output "topic_arn" {
  description = "인프라 오류 SNS 주제 ARN (cluster 묶음 노드 경보, sync-alb-alarm.sh, 켜고 끄기 워크플로가 보낸다)"
  value       = aws_sns_topic.this.arn
}

output "webhook_secret_name" {
  description = "Discord 오류 채널 웹훅 주소를 넣을 비밀 이름 (scripts/set-error-webhook.ps1, gitops ArgoCD 알림)"
  value       = aws_secretsmanager_secret.webhook.name
}

output "webhook_secret_arn" {
  description = "웹훅 비밀 ARN (cluster 묶음 External Secrets 읽기 권한)"
  value       = aws_secretsmanager_secret.webhook.arn
}
