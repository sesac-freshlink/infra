variable "env" {
  description = "환경 이름. 큐 이름 앞에 '<env>-'로 붙는다(팀원 IAM은 dev-* 큐만 허용)"
  type        = string
}

variable "developers" {
  description = "개발자별 큐 세트를 만들 아이디 목록. 큐 이름 '<env>-<아이디>-...'(QUEUE_PREFIX '<env>-<아이디>-'). prod는 빈 목록"
  type        = set(string)
  default     = []
}

variable "max_receive_count" {
  description = "이 횟수만큼 받고도 지워지지 않은 쪽지는 DLQ로 옮긴다"
  type        = number
  default     = 3
}

variable "visibility_timeout_seconds" {
  description = "받은 쪽지를 다른 소비자에게 숨기는 시간(초). 처리 시간보다 길게"
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "본 큐 보관 시간(초). 기본 4일"
  type        = number
  default     = 345600
}

variable "dlq_retention_seconds" {
  description = "DLQ 보관 시간(초). 기본 14일(최대)"
  type        = number
  default     = 1209600
}
