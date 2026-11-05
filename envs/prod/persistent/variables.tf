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

variable "domain_name" {
  description = "Route 53에서 산 도메인(호스팅 영역 이름). 비우면 CloudFront 기본 주소만 쓴다. prod 화면 주소는 <domain_name> (도메인 그 자체) (README 4-21)"
  type        = string
  default     = "getfreshlink.com" # 2026-10-30 Route 53에서 1년 등록(자동 갱신 끔)
}

variable "cost_anomaly_monitor_arn" {
  description = "계정에 이미 있는 AWS 서비스 비용 이상 모니터 ARN. 비우면 새로 만든다. apply가 모니터 한도로 실패할 때만 넣는다(README 4-24)"
  type        = string
  default     = ""
}
