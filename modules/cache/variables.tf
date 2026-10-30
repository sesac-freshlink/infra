variable "name_prefix" {
  description = "리소스 이름 앞부분 (freshlink-dev, freshlink-prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Valkey를 둘 프라이빗 서브넷 (앱 서브넷 2개)"
  type        = list(string)
}

variable "client_security_group_id" {
  description = "6379로 들어올 수 있는 보안 그룹 (EKS 클러스터 보안 그룹)"
  type        = string
}

variable "node_type" {
  description = "노드 크기"
  type        = string
  default     = "cache.t4g.micro"
}

variable "engine_version" {
  description = "Valkey 버전 (기본 파라미터 그룹 default.valkey<주 버전>을 쓴다)"
  type        = string
  default     = "8.0"
}
