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
