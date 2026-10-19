variable "name_prefix" {
  description = "이름 접두사 (함수·주제·일정 이름은 <접두사>-cost-report)"
  type        = string
  default     = "freshlink"
}

variable "emails" {
  description = "비용 메일을 받을 주소. 처음 apply 뒤 각자 확인 메일의 Confirm subscription을 한 번 눌러야 받는다"
  type        = list(string)
}

variable "monthly_limits" {
  description = "월별 예산(USD). 키는 YYYY-MM. 첫 달 1일이 총 비용을 세기 시작하는 날이다"
  type        = map(number)
}

variable "total_budget_usd" {
  description = "프로젝트 전체 예산(USD). 메일에 총 비용과 함께 비율을 보인다"
  type        = number
}

variable "schedule_cron" {
  description = "보내는 시각(Asia/Seoul). Cost Explorer의 하루가 UTC라서 한국 시간 09:00 뒤여야 어제 하루가 끝나 있다"
  type        = string
  default     = "cron(0 9 * * ? *)"
}

variable "log_retention_days" {
  description = "Lambda 로그 보관 일수"
  type        = number
  default     = 14
}
