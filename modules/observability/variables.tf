variable "name_prefix" {
  description = "리소스 이름 앞부분 (freshlink-dev, freshlink-prod)"
  type        = string
}

variable "log_retention_days" {
  description = "로그 보관 일수. gitops platform/observability/values/loki.yaml의 retention_period(336h)와 맞춘다"
  type        = number
  default     = 14
}

variable "force_destroy" {
  description = "terraform destroy 때 버킷 안 로그까지 지울지"
  type        = bool
  default     = false
}
