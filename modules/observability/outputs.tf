output "loki_bucket" {
  description = "Loki 로그 버킷 이름 (gitops loki Application이 root 값 cluster.observability.loki.bucket으로 받는다)"
  value       = aws_s3_bucket.loki.bucket
}

output "loki_bucket_arn" {
  description = "Loki 로그 버킷 ARN (cluster 묶음 Loki IRSA 정책)"
  value       = aws_s3_bucket.loki.arn
}
