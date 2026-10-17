variable "name_prefix" {
  description = "리소스 이름 앞부분 (예 freshlink-dev). Role 이름은 <name_prefix>-cluster-actions, 다룰 수 있는 IAM은 <name_prefix>-*"
  type        = string
}

variable "github_sub_prefixes" {
  description = "이 Role을 맡을 GitHub 작업의 sub 앞부분 (main 브랜치만 붙여 쓴다). infra 레포 설정: gh api repos/sesac-freshlink/infra/actions/oidc/customization/sub 의 sub_claim_prefix"
  type        = list(string)
  default = [
    "repo:sesac-freshlink@341308955/infra@1415176113", # immutable subject (지금 쓰는 형식)
    "repo:sesac-freshlink/infra",                      # 기본 형식
  ]
}
