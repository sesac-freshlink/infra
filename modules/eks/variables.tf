variable "name_prefix" {
  description = "리소스 이름 앞부분 (예 freshlink-dev). IAM Role 이름에 쓴다"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (예 freshlink-dev-eks). persistent 묶음의 노드 일정이 같은 이름을 쓴다"
  type        = string
}

variable "node_group_name" {
  description = "노드 그룹 이름 (예 freshlink-dev-nodes). persistent 묶음의 노드 일정이 같은 이름을 쓴다"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes 버전. 표준 지원 안의 버전만 쓴다(지원이 끝난 버전은 시간당 요금이 6배)"
  type        = string
}

variable "subnet_ids" {
  description = "클러스터 ENI와 노드를 둘 app 서브넷 두 개 [a, c]"
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "클러스터 관리자(access entry)로 넣을 IAM 사용자·Role ARN"
  type        = list(string)
}

variable "node_instance_type" {
  description = "노드 인스턴스 타입 (aws-리소스-계획.md 3장)"
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  description = "처음 만들 때 노드 수. 그 뒤로는 스케줄러가 바꾸고 Terraform은 무시한다"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "노드 최대 수. 동시 주문 시험·장애 훈련 때만 3으로 올린다"
  type        = number
  default     = 3
}

variable "ebs_csi_role_arn" {
  description = "EBS CSI 드라이버 IRSA Role ARN"
  type        = string
}
