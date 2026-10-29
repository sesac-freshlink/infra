# Cognito User Pool 1개(이메일 로그인), 그룹 OWNER·CUSTOMER·ADMIN, custom:storeId, 브라우저용 앱 클라이언트(시크릿 없음),
# 가입 확인 트리거 Lambda, member-service가 맡을 Cognito 관리자 정책, 시드 계정 비밀.
# BFF(10/28 결정): gateway용 앱 클라이언트 bff(시크릿 있음)와 그 시크릿 비밀, 로그인 도메인, 구글 IdP.
# 결정 근거: .github docs/기술스택과 선택이유.md 3-7

locals {
  pool_name     = "${var.name_prefix}-users"
  function_name = "${var.name_prefix}-post-confirmation"
}

# ---------------------------------------------------------------------------
# User Pool
# ---------------------------------------------------------------------------
resource "aws_cognito_user_pool" "this" {
  name = local.pool_name

  # Lite 요금제: 월간 활성 사용자 1만 명까지 무료. 액세스 토큰 맞춤(Essentials)은 쓰지 않는다(3-7 토큰 항목)
  user_pool_tier      = "LITE"
  deletion_protection = var.deletion_protection

  # 이메일을 아이디로 쓰고, 가입 때 이메일 인증 코드로 확인한다
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  # 회원가입 화면 규칙(member M1)과 같다: 8자 이상, 대문자·소문자·숫자·특수문자
  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # 고객만 직접 가입한다. 점주·관리자는 AdminCreateUser
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Cognito 기본 메일(하루 50통 한도). 실서비스 규모가 되면 SES로 바꾼다
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "[FreshLink] 가입 인증 코드"
    email_message        = "FreshLink 가입 인증 코드는 {####} 입니다."
  }

  # 점주의 점포 ID(숫자 문자열 "1"). 앱 클라이언트는 읽기만 한다(아래 write_attributes에서 뺀다).
  # 사용자 속성은 만든 뒤 지우거나 이름을 바꿀 수 없다.
  schema {
    name                     = "storeId"
    attribute_data_type      = "String"
    mutable                  = true
    developer_only_attribute = false
    required                 = false

    string_attribute_constraints {
      min_length = 1
      max_length = 20
    }
  }

  lambda_config {
    post_confirmation = aws_lambda_function.post_confirmation.arn
  }
}

resource "aws_cognito_user_group" "this" {
  for_each = var.groups

  user_pool_id = aws_cognito_user_pool.this.id
  name         = each.key
  description  = each.value
}

# 브라우저(Amplify)용 공개 클라이언트. 시크릿 없음, SRP 로그인
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.name_prefix}-web"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false
  explicit_auth_flows = concat(
    ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"],
    var.admin_password_auth ? ["ALLOW_ADMIN_USER_PASSWORD_AUTH"] : [],
  )
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  id_token_validity      = var.id_token_validity_hours
  access_token_validity  = var.id_token_validity_hours
  refresh_token_validity = var.refresh_token_validity_days
  token_validity_units {
    id_token      = "hours"
    access_token  = "hours"
    refresh_token = "days"
  }

  # ID 토큰에 custom:storeId가 들어가려면 읽기 속성에 있어야 한다. 쓰기 속성에는 넣지 않는다(화면이 점포를 바꾸지 못하게)
  read_attributes  = ["email", "email_verified", "custom:storeId"]
  write_attributes = ["email"]
}

# ---------------------------------------------------------------------------
# BFF: gateway가 로그인·갱신을 대신 하는 서버용 클라이언트 (10/28 결정, .github docs/BFF-인수인계.md)
# 프론트를 다 옮길 때까지 web 클라이언트와 같이 둔다. 다 옮기면 web을 지운다.
# ---------------------------------------------------------------------------
data "aws_region" "current" {}

# 로그인 도메인(구글 로그인 리디렉트용). 주소 https://<접두사>.auth.<리전>.amazoncognito.com
# 구글 OAuth 클라이언트의 리디렉션 URI가 이 주소 + /oauth2/idpresponse 라서 접두사를 바꾸면 구글 콘솔도 고쳐야 한다.
# managed_login_version 1 = 기존 Hosted UI(Lite 요금제에서 쓸 수 있다). 화면은 쓰지 않고 구글로 바로 넘긴다.
resource "aws_cognito_user_pool_domain" "this" {
  domain                = var.domain_prefix
  user_pool_id          = aws_cognito_user_pool.this.id
  managed_login_version = 1
}

# 구글 OAuth 클라이언트 ID·시크릿. Terraform 코드에 쓰지 않고 scripts/set-google-oauth.ps1이 Secrets Manager에 넣는다.
# 비밀이 아직 없으면 구글 IdP 없이 만들고, 스크립트로 비밀을 넣은 뒤 다시 apply하면 구글 IdP가 생긴다.
# google_secret_name이 null이면 구글 로그인을 만들지 않는다.
data "aws_secretsmanager_secrets" "google" {
  count = var.google_secret_name == null ? 0 : 1
  filter {
    name   = "name"
    values = [var.google_secret_name]
  }
}

locals {
  google_secret_exists = var.google_secret_name != null && contains(try(data.aws_secretsmanager_secrets.google[0].names, []), var.google_secret_name)
}

data "aws_secretsmanager_secret_version" "google" {
  count     = local.google_secret_exists ? 1 : 0
  secret_id = var.google_secret_name
}

locals {
  google = local.google_secret_exists ? jsondecode(data.aws_secretsmanager_secret_version.google[0].secret_string) : null
}

resource "aws_cognito_identity_provider" "google" {
  count = local.google_secret_exists ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.this.id
  provider_name = "Google"
  provider_type = "Google"

  # client_id·client_secret·authorize_scopes 말고는 Cognito가 채우는 값이다. 적어 두지 않으면 plan마다 바뀐다고 나온다
  provider_details = {
    client_id                     = local.google.clientId
    client_secret                 = local.google.clientSecret
    authorize_scopes              = "openid email profile"
    attributes_url                = "https://people.googleapis.com/v1/people/me?personFields="
    attributes_url_add_attributes = "true"
    authorize_url                 = "https://accounts.google.com/o/oauth2/v2/auth"
    oidc_issuer                   = "https://accounts.google.com"
    token_request_method          = "POST"
    token_url                     = "https://www.googleapis.com/oauth2/v4/token"
  }

  # Cognito에는 이메일만 둔다(이름은 member DB, 10/21 결정). 매핑한 속성은 bff 클라이언트 write_attributes에 있어야 한다
  attribute_mapping = {
    username = "sub"
    email    = "email"
  }
}

resource "aws_cognito_user_pool_client" "bff" {
  name         = "${var.name_prefix}-bff"
  user_pool_id = aws_cognito_user_pool.this.id

  # 시크릿이 있어서 SignUp·ConfirmSignUp·AdminInitiateAuth에 SECRET_HASH를 붙여야 한다
  generate_secret               = true
  explicit_auth_flows           = ["ALLOW_ADMIN_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  # 토큰 기간·속성은 web과 같다. gateway 쿠키 만료가 이 값을 따른다
  id_token_validity      = var.id_token_validity_hours
  access_token_validity  = var.id_token_validity_hours
  refresh_token_validity = var.refresh_token_validity_days
  token_validity_units {
    id_token      = "hours"
    access_token  = "hours"
    refresh_token = "days"
  }

  read_attributes  = ["email", "email_verified", "custom:storeId"]
  write_attributes = ["email"]

  # 구글 로그인: gateway /api/auth/google → 로그인 도메인 /oauth2/authorize → 구글 → /api/auth/callback?code=
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = concat(["COGNITO"], aws_cognito_identity_provider.google[*].provider_name)
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
}

# bff 클라이언트 ID·시크릿 → gateway 파드(ExternalSecret → COGNITO_CLIENT_SECRET). output에는 시크릿을 내보내지 않는다
resource "aws_secretsmanager_secret" "gateway_cognito" {
  name                    = "${var.name_prefix}/gateway/cognito"
  description             = "gateway BFF: Cognito app client ${aws_cognito_user_pool_client.bff.name} (clientId, clientSecret)"
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "gateway_cognito" {
  secret_id = aws_secretsmanager_secret.gateway_cognito.id
  secret_string = jsonencode({
    clientId     = aws_cognito_user_pool_client.bff.id
    clientSecret = aws_cognito_user_pool_client.bff.client_secret
  })
}

# ---------------------------------------------------------------------------
# 가입 확인 트리거 Lambda
# ---------------------------------------------------------------------------
data "archive_file" "post_confirmation" {
  type        = "zip"
  source_file = "${path.module}/lambda/post_confirmation.py"
  output_path = "${path.module}/.build/post_confirmation.zip"
}

resource "aws_cloudwatch_log_group" "post_confirmation" {
  # 이름에 freshlink-<env>-가 들어가야 팀원이 dev 로그를 읽을 수 있다(global iam-developers)
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.lambda_log_retention_days
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "post_confirmation" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "post_confirmation" {
  statement {
    sid       = "AddToGroupInThisPool"
    actions   = ["cognito-idp:AdminAddUserToGroup"]
    resources = [aws_cognito_user_pool.this.arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.post_confirmation.arn}:*"]
  }
}

resource "aws_iam_role_policy" "post_confirmation" {
  name   = "post-confirmation"
  role   = aws_iam_role.post_confirmation.id
  policy = data.aws_iam_policy_document.post_confirmation.json
}

resource "aws_lambda_function" "post_confirmation" {
  function_name    = local.function_name
  description      = "Cognito Post Confirmation: self sign-up -> ${var.self_signup_group} group"
  role             = aws_iam_role.post_confirmation.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "post_confirmation.handler"
  filename         = data.archive_file.post_confirmation.output_path
  source_code_hash = data.archive_file.post_confirmation.output_base64sha256
  memory_size      = 128
  timeout          = 5

  environment {
    variables = {
      SELF_SIGNUP_GROUP = var.self_signup_group
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.post_confirmation.name
  }
}

resource "aws_lambda_permission" "cognito" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_confirmation.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this.arn
}

# ---------------------------------------------------------------------------
# member-service용 Cognito 관리자 정책 (이 User Pool만)
# EKS 클러스터와 IRSA Role은 클러스터 묶음(할 일 7)에서 만든다. 그때 Role freshlink-<env>-member-service-irsa에
# 이 정책 ARN(output member_cognito_policy_arn)을 붙인다.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "member_cognito" {
  statement {
    sid = "ManageUsersInThisPool"
    actions = [
      "cognito-idp:AdminCreateUser",           # 점주 계정 만들기 (AD-01 3단계)
      "cognito-idp:AdminSetUserPassword",      # 초기 비밀번호를 영구 비밀번호로
      "cognito-idp:AdminUpdateUserAttributes", # custom:storeId, email_verified
      "cognito-idp:AdminAddUserToGroup",       # OWNER 그룹
      "cognito-idp:AdminGetUser",              # 이메일 중복 확인·sub 확인
      "cognito-idp:ListUsers",                 # 이메일로 기존 계정 찾기 (미인증 포함)
      "cognito-idp:AdminListGroupsForUser",
      "cognito-idp:AdminDeleteUser", # 등록 실패 때 이번 요청이 만든 계정 정리
    ]
    resources = [aws_cognito_user_pool.this.arn]
  }
}

resource "aws_iam_policy" "member_cognito" {
  name        = "${var.name_prefix}-member-cognito"
  path        = "/freshlink/"
  description = "member-service: ${local.pool_name} user admin (create owner, group, storeId, cleanup)"
  policy      = data.aws_iam_policy_document.member_cognito.json
}

# ---------------------------------------------------------------------------
# 시드 계정(관리자 1·점주 3) 자격. 값은 scripts/seed-cognito.ps1이 넣는다(state·레포에 남지 않게)
# 이름이 freshlink-<env>-로 시작해서 팀원도 dev 비밀로 읽을 수 있다(시험 로그인용)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "seed_accounts" {
  name                    = "${var.name_prefix}-seed-accounts"
  description             = "Seed Cognito accounts for ${local.pool_name} (admin 1, owners 3): email, password, sub, storeId"
  recovery_window_in_days = var.secret_recovery_window_days
}
