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

variable "domain_name" {
  description = "Route 53에서 산 도메인(호스팅 영역 이름). 비우면 CloudFront 기본 주소만 쓴다. dev 화면 주소는 dev.<domain_name> (README 4-21)"
  type        = string
  default     = "getfreshlink.com" # 2026-10-30 Route 53에서 1년 등록(자동 갱신 끔)
}
