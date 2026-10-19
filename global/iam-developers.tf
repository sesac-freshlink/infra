# 팀원 IAM 사용자와 그룹 freshlink-developers.
# - MFA는 강제하지 않는다(콘솔·CLI 모두). CLI는 액세스 키 하나로 바로 쓴다.
# - 권한은 dev 리소스만. prod 리소스는 읽기 권한도 없다(허용 문장이 없으면 기본 거부).
# - 콘솔 비밀번호·액세스 키는 Terraform으로 만들지 않는다(state에 비밀이 남지 않게). 첫 비밀번호는 README 5-1 명령으로, 액세스 키는 팀원이 직접 만든다(5-2).
# 팀원이 빠지면 var.developers에서 지우고 apply한다(force_destroy로 키·MFA까지 같이 지운다).

locals {
  arn_prefix             = "arn:${local.partition}"
  dev_access_policy_name = "freshlink-dev-access"
}

resource "aws_iam_group" "developers" {
  name = "freshlink-developers"
  path = "/freshlink/"
}

resource "aws_iam_user" "developer" {
  for_each = var.developers

  name          = "freshlink-${each.key}"
  path          = "/freshlink/"
  force_destroy = true

  tags = {
    DeveloperId = each.key
    FullName    = each.value
  }
}

resource "aws_iam_user_group_membership" "developer" {
  for_each = aws_iam_user.developer

  user   = each.value.name
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
# 1) 본인 비밀번호·액세스 키·MFA 관리 (MFA는 강제하지 않는다. 등록은 각자 선택)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "self_service" {
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
    resources = ["${local.arn_prefix}:iam::${local.account_id}:user/freshlink/$${aws:username}"]
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
    resources = ["${local.arn_prefix}:iam::${local.account_id}:user/freshlink/$${aws:username}"]
  }
}

resource "aws_iam_policy" "self_service" {
  name        = "freshlink-self-service"
  path        = "/freshlink/"
  description = "본인 비밀번호·액세스 키·MFA 기기 관리"
  policy      = data.aws_iam_policy_document.self_service.json
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

  # member-service를 PC에서 dev에 붙여 시험할 때(점주 등록 AD-01) 쓰는 사용자 관리 권한.
  # 클러스터의 member IRSA 정책(freshlink-dev-member-cognito)과 같은 동작이고, 태그 Environment=dev인 User Pool만.
  # (정책 description은 바꾸면 정책이 다시 만들어지므로 그대로 둔다)
  statement {
    sid = "DevCognitoUserAdmin"
    actions = [
      "cognito-idp:AdminCreateUser",
      "cognito-idp:AdminSetUserPassword",
      "cognito-idp:AdminUpdateUserAttributes",
      "cognito-idp:AdminAddUserToGroup",
      "cognito-idp:AdminDeleteUser",
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

resource "aws_iam_group_policy_attachment" "self_service" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.self_service.arn
}

resource "aws_iam_group_policy_attachment" "dev_access" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.dev_access.arn
}
