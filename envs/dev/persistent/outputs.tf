output "vpc_id" {
  description = "dev VPC ID (cluster 묶음이 읽는다)"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "public 서브넷 ID [a, c]"
  value       = module.network.public_subnet_ids
}

output "app_subnet_ids" {
  description = "app 서브넷 ID [a, c] (EKS 노드)"
  value       = module.network.app_subnet_ids
}

output "app_route_table_id" {
  description = "app 라우팅 테이블. cluster 묶음이 NAT 경로를 넣는다"
  value       = module.network.app_route_table_id
}

output "rds_security_group_id" {
  description = "RDS 보안 그룹. cluster 묶음이 EKS 노드 → 3306을 연다"
  value       = module.rds.rds_security_group_id
}

output "db_address" {
  description = "dev RDS 주소 (포트 포워딩 host, DB_URL)"
  value       = module.rds.db_address
}

output "master_user_secret_arn" {
  description = "RDS 관리자 비밀번호 비밀 ARN (김진아 전용, README 4-4 SQL에 쓴다)"
  value       = module.rds.master_user_secret_arn
}

output "app_databases" {
  description = "서비스 → 스키마·DB 사용자"
  value       = module.rds.app_databases
}

output "app_db_secret_names" {
  description = "서비스 → 앱 DB 비밀 이름 (팀원이 비밀번호를 꺼낼 때 쓴다)"
  value       = module.rds.app_db_secret_names
}

output "app_db_secret_arns" {
  description = "서비스 → 앱 DB 비밀 ARN"
  value       = module.rds.app_db_secret_arns
}

output "toss_secret_name" {
  description = "토스 테스트 키 비밀 이름"
  value       = aws_secretsmanager_secret.toss.name
}

output "ssm_access_instance_id" {
  description = "SSM 접속용 인스턴스 ID (포트 포워딩 --target)"
  value       = module.rds.ssm_access_instance_id
}

output "queue_prefixes" {
  description = "세트 → QUEUE_PREFIX (shared = dev-, 개발자 = dev-<아이디>-)"
  value       = module.messaging.queue_prefixes
}

output "queues" {
  description = "세트 → 큐 이름 4개"
  value       = module.messaging.queues
}

output "queue_arns" {
  description = "세트 → 큐 ARN 4개"
  value       = module.messaging.queue_arns
}

output "schedules" {
  description = "켜고 끄기 일정 (Asia/Seoul)"
  value       = module.scheduler.schedules
}
