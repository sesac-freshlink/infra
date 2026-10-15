output "tfstate_bucket" {
  description = "Terraform state 버킷 이름 (backend.hcl의 bucket 값)"
  value       = aws_s3_bucket.tfstate.bucket
}

output "ecr_repository_urls" {
  description = "ECR 리포지토리 주소 (서비스 CI, gitops values에서 쓴다)"
  value       = module.ecr.repository_urls
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC 공급자 ARN (할 일 10의 Role trust에서 쓴다)"
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
