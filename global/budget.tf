# 계정 전체 예산과 비용 이상 탐지. 다른 무엇보다 먼저 apply한다(README 4장 1단계).
module "budget" {
  source = "../modules/budget"

  name_prefix           = "freshlink"
  monthly_limits        = var.monthly_budget_usd
  alert_emails          = var.alert_emails
  anomaly_threshold_usd = var.anomaly_threshold_usd
  create_test_budget    = var.budget_test_alert
}
