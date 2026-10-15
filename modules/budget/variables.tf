variable "name_prefix" {
  description = "예산·이상 탐지 이름 접두사"
  type        = string
  default     = "freshlink"
}

variable "monthly_limits" {
  description = "월별 예산(USD). 키는 YYYY-MM. 합계가 지원금(약 360 USD)을 넘지 않게 나눈다"
  type        = map(number)

  validation {
    condition     = alltrue([for k in keys(var.monthly_limits) : can(regex("^[0-9]{4}-[0-9]{2}$", k))])
    error_message = "monthly_limits 키는 YYYY-MM 형식이어야 한다."
  }
}

variable "alert_emails" {
  description = "예산·이상 탐지 알림을 받을 메일 주소 (최대 10개)"
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) >= 1 && length(var.alert_emails) <= 10
    error_message = "alert_emails는 1~10개여야 한다."
  }
}

variable "actual_thresholds" {
  description = "실제 비용 알림 기준(예산 대비 %)"
  type        = list(number)
  default     = [50, 80, 100]
}

variable "anomaly_threshold_usd" {
  description = "비용 이상 탐지 알림 기준: 이상 금액 합계가 이 값(USD) 이상일 때 메일"
  type        = number
  default     = 10
}

variable "create_test_budget" {
  description = "true면 알림 시험용 예산(1 USD, 1% 초과 시 메일)을 만든다. 메일을 모두 받은 뒤 false로 돌려 지운다"
  type        = bool
  default     = false
}
