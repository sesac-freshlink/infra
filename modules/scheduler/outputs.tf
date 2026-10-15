output "schedule_group" {
  description = "일정 그룹 이름"
  value       = aws_scheduler_schedule_group.this.name
}

output "schedules" {
  description = "일정 이름 → cron (Asia/Seoul)"
  value       = { for k, s in aws_scheduler_schedule.this : s.name => s.schedule_expression }
}

output "role_arn" {
  description = "스케줄러 실행 Role ARN"
  value       = aws_iam_role.this.arn
}
