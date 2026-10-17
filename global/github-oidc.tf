# GitHub Actions가 장기 키 없이 AWS에 들어오는 OIDC 공급자. 계정에 하나만 둔다.
# 이 공급자를 믿는 Role: 서비스 CI(github-ci.tf, 할 일 8), 켜고 끄기 워크플로(modules/cluster-actions, 할 일 7).
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list는 비워 둔다. AWS가 GitHub OIDC는 신뢰 CA로 직접 검증한다.
}
