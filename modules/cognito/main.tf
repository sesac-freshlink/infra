# Cognito User Pool 1개(이메일 로그인), 그룹 OWNER·CUSTOMER·ADMIN, custom:storeId, 브라우저용 앱 클라이언트(시크릿 없음),
# 가입 확인 트리거 Lambda, member-service가 맡을 Cognito 관리자 정책, 시드 계정 비밀.
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
