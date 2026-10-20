variable "name_prefix" {
  description = "리소스 이름 앞부분 (예 freshlink-dev). 일정 그룹·Role 이름에 쓴다"
  type        = string
}

variable "timezone" {
  description = "일정 시간대. 한국 시각 그대로 적는다"
  type        = string
  default     = "Asia/Seoul"
}

variable "rds_instance_identifier" {
  description = "켜고 끌 RDS 식별자"
  type        = string
}

variable "rds_instance_arn" {
  description = "켜고 끌 RDS ARN (실행 Role 권한 범위)"
  type        = string
}

variable "ec2_instance_ids" {
  description = "RDS와 같은 시각에 켜고 끌 EC2 인스턴스 ID (SSM 접속용 nano)"
  type        = list(string)
}

variable "ec2_instance_arns" {
  description = "위 인스턴스 ARN (실행 Role 권한 범위)"
  type        = list(string)
}

variable "start_cron" {
  description = "켜기 (EventBridge Scheduler cron). 기본 평일 09:00"
  type        = string
  default     = "cron(0 9 ? * MON-FRI *)"
}

variable "stop_cron" {
  description = "끄기. 기본 평일 21:00"
  type        = string
  default     = "cron(0 21 ? * MON-FRI *)"
}

variable "safety_stop_cron" {
  description = "안전 끄기 (추가 개발 뒤 잊었을 때 대비). 기본 매일 23:00"
  type        = string
  default     = "cron(0 23 * * ? *)"
}

variable "enabled" {
  description = "false면 일정을 멈춘다(DISABLED). 시연 직전처럼 계속 켜 둘 때만"
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = "노드 수를 바꿀 EKS 클러스터 이름 (cluster 묶음이 같은 이름으로 만든다)"
  type        = string
}

variable "eks_node_group_name" {
  description = "노드 수를 바꿀 노드 그룹 이름"
  type        = string
}

variable "nodes_up_cron" {
  description = "노드 2대. 기본 화~금 09:10 (NAT가 08:50에 생긴 뒤, modules/workflow-dispatch. NAT 없이 뜬 노드는 붙지 못한다. 월요일은 클러스터 생성이 노드 2대로 만든다)"
  type        = string
  default     = "cron(10 9 ? * TUE-FRI *)"
}

variable "nodes_down_cron" {
  description = "노드 0대. 기본 월~목 21:00 (금요일은 21:00에 클러스터를 지운다)"
  type        = string
  default     = "cron(0 21 ? * MON-THU *)"
}

variable "nodes_safety_down_cron" {
  description = "노드 안전 0대 (추가 개발 뒤 잊었을 때 대비). 기본 월~금 23:00. 주말은 클러스터가 없어 넣지 않는다"
  type        = string
  default     = "cron(0 23 ? * MON-FRI *)"
}
