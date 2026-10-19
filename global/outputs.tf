output "tfstate_bucket" {
  description = "Terraform state 버킷 이름 (backend.hcl의 bucket 값)"
  value       = aws_s3_bucket.tfstate.bucket
}

output "ecr_repository_urls" {
  description = "ECR 리포지토리 주소 (서비스 CI, gitops values에서 쓴다)"
  value       = module.ecr.repository_urls
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC 공급자 ARN (서비스 CI Role·켜고 끄기 Role trust에서 쓴다)"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "developer_users" {
  description = "팀원 IAM 사용자 이름"
  value       = { for k, u in aws_iam_user.developer : k => u.name }
}

output "developers_group" {
  description = "팀원 IAM 그룹 이름"
  value       = aws_iam_group.developers.name
}

output "ci_ecr_push_role_arn" {
  description = "서비스 CI가 맡는 Role ARN (.github 레포 spring-build.yml의 aws-role-arn 기본값)"
  value       = aws_iam_role.ci_ecr_push.arn
}

output "cost_report_function_name" {
  description = "매일 비용 메일 Lambda 이름 (README 4-9에서 지금 한 번 보내 볼 때 쓴다)"
  value       = module.cost_report.function_name
}
