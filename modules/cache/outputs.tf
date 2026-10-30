output "endpoint" {
  description = "Valkey 주소 (TLS, 포트 6379)"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "order_redis_secret_arn" {
  description = "order-service 접속 정보 비밀 ARN (External Secrets 읽기 권한)"
  value       = aws_secretsmanager_secret.order_redis.arn
}

output "order_redis_secret_name" {
  description = "order-service 접속 정보 비밀 이름 (gitops order values extraSecrets)"
  value       = aws_secretsmanager_secret.order_redis.name
}
