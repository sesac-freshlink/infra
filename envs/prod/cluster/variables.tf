variable "nat_enabled" {
  description = "NAT Gateway를 둘지. prod는 클러스터를 통째로 지우므로 보통 true 그대로. nat-off 버튼으로 false가 될 수 있다"
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "EKS Kubernetes 버전. 1.36 표준 지원은 2027-08까지(프로젝트 기간 안에 끝나지 않는다)"
  type        = string
  default     = "1.36"
}

variable "admin_iam_users" {
  description = "클러스터 관리자로 넣을 IAM 사용자 이름 (김진아 sesac-c2). 켜고 끄기 워크플로 Role은 따로 들어간다"
  type        = list(string)
  default     = ["sesac-c2"]
}

variable "developer_iam_users" {
  description = "Grafana·Zipkin port-forward와 서비스 파드·로그 보기 권한을 줄 팀원 IAM 사용자 이름 (global의 freshlink-<아이디>). prod도 보기만 준다(2026-11-13)"
  type        = list(string)
  default     = ["freshlink-taewoo", "freshlink-kyungwoo"]
}
