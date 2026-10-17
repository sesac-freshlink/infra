# GitHub Actions 켜고 끄기 워크플로(infra 레포 .github/workflows/dev-cluster.yml)가 맡는 IAM Role.
# 이 Role로 envs/<env>/cluster를 apply·destroy한다(EKS·NAT·IRSA Role·Helm).
# 장기 액세스 키 없이 GitHub OIDC로 들어온다. infra 레포 main 브랜치에서 돈 작업만 맡을 수 있다(PR 브랜치·포크 불가).
# 유지 묶음에 둔다: 클러스터를 지워도 남아 있어야 월요일에 다시 만들 수 있다.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  iam_prefix = "arn:${local.partition}:iam::${local.account_id}"
}

# global 묶음이 만든 GitHub OIDC 공급자(계정에 하나)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "assume" {
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
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name_prefix}-cluster-actions"
  description          = "GitHub Actions ${var.github_repository} main: apply/destroy ${var.name_prefix} cluster bundle"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 7200 # EKS 생성·삭제 15~20분 + Helm. 기본 1시간이면 충분하지만 여유를 둔다
}

# EKS·EC2(NAT)·ELB·S3(state)·SQS 조회 등. IAM·Organizations·계정 설정은 빠져 있다.
resource "aws_iam_role_policy_attachment" "power_user" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

# cluster 묶음이 만드는 IAM 리소스(이름이 <name_prefix>-로 시작)만 다룬다.
data "aws_iam_policy_document" "iam" {
  statement {
    sid = "ManageEnvRolesAndPolicies"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListInstanceProfilesForRole", "iam:PassRole",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:TagPolicy", "iam:UntagPolicy", "iam:ListPolicyTags",
    ]
    resources = [
      "${local.iam_prefix}:role/${var.name_prefix}-*",
      "${local.iam_prefix}:policy/${var.name_prefix}-*",
    ]
  }

  # 자기 Role의 권한·신뢰 정책은 바꾸지 못하게 한다.
  statement {
    sid       = "DenySelfModify"
    effect    = "Deny"
    actions   = ["iam:UpdateAssumeRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRole"]
    resources = [aws_iam_role.this.arn]
  }

  statement {
    sid = "ManageEksOidcProvider"
    actions = [
      "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider", "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = ["${local.iam_prefix}:oidc-provider/oidc.eks.*"]
  }

  # 정책 내용 조회(AWS 관리형 정책 붙이기 전 확인)
  statement {
    sid       = "ReadAwsManagedPolicies"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = ["arn:${local.partition}:iam::aws:policy/*"]
  }

  statement {
    sid       = "CreateServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"] # 서비스 연결 Role ARN은 서비스마다 경로가 달라 아래 조건으로 좁힌다
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "elasticloadbalancing.amazonaws.com", "autoscaling.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "iam" {
  name        = "${var.name_prefix}-cluster-actions-iam"
  description = "IAM for ${var.name_prefix} cluster bundle (roles/policies named ${var.name_prefix}-*, EKS OIDC providers)"
  policy      = data.aws_iam_policy_document.iam.json
}

resource "aws_iam_role_policy_attachment" "iam" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.iam.arn
}
