variable "developers" {
  description = "개발자별 큐 세트를 받을 팀원 아이디 (global var.developers의 키와 같은 아이디). 큐 이름 dev-<아이디>-..."
  type        = set(string)
  default     = ["taewoo", "kyungwoo"]
}

variable "scheduler_enabled" {
  description = "false면 RDS·SSM 접속용 인스턴스 자동 켜기·끄기를 멈춘다(시연 직전 상시 가동 때만)"
  type        = bool
  default     = true
}
