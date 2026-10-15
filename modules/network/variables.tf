variable "name_prefix" {
  description = "리소스 이름 앞부분 (예 freshlink-dev)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC 대역. dev 10.0.0.0/16, prod 10.1.0.0/16. 서브넷은 이 값에서 계산한다(aws-리소스-계획.md 5-2)"
  type        = string

  validation {
    condition     = endswith(var.vpc_cidr, "/16")
    error_message = "서브넷 계산이 /16을 전제로 한다."
  }
}

variable "availability_zones" {
  description = "가용 영역 두 개. 순서대로 a, c 서브넷에 쓴다"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "가용 영역은 두 개만 쓴다."
  }
}
