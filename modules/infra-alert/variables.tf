variable "env" {
  description = "환경 이름(dev·prod). Discord 메시지 머리에 붙는다"
  type        = string
}

variable "name_prefix" {
  description = "이름 접두사. 비밀 <접두사>-error-webhook, 함수·주제 <접두사>-infra-alert, 경보 <접두사>-rds-*"
  type        = string
}

variable "rds_instance_identifier" {
  description = "경보를 걸 RDS 인스턴스 ID"
  type        = string
}

variable "rds_cpu_percent" {
  description = "RDS CPU 경보 기준(%). 5분 평균이 3번(15분) 이어서 넘을 때만 울린다"
  type        = number
  default     = 80
}

variable "rds_free_storage_gb" {
  description = "RDS 남은 저장 공간 경보 기준(GiB). 20GiB 중 10%"
  type        = number
  default     = 2
}

variable "rds_connections" {
  description = "RDS 연결 수 경보 기준. db.t4g.small 최대 약 170, 평소 서비스 풀 합계 약 70~100"
  type        = number
  default     = 120
}

variable "lambda_function_names" {
  description = "Errors 경보를 걸 Lambda 이름(켜고 끄기 workflow-dispatch)"
  type        = list(string)
  default     = []
}

variable "cost_anomaly_enabled" {
  description = "비용 이상 감지를 이 주제로 받을지. 계정 전체라 한 환경(prod)에서만 true"
  type        = bool
  default     = false
}

variable "cost_anomaly_monitor_arn" {
  description = "계정에 이미 있는 AWS 서비스 비용 모니터 ARN. 비우면 새로 만든다(계정에 하나뿐이라 있으면 만들기가 실패한다)"
  type        = string
  default     = ""
}

variable "cost_anomaly_usd" {
  description = "비용 이상 알림 기준(USD). 이상 하나의 예상 초과 금액이 이 값 이상일 때만 보낸다"
  type        = number
  default     = 5
}

variable "secret_recovery_window_days" {
  description = "비밀을 지울 때 복구 대기 일수"
  type        = number
  default     = 7
}

variable "log_retention_days" {
  description = "Lambda 로그 보관 일수"
  type        = number
  default     = 14
}
