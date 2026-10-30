variable "name_prefix" {
  description = "이름 접두사. 예: freshlink-dev"
  type        = string
}

variable "github_org" {
  description = "배포 Role을 맡을 수 있는 GitHub 조직"
  type        = string
  default     = "sesac-freshlink"
}

variable "deploy_branch" {
  description = "이 환경 버킷에 올릴 수 있는 frontend 레포 브랜치 (dev → dev, main → prod)"
  type        = string
}

variable "force_destroy" {
  description = "true면 destroy 때 버킷에 파일이 있어도 지운다 (dev만)"
  type        = bool
  default     = false
}

variable "price_class" {
  description = "CloudFront 가격 등급. PriceClass_200은 한국 엣지를 포함한다"
  type        = string
  default     = "PriceClass_200"
}

variable "csp_report_only" {
  description = "true면 CSP를 Content-Security-Policy-Report-Only로 건다(막지 않고 콘솔에만 찍는다). 확인 뒤 false로 바꿔 실제로 막는다"
  type        = bool
  default     = true
}

variable "csp_extra_connect_src" {
  description = "CSP connect-src에 더할 주소. 브라우저 Amplify가 Cognito를 직접 부르는 동안(BFF 전환 전 prod)만 cognito-idp 주소를 넣는다"
  type        = list(string)
  default     = []
}

variable "hostnames" {
  description = "화면 주소(도메인). 첫 번째가 대표 주소다. 비우면 CloudFront 기본 주소만 쓴다. 예 [\"dev.<도메인>\"]"
  type        = list(string)
  default     = []
}

variable "zone_id" {
  description = "hostnames가 들어 있는 Route 53 호스팅 영역 ID (도메인을 사면 자동으로 생긴다). hostnames가 비면 쓰지 않는다"
  type        = string
  default     = ""
  nullable    = false # 도메인이 없을 때 부르는 쪽이 null을 넘겨도 ""로 받는다

  validation {
    condition     = length(var.hostnames) == 0 || var.zone_id != ""
    error_message = "hostnames를 넣으면 zone_id도 넣어야 한다."
  }
}
