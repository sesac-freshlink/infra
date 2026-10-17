# 서비스 CI(.github 레포 spring-build.yml)가 맡는 IAM Role (할 일 8). dev·prod 공용 ECR에 이미지를 올리는 권한만 있다.
# - 서비스 레포 5개의 dev·main 브랜치에서 돈 작업만 맡을 수 있다(PR 브랜치·포크 불가).
#   재사용 워크플로라도 OIDC 토큰의 sub는 부른 쪽(서비스 레포) 기준이다.
# - prod 쓰기 권한(prod 버킷, prod terraform)은 주지 않는다. main 머지 때 하는 태그 승격(할 일 15)은 gitops 커밋뿐이라 AWS 권한이 필요 없다.
# - 클러스터 접근 권한도 없다. 배포는 gitops 커밋 → ArgoCD가 끌어간다.
# - 이름이 freshlink-dev-*가 아니어서 켜고 끄기 워크플로 Role(freshlink-dev-* IAM만 수정 가능)이 이 Role을 바꿀 수 없다.

locals {
  ci_branches = ["dev", "main"]
  # 조직 설정에 따라 sub가 "repo:<조직>/<레포>:..." 또는 ID가 붙은 "repo:<조직>@<ID>/<레포>@<ID>:..."로 온다(할 일 7에서 확인).
  # 두 모양을 다 받는다. 조직·레포 이름과 브랜치는 고정이라 다른 조직·브랜치는 맞지 않는다.
  ci_subjects = flatten([
    for repo in var.ecr_repositories : [
      for branch in local.ci_branches : [
        "repo:${var.github_org}/${repo}:ref:refs/heads/${branch}",
        "repo:${var.github_org}@*/${repo}@*:ref:refs/heads/${branch}",
      ]
    ]
  ])
}

data "aws_iam_policy_document" "ci_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.ci_subjects
    }
  }
}

resource "aws_iam_role" "ci_ecr_push" {
  name                 = "freshlink-ci-ecr-push"
  description          = "GitHub Actions service repos dev/main: push images to ECR"
  assume_role_policy   = data.aws_iam_policy_document.ci_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ci_ecr_push" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # 리소스를 지정할 수 없는 동작
  }
  statement {
    sid = "PushServiceImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = values(module.ecr.repository_arns)
  }
}

resource "aws_iam_role_policy" "ci_ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.ci_ecr_push.id
  policy = data.aws_iam_policy_document.ci_ecr_push.json
}
