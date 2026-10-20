variable "name_prefix" {
  description = "이름 접두사 (예 freshlink-dev). 함수·비밀·일정 그룹 이름은 <접두사>-workflow-dispatch"
  type        = string
}

variable "repo" {
  description = "워크플로가 있는 GitHub 저장소 (owner/name)"
  type        = string
  default     = "sesac-freshlink/infra"
}

variable "workflow" {
  description = "실행할 워크플로 파일 이름"
  type        = string
  default     = "dev-cluster.yml"
}

variable "ref" {
  description = "워크플로를 돌릴 브랜치"
  type        = string
  default     = "main"
}

variable "schedules" {
  description = "일정 이름 → { cron(Asia/Seoul), action(워크플로 action 입력) }"
  type = map(object({
    cron   = string
    action = string
  }))
}

variable "enabled" {
  description = "false면 일정만 멈춘다(DISABLED)"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Lambda 로그 보관 일수"
  type        = number
  default     = 14
}
