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

variable "admin_password_auth" {
  description = "true면 앱 클라이언트에 ALLOW_ADMIN_USER_PASSWORD_AUTH를 켠다. IAM 자격(cognito-idp:AdminInitiateAuth)이 있어야만 쓰는 흐름이라 브라우저에서는 쓸 수 없다. dev에서 PowerShell로 시험 토큰을 받을 때만 켠다"
  type        = bool
  default     = false
}

variable "domain_prefix" {
  description = "로그인 도메인 접두사(리전 안에서 전 세계 유일, aws·amazon·cognito 금지). 예 freshlink-dev-auth"
  type        = string
}

variable "callback_urls" {
  description = "bff 클라이언트 OAuth 콜백 주소(gateway /api/auth/callback). 예 https://<프론트>/api/auth/callback"
  type        = list(string)
}

variable "logout_urls" {
  description = "bff 클라이언트 로그아웃 후 돌아갈 주소(로그인 도메인 /logout의 logout_uri)"
  type        = list(string)
}

variable "google_secret_name" {
  description = "구글 OAuth 클라이언트 비밀 이름(JSON clientId·clientSecret, scripts/set-google-oauth.ps1이 넣는다). 비밀이 없거나 null이면 구글 로그인 없음"
  type        = string
  default     = null
}
