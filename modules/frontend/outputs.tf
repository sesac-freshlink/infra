output "bucket_name" {
  description = "React 빌드 파일을 올리는 버킷 (frontend-deploy.yml의 FRONTEND_BUCKET)"
  value       = aws_s3_bucket.site.bucket
}

output "distribution_id" {
  description = "CloudFront 배포 ID (frontend-deploy.yml의 FRONTEND_DISTRIBUTION_ID)"
  value       = aws_cloudfront_distribution.this.id
}

output "url" {
  description = "프론트 대표 주소. 도메인을 붙였으면 https://<hostnames[0]>, 아니면 CloudFront 기본 주소"
  value       = local.site_urls[0]
}

output "urls" {
  description = "화면이 열리는 주소 전부(도메인들 + CloudFront 기본 주소). Cognito 콜백·버킷 CORS에 쓴다"
  value       = local.site_urls
}

output "cloudfront_url" {
  description = "CloudFront 기본 주소(https://<id>.cloudfront.net). 도메인을 붙인 뒤에도 열린다"
  value       = local.cloudfront_url
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
