variable "env" {
  description = "환경 이름 (dev 또는 prod). SSM 파라미터 경로 /freshlink/<env>/... 에 쓴다"
  type        = string
}

variable "name_prefix" {
  description = "리소스 이름 앞부분 (예 freshlink-dev). RDS는 <name_prefix>-mysql, 비밀은 <name_prefix>-<서비스>-db"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "db_subnet_ids" {
  description = "RDS 서브넷 그룹에 넣을 db 서브넷 두 개 (인터넷 경로 없음)"
  type        = list(string)
}

variable "ssm_access_subnet_id" {
  description = "SSM 접속용 인스턴스를 둘 서브넷. public 서브넷이어야 한다(아래 main.tf 주석 참고)"
  type        = string
}

variable "instance_class" {
  description = "RDS 인스턴스 크기. 앱 파드 7개 × 커넥션 10개 때문에 small(aws-리소스-계획.md 4장)"
  type        = string
  default     = "db.t4g.small"
}

variable "engine_version" {
  description = "MySQL 버전. 8.0은 2026-07-31에 표준 지원이 끝나 Extended Support 요금이 붙으므로 8.4(LTS)를 쓴다"
  type        = string
  default     = "8.4"
}

variable "allocated_storage_gb" {
  description = "gp3 저장 공간(GiB)"
  type        = number
  default     = 20
}

variable "master_username" {
  description = "RDS 관리자 이름. 비밀번호는 RDS가 만들어 Secrets Manager(rds!db-...)에 둔다"
  type        = string
  default     = "freshlink_admin"
}

variable "backup_retention_days" {
  description = "자동 백업 보관 일수"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "true면 RDS를 지우지 못한다"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "true면 설정 변경을 다음 점검 시간까지 미루지 않고 바로 적용한다"
  type        = bool
  default     = false
}

variable "app_databases" {
  description = "서비스별 스키마와 앱 DB 사용자. 키는 서비스 이름(비밀 이름 <name_prefix>-<키>-db)"
  type = map(object({
    schema   = string
    username = string
  }))
  default = {
    member       = { schema = "member", username = "member_app" }
    inventory    = { schema = "inventory", username = "inventory_app" }
    order        = { schema = "orders", username = "order_app" }
    notification = { schema = "notification", username = "notification_app" } # 화면 알림(10/30)
  }
}

variable "app_password_version" {
  description = "앱 DB 비밀번호 버전. 올리면 서비스 비밀번호를 모두 새로 만들어 비밀에 넣는다(그 뒤 DB 사용자 SQL을 다시 돌린다)"
  type        = number
  default     = 1
}

variable "secret_recovery_window_days" {
  description = "비밀 삭제 후 복구 대기 일수. 0이면 바로 지워져 같은 이름으로 다시 만들 수 있다"
  type        = number
  default     = 7
}

variable "ssm_instance_type" {
  description = "SSM 접속용 인스턴스 크기"
  type        = string
  default     = "t4g.nano"
}
