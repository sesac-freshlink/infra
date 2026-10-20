# 관측성(I-03) 중 AWS 쪽: Loki 로그 버킷(S3) 하나. persistent 묶음에서 부른다.
# 클러스터를 지워도 로그가 남게 버킷은 유지 묶음에 둔다. Loki 자체와 Prometheus·Grafana·Zipkin은 gitops(ArgoCD)가 설치한다.
# 버킷을 읽고 쓰는 IRSA Role(freshlink-<env>-loki-irsa)은 OIDC 공급자와 같이 생기고 지워지므로 cluster 묶음에 있다.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "loki" {
  # 버킷 이름은 전 세계에서 유일해야 해서 state 버킷과 같은 규칙으로 계정 ID 끝 4자리를 붙인다
  bucket        = "${var.name_prefix}-loki-logs-${substr(data.aws_caller_identity.current.account_id, 8, 4)}"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Loki compactor가 보관 기간(retention_period)이 지난 로그를 지운다. 수명 주기는 그보다 하루 늦게 남은 것을 치우는 안전망이다.
resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = var.log_retention_days + 1
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}
