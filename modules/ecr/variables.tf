variable "repositories" {
  description = "만들 ECR 리포지토리 이름. 서비스 레포 이름과 똑같이 쓴다"
  type        = set(string)
}

variable "keep_image_count" {
  description = "리포지토리마다 남길 태그 이미지 개수. 넘으면 오래된 것부터 지운다"
  type        = number
  default     = 30
}
