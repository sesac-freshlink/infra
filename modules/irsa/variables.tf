variable "name_prefix" {
  description = "리소스 이름 앞부분 (예 freshlink-dev). Role 이름은 <name_prefix>-<키>-irsa"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC 공급자 ARN"
  type        = string
}

variable "oidc_issuer" {
  description = "EKS OIDC 발급자 주소 (https:// 포함)"
  type        = string
}

variable "roles" {
  description = "Role 키(레포 이름 등) → ServiceAccount와 권한. policy_json은 이 Role 전용 정책, policy_arns는 이미 있는 정책"
  type = map(object({
    namespace       = string
    service_account = string
    policy_json     = optional(string)
    policy_arns     = optional(list(string), [])
  }))
}
