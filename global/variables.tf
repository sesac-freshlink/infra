variable "alert_emails" {
  description = "예산·비용 이상 알림 메일 (김진아, 이태우, 김경우). 실값은 terraform.tfvars에만 둔다"
  type        = list(string)
}

variable "monthly_budget_usd" {
  description = "월별 예산(USD). 합계가 새싹 지원금 약 360 USD를 넘지 않게 나눈다"
  type        = map(number)
  default = {
    "2026-10" = 160
    "2026-11" = 200
  }

  validation {
    condition     = sum(values(var.monthly_budget_usd)) <= 360
    error_message = "월 예산 합계가 360 USD를 넘는다."
  }
}

variable "anomaly_threshold_usd" {
  description = "비용 이상 탐지 메일 기준(USD)"
  type        = number
  default     = 10
}

variable "budget_test_alert" {
  description = "true면 예산 알림 시험용 예산을 만든다. 시험 메일 확인 후 false로 돌린다"
  type        = bool
  default     = false
}

variable "developers" {
  description = "팀원. 키는 영문 아이디(dev 개발자별 큐 이름에 쓴다), iam_user는 새싹이 발급한 기존 IAM 사용자 이름"
  type = map(object({
    name     = string
    iam_user = string
  }))
  default = {
    kyungwoo  = { name = "김경우", iam_user = "sesac-c1" }
    younghoon = { name = "문영훈", iam_user = "sesac-c3" }
    taewoo    = { name = "이태우", iam_user = "sesac-c4" }
  }
}

variable "ecr_repositories" {
  description = "ECR 리포지토리 (두 환경 공용, 서비스 레포 이름 그대로)"
  type        = set(string)
  default     = ["gateway", "member-service", "inventory-service", "order-service", "logistics-simulator"]
}
