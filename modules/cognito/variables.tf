variable "name_prefix" {
  description = "리소스 이름 앞부분 (예 freshlink-dev). User Pool은 <name_prefix>-users, Lambda는 <name_prefix>-post-confirmation"
  type        = string
}

variable "groups" {
  description = "User Pool 그룹 → 설명. 토큰의 cognito:groups로 역할을 판단한다"
  type        = map(string)
  default = {
    OWNER    = "점주. 관리자 등록(AD-01)이나 시드 스크립트로만 들어간다"
    CUSTOMER = "고객. 가입 확인 트리거가 넣는다"
    ADMIN    = "관리자. 시드 스크립트로만 들어간다"
  }
}

variable "self_signup_group" {
  description = "직접 가입(confirmSignUp)한 사용자를 넣을 그룹. 화면이 넘기는 역할 값은 보지 않는다"
  type        = string
  default     = "CUSTOMER"
}

variable "id_token_validity_hours" {
  description = "ID 토큰·액세스 토큰 유효 시간(시간)"
  type        = number
  default     = 1
}

variable "refresh_token_validity_days" {
  description = "리프레시 토큰 유효 기간(일)"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "ACTIVE면 User Pool을 지울 수 없다(회원 계정 보호). 지우려면 INACTIVE로 바꿔 apply한 뒤 destroy"
  type        = string
  default     = "ACTIVE"
}

variable "lambda_log_retention_days" {
  description = "가입 확인 Lambda 로그 보관 기간(일)"
  type        = number
  default     = 14
}

variable "secret_recovery_window_days" {
  description = "시드 계정 비밀을 지울 때 복구 대기 기간(일). 0이면 바로 지운다"
  type        = number
  default     = 7
}
