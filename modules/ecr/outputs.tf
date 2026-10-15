output "repository_urls" {
  description = "리포지토리 이름 → 이미지 주소"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "리포지토리 이름 → ARN (OIDC Role 권한에 쓴다, 할 일 10)"
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}
