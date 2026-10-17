output "bucket_name" {
  description = "React 빌드 파일을 올리는 버킷 (frontend-deploy.yml의 FRONTEND_BUCKET)"
  value       = aws_s3_bucket.site.bucket
}

output "distribution_id" {
  description = "CloudFront 배포 ID (frontend-deploy.yml의 FRONTEND_DISTRIBUTION_ID)"
  value       = aws_cloudfront_distribution.this.id
}

output "url" {
  description = "프론트 주소"
  value       = "https://${aws_cloudfront_distribution.this.domain_name}"
}

output "deploy_role_arn" {
  description = "frontend 레포 frontend-deploy.yml이 맡는 Role (FRONTEND_DEPLOY_ROLE_ARN)"
  value       = aws_iam_role.deploy.arn
}
