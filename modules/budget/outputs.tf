output "budget_name" {
  description = "월 예산 이름"
  value       = aws_budgets_budget.monthly.name
}

output "anomaly_monitor_arn" {
  description = "비용 이상 탐지 모니터 ARN"
  value       = aws_ce_anomaly_monitor.services.arn
}
