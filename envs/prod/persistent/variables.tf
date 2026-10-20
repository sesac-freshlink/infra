variable "developers" {
  description = "개발자별 큐 세트를 받을 팀원 아이디. prod는 비운다(공용 prod- 큐만)"
  type        = set(string)
  default     = []
}

variable "scheduler_enabled" {
  description = "false면 끄기 일정(RDS·nano 21:00·23:00, 클러스터 21:05·23:05 삭제)을 멈춘다. 저녁 시연처럼 밤까지 켜 둘 때만"
  type        = bool
  default     = true
}
