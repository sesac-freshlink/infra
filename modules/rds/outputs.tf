output "db_instance_identifier" {
  description = "RDS 식별자 (스케줄러가 켜고 끈다)"
  value       = aws_db_instance.this.identifier
}

output "db_instance_arn" {
  description = "RDS ARN"
  value       = aws_db_instance.this.arn
}

output "db_address" {
  description = "RDS 접속 주소 (포트 포워딩의 host)"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS 포트"
  value       = aws_db_instance.this.port
}

output "master_user_secret_arn" {
  description = "RDS가 만든 관리자 비밀번호 비밀 ARN (김진아만 읽는다)"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "rds_security_group_id" {
  description = "RDS 보안 그룹. cluster 묶음이 EKS 노드 → 3306 규칙을 붙인다"
  value       = aws_security_group.rds.id
}

output "app_db_secret_names" {
  description = "서비스 → 앱 DB 비밀 이름"
  value       = { for k, s in aws_secretsmanager_secret.app_db : k => s.name }
}

output "app_db_secret_arns" {
  description = "서비스 → 앱 DB 비밀 ARN (External Secrets 권한에 쓴다)"
  value       = { for k, s in aws_secretsmanager_secret.app_db : k => s.arn }
}

output "app_databases" {
  description = "서비스 → 스키마·DB 사용자 (README 4-4 SQL이 쓴다)"
  value       = var.app_databases
}

output "ssm_access_instance_id" {
  description = "SSM 접속용 인스턴스 ID (포트 포워딩 --target)"
  value       = aws_instance.ssm_access.id
}

output "ssm_access_instance_arn" {
  description = "SSM 접속용 인스턴스 ARN (스케줄러 권한)"
  value       = aws_instance.ssm_access.arn
}
