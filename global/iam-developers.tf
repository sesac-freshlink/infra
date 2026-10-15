# 팀원 IAM 권한: 그룹 freshlink-developers.
# - 팀원은 새싹이 발급한 기존 IAM 사용자(sesac-cN)를 그대로 쓴다. Terraform은 사용자를 만들지 않고 그룹에 넣기만 한다.
# - 새싹 기본 그룹 sesac-c에는 AdministratorAccess가 붙어 있다. 팀원을 그 그룹에서 빼야 아래 dev 전용 권한만 남는다.
#   그룹에서 빼는 것은 Terraform 밖에서 사람이 한 번 한다(README 5-1). sesac-c 그룹은 새싹 관리라 Terraform으로 건드리지 않는다.
# - MFA를 켜기 전에는 비밀번호 바꾸기·MFA 등록 말고는 아무것도 못 한다.
# - 권한은 dev 리소스만. prod 리소스는 읽기 권한도 없다(허용 문장이 없으면 기본 거부).

locals {
  arn_prefix             = "arn:${local.partition}"
  dev_access_policy_name = "freshlink-dev-access"
}

resource "aws_iam_group" "developers" {
  name = "freshlink-developers"
  path = "/freshlink/"
}

data "aws_iam_user" "developer" {
  for_each = var.developers

  user_name = each.value.iam_user
}

# 다른 그룹 소속(sesac-c 등)은 건드리지 않고 freshlink-developers만 더한다.
resource "aws_iam_user_group_membership" "developer" {
  for_each = data.aws_iam_user.developer

  user   = each.value.user_name
  groups = [aws_iam_group.developers.name]
}

# 비밀번호 정책(계정 전체). 콘솔 첫 로그인 때 새 비밀번호로 바꾸게 한다.
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 5
}

# ---------------------------------------------------------------------------
# 1) MFA 필수: AWS 공식 예시(BlockMostAccessUnlessSignedInWithMFA)를 따른다
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "require_mfa" {
  statement {
    sid       = "AllowViewAccountInfo"
    actions   = ["iam:GetAccountPasswordPolicy", "iam:ListVirtualMFADevices"]
    resources = ["*"] # 두 API 모두 리소스 단위 권한을 지원하지 않는다
  }

  statement {
    sid = "AllowManageOwnPasswordAndKeys"
    actions = [
      "iam:ChangePassword",
      "iam:GetUser",
      "iam:GetLoginProfile",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:ListAccessKeys",
      "iam:UpdateAccessKey",
      "iam:GetAccessKeyLastUsed",
    ]
    resources = ["${local.arn_prefix}:iam::${local.account_id}:user/$${aws:username}"]
  }

  statement {
    sid       = "AllowManageOwnVirtualMFADevice"
    actions   = ["iam:CreateVirtualMFADevice"]
    resources = ["${local.arn_prefix}:iam::${local.account_id}:mfa/*"]
  }

  statement {
    sid = "AllowManageOwnUserMFA"
    actions = [
      "iam:DeactivateMFADevice",
      "iam:EnableMFADevice",
      "iam:GetMFADevice",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
    ]
    resources = ["${local.arn_prefix}:iam::${local.account_id}:user/$${aws:username}"]
  }

  statement {
    sid    = "DenyAllExceptListedIfNoMFA"
    effect = "Deny"
    not_actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:GetUser",
      "iam:GetMFADevice",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:ResyncMFADevice",
      "iam:ChangePassword",
      "iam:GetAccountPasswordPolicy",
      "sts:GetSessionToken",
    ]
    resources = ["*"]
    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "require_mfa" {
  name        = "freshlink-require-mfa"
  path        = "/freshlink/"
  description = "MFA 없이는 비밀번호 변경·MFA 등록 외 모든 요청을 거부한다"
  policy      = data.aws_iam_policy_document.require_mfa.json
}

# ---------------------------------------------------------------------------
# 2) dev 리소스만: 이름 접두사(dev-, freshlink-dev-) 또는 태그 Environment=dev로 좁힌다.
#    envs/dev/* 루트는 provider default_tags에 Environment = "dev"를 넣어야 한다.
#    CloudWatch 지표(GetMetricData·ListMetrics)와 각종 List* API는 리소스 단위로 좁힐 수 없어
#    prod까지 보이게 되므로 넣지 않는다. 지표는 dev Grafana로 본다.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "dev_access" {
  statement {
    sid = "DevQueues"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:ListQueueTags",
      "sqs:ListDeadLetterSourceQueues",
      "sqs:PurgeQueue",
      "sqs:StartMessageMoveTask",
      "sqs:ListMessageMoveTasks",
      "sqs:CancelMessageMoveTask",
    ]
    resources = ["${local.arn_prefix}:sqs:${local.region}:${local.account_id}:dev-*"]
  }

  statement {
    sid       = "DevSecretsRead"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["${local.arn_prefix}:secretsmanager:${local.region}:${local.account_id}:secret:freshlink-dev-*"]
  }

  statement {
    sid = "DevCognitoRead"
    actions = [
      "cognito-idp:DescribeUserPool",
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:ListUserPoolClients",
      "cognito-idp:ListUsers",
      "cognito-idp:AdminGetUser",
      "cognito-idp:ListGroups",
      "cognito-idp:GetGroup",
      "cognito-idp:ListUsersInGroup",
      "cognito-idp:AdminListGroupsForUser",
    ]
    resources = ["${local.arn_prefix}:cognito-idp:${local.region}:${local.account_id}:userpool/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  # SSM 포트 포워딩(RDS 접속용 t4g.nano). 셸 세션 문서는 주지 않는다.
  statement {
    sid       = "DevSsmStartSessionOnDevInstances"
    actions   = ["ssm:StartSession"]
    resources = ["${local.arn_prefix}:ec2:${local.region}:${local.account_id}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Environment"
      values   = ["dev"]
    }
    condition {
      test     = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"
      values   = ["true"]
    }
  }

  statement {
    sid     = "DevSsmPortForwardDocuments"
    actions = ["ssm:StartSession"]
    resources = [
      "${local.arn_prefix}:ssm:${local.region}::document/AWS-StartPortForwardingSessionToRemoteHost",
      "${local.arn_prefix}:ssm:${local.region}::document/AWS-StartPortForwardingSession",
    ]
  }

  statement {
    sid       = "OwnSsmSessions"
    actions   = ["ssm:TerminateSession", "ssm:ResumeSession"]
    resources = ["${local.arn_prefix}:ssm:${local.region}:${local.account_id}:session/$${aws:username}-*"]
  }

  statement {
    sid = "DevLogsRead"
    actions = [
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
      "logs:StartQuery",
      "logs:StartLiveTail",
    ]
    resources = [
      "${local.arn_prefix}:logs:${local.region}:${local.account_id}:log-group:*freshlink-dev-*",
      "${local.arn_prefix}:logs:${local.region}:${local.account_id}:log-group:*freshlink-dev-*:log-stream:*",
    ]
  }

  statement {
    sid       = "LogsQueryResults"
    actions   = ["logs:GetQueryResults", "logs:StopQuery", "logs:StopLiveTail"]
    resources = ["*"] # 쿼리 ID로만 동작하고 리소스 단위 권한을 지원하지 않는다. 시작은 위에서 dev로 막힌다
  }
}

resource "aws_iam_policy" "dev_access" {
  name        = local.dev_access_policy_name
  path        = "/freshlink/"
  description = "팀원용 dev 리소스 권한 (dev-* SQS, freshlink-dev-* 비밀 읽기, dev Cognito 조회, SSM 포트 포워딩, dev 로그 읽기)"
  policy      = data.aws_iam_policy_document.dev_access.json
}

resource "aws_iam_group_policy_attachment" "require_mfa" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.require_mfa.arn
}

resource "aws_iam_group_policy_attachment" "dev_access" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.dev_access.arn
}
