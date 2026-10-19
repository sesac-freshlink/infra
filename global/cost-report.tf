# 매일 아침 09:00(한국 시간) 비용 메일: 어제 비용, 이번 달 누계, 프로젝트 총 비용. README 4-9
module "cost_report" {
  source = "../modules/cost-report"

  name_prefix      = "freshlink"
  emails           = var.alert_emails
  monthly_limits   = var.monthly_budget_usd
  total_budget_usd = var.total_budget_usd
}
