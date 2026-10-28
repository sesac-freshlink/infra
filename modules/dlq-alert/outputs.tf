output "webhook_secret_name" {
  description = "Discord 웹훅 주소를 넣을 비밀 이름 (scripts/set-dlq-webhook.ps1)"
  value       = aws_secretsmanager_secret.webhook.name
}

output "topic_arn" {
  description = "DLQ 경보 SNS 주제 ARN"
  value       = aws_sns_topic.this.arn
}
