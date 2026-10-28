variable "env" {
  description = "환경 이름(dev·prod). Discord 메시지 머리에 붙는다"
  type        = string
}

variable "name_prefix" {
  description = "이름 접두사. 비밀 <접두사>-dlq-webhook, 함수·주제 <접두사>-dlq-alert"
  type        = string
}

variable "dlq_names" {
  description = "경보를 걸 DLQ 이름. 경보 1개에 월 0.10 USD라 공용 DLQ만 넣는다"
  type        = list(string)
}

variable "secret_recovery_window_days" {
  description = "비밀을 지울 때 복구 대기 일수. dev는 0(바로 다시 만들 수 있게)"
  type        = number
  default     = 7
}

variable "log_retention_days" {
  description = "Lambda 로그 보관 일수"
  type        = number
  default     = 14
}
