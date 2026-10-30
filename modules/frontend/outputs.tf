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

output "bucket_arn" {
  description = "프론트 버킷 ARN (cluster 묶음 member-service IRSA가 images/stores/ 아래에만 올린다)"
  value       = aws_s3_bucket.site.arn
}

output "images_prefix" {
  description = "점포 이미지를 두는 경로 (버킷 안 images/, 화면에서는 /images/)"
  value       = local.images_prefix
}
