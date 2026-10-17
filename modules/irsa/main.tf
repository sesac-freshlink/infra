# IRSA Role: 쿠버네티스 ServiceAccount 하나가 맡는 IAM Role.
# Role마다 신뢰 정책을 그 네임스페이스·ServiceAccount 하나로 좁힌다. 권한은 인라인이 아닌 관리형 정책으로 붙인다.

locals {
  issuer_host = replace(var.oidc_issuer, "https://", "")

  # Role 키 → 붙일 정책 ARN 목록을 (키, ARN) 쌍으로 편다
  attachments = merge([
    for k, r in var.roles : {
      for i, arn in r.policy_arns : "${k}/${i}" => { role = k, policy_arn = arn }
    }
  ]...)
}

data "aws_iam_policy_document" "assume" {
  for_each = var.roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.roles

  name               = "${var.name_prefix}-${each.key}-irsa"
  description        = "IRSA for ${each.value.namespace}/${each.value.service_account}"
  assume_role_policy = data.aws_iam_policy_document.assume[each.key].json
}

resource "aws_iam_policy" "this" {
  for_each = { for k, r in var.roles : k => r if r.policy_json != null }

  name        = "${var.name_prefix}-${each.key}-irsa"
  description = "Permissions for ${each.value.namespace}/${each.value.service_account}"
  policy      = each.value.policy_json
}

resource "aws_iam_role_policy_attachment" "own" {
  for_each = aws_iam_policy.this

  role       = aws_iam_role.this[each.key].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each = local.attachments

  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.policy_arn
}
