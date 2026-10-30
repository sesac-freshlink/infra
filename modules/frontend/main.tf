# 프론트 진입점 (I-11): S3(React 빌드 파일, 비공개) + CloudFront 하나.
# - 기본 동작 → S3 (OAC로만 읽는다). 확장자 없는 경로는 CloudFront Function이 /index.html로 바꾼다(SPA 경로).
# - /api/* → ALB(gateway Ingress). 캐시하지 않고 Authorization·Idempotency-Key 헤더와 쿼리를 그대로 넘긴다.
# ALB는 클러스터 안의 컨트롤러가 만들어서 클러스터를 새로 만들 때마다 주소가 바뀐다. 그래서 /api 오리진 주소는
# Terraform이 아니라 scripts/sync-api-origin.sh(켜고 끄기 워크플로의 create 단계)가 맞춘다. Terraform은 이 칸을 건드리지 않는다.
# 도메인이 없어서 ACM 인증서는 쓰지 않고 CloudFront 기본 주소(https://<id>.cloudfront.net)를 쓴다.
# 기본 동작(화면)에는 보안 헤더·CSP 응답 헤더 정책을 붙인다(README 4-18).
# 점포 이미지는 같은 버킷의 images/ 아래에 둔다(README 4-20). member-service가 presigned PUT URL을 주면 브라우저가 버킷에 바로 올리고,
# 화면은 같은 주소의 /images/...로 읽는다. 배포(frontend-deploy.yml)의 s3 sync --delete는 images/를 건너뛴다.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  s3_origin_id  = "s3"
  images_prefix = "images/" # 점포 이미지. 빌드 파일과 섞이지 않게 이 경로만 쓴다

  # 브라우저가 presigned URL로 올릴 때 부르는 버킷 주소 (presigned URL의 호스트)
  bucket_regional_url = "https://${aws_s3_bucket.site.bucket_regional_domain_name}"
  api_origin_id       = "api"

  # AWS 관리형 정책 ID (모든 계정 공통)
  cache_policy_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  origin_request_all_viewer_host = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader

  # 화면이 실제로 부르는 곳만 연다. API·로그인(BFF)·알림 SSE는 같은 주소의 /api라 'self'로 된다.
  # 구글 로그인은 Cognito 로그인 도메인으로 페이지를 옮기는 것(navigation)이라 CSP와 상관없다.
  # 토스 결제위젯: SDK가 js.tosspayments.com 스크립트를 받고, 결제 수단·약관·결제창은 *.tosspayments.com iframe이다.
  # 카카오맵: SDK(dapi.kakao.com)가 지도 스크립트를 t1.daumcdn.net에서 더 받는다. 지도 타일은 이미지라 img-src https:로 된다.
  # 점포 이미지 올리기: 브라우저가 presigned URL로 이 버킷에 PUT 한다(connect-src). 읽기는 같은 주소 /images/라 'self'.
  content_security_policy = join("; ", [
    "default-src 'self'",
    "script-src 'self' https://js.tosspayments.com https://dapi.kakao.com https://t1.daumcdn.net",
    join(" ", concat(["connect-src 'self' https://*.tosspayments.com ${local.bucket_regional_url}"], var.csp_extra_connect_src)),
    "frame-src https://*.tosspayments.com",
    "img-src 'self' data: https:", # 상품 이미지가 외부 주소(NCP 등)라 https 전체
    "style-src 'self' 'unsafe-inline'",
    "object-src 'none'",
    "base-uri 'self'",
    "frame-ancestors 'none'",
  ])
}

# ---------------------------------------------------------------- S3

resource "aws_s3_bucket" "site" {
  # 버킷 이름은 전 세계에서 유일해야 해서 state 버킷과 같은 규칙으로 계정 ID 끝 4자리를 붙인다
  bucket        = "${var.name_prefix}-frontend-${substr(local.account_id, 8, 4)}"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudFront(이 배포 하나)만 읽을 수 있다
data "aws_iam_policy_document" "site" {
  statement {
    sid       = "CloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

# 점포 이미지 올리기(presigned PUT)는 다른 주소(버킷)로 가는 요청이라 CORS가 필요하다. 화면 주소에서 오는 PUT만 받는다
resource "aws_s3_bucket_cors_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = ["https://${aws_cloudfront_distribution.this.domain_name}"]
    allowed_headers = ["Content-Type"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---------------------------------------------------------------- CloudFront

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.name_prefix}-frontend"
  description                       = "${var.name_prefix} frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 확장자가 없는 경로(/owner/inventory 같은 React 라우트)는 index.html을 준다. /api/*에는 붙이지 않는다.
resource "aws_cloudfront_function" "spa" {
  name    = "${var.name_prefix}-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "SPA routes -> /index.html"
  publish = true
  code    = file("${path.module}/spa-rewrite.js")
}

# /api/*: 실제로는 캐시하지 않는다(기본 TTL 0, gateway 응답에 Cache-Control: no-store).
# Authorization 헤더는 오리진 요청 정책으로는 넘길 수 없고 캐시 정책에 넣어야 넘어간다. 최대 TTL이 0이면 헤더를 넣을 수 없어서 1초로 둔다.
resource "aws_cloudfront_cache_policy" "api" {
  name        = "${var.name_prefix}-api"
  comment     = "API: no cache, forward Authorization"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization"]
      }
    }
    cookies_config {
      cookie_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

# 화면(S3) 응답에 붙이는 보안 헤더. /api 응답에는 붙이지 않는다(gateway가 정한다).
# CSP는 처음에 Report-Only로 건다: 막지 않고 브라우저 콘솔에 "막혔을 주소"만 찍는다. 확인 뒤 csp_report_only = false.
resource "aws_cloudfront_response_headers_policy" "site" {
  name    = "${var.name_prefix}-site-security"
  comment = "HSTS, nosniff, DENY, referrer, CSP${var.csp_report_only ? " (report-only)" : ""}"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000 # 1년
      include_subdomains         = true
      preload                    = false # 도메인을 사기 전이라 preload 목록에는 넣지 않는다
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    dynamic "content_security_policy" {
      for_each = var.csp_report_only ? [] : [1]
      content {
        content_security_policy = local.content_security_policy
        override                = true
      }
    }
  }

  # Report-Only 헤더는 보안 헤더 칸에 없어서 사용자 지정 헤더로 넣는다
  dynamic "custom_headers_config" {
    for_each = var.csp_report_only ? [1] : []
    content {
      items {
        header   = "Content-Security-Policy-Report-Only"
        value    = local.content_security_policy
        override = true
      }
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "${var.name_prefix}-frontend" # scripts/sync-api-origin.sh가 이 값으로 배포를 찾는다
  default_root_object = "index.html"
  price_class         = var.price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  # 클러스터가 없을 때의 자리 표시. 버킷 주소로 두면 /api 요청이 AWS 밖으로 나가지 않는다(S3가 403을 준다).
  # 클러스터를 만들면 sync-api-origin.sh가 gateway ALB 주소로 바꾼다.
  origin {
    origin_id   = local.api_origin_id
    domain_name = aws_s3_bucket.site.bucket_regional_domain_name
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  default_cache_behavior {
    target_origin_id           = local.s3_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.cache_policy_caching_optimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa.arn
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = local.api_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = aws_cloudfront_cache_policy.api.id
    origin_request_policy_id = local.origin_request_all_viewer_host # Idempotency-Key 등 나머지 헤더·쿼리·쿠키
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # /api 오리진 주소는 sync-api-origin.sh가 맞춘다. Terraform이 매번 자리 표시로 되돌리지 않게 오리진 칸 전체를 무시한다.
  # S3 오리진을 바꿔야 하면 이 줄을 잠시 빼고 apply한 뒤 sync-api-origin.sh를 다시 돌린다.
  lifecycle {
    ignore_changes = [origin]
  }
}

# ---------------------------------------------------------------- 배포 Role (frontend 레포 frontend-deploy.yml)

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # sub가 옛 형식이거나 ID가 붙은 형식(immutable subject)으로 온다. 둘 다 받는다(global/github-ci.tf와 같다)
      values = [
        "repo:${var.github_org}/frontend:ref:refs/heads/${var.deploy_branch}",
        "repo:${var.github_org}@*/frontend@*:ref:refs/heads/${var.deploy_branch}",
      ]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.name_prefix}-frontend-deploy"
  description          = "GitHub Actions frontend ${var.deploy_branch}: upload build to ${var.name_prefix} bucket"
  assume_role_policy   = data.aws_iam_policy_document.deploy_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
  }
  statement {
    sid       = "WriteObjects"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }
  statement {
    sid       = "Invalidate"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation", "cloudfront:GetDistribution"]
    resources = [aws_cloudfront_distribution.this.arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "frontend-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
