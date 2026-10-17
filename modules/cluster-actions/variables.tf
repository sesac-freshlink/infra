variable "name_prefix" {
  description = "리소스 이름 앞부분 (예 freshlink-dev). Role 이름은 <name_prefix>-cluster-actions, 다룰 수 있는 IAM은 <name_prefix>-*"
  type        = string
}

variable "github_repository" {
  description = "이 Role을 맡을 GitHub 레포 (main 브랜치만)"
  type        = string
  default     = "sesac-freshlink/infra"
}
