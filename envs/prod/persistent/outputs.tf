output "vpc_id" {
  description = "prod VPC ID (cluster 묶음이 읽는다)"
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
  description = "prod RDS 주소 (포트 포워딩 host, DB_URL)"
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
  description = "세트 → QUEUE_PREFIX (shared = prod-. prod는 개발자별 큐 없음)"
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

output "cognito_user_pool_id" {
  description = "prod User Pool ID (gateway issuer, member-service, frontend VITE_COGNITO_USER_POOL_ID)"
  value       = module.cognito.user_pool_id
}

output "cognito_app_client_id" {
  description = "prod 앱 클라이언트 ID (gateway aud, frontend VITE_COGNITO_CLIENT_ID)"
  value       = module.cognito.app_client_id
}

output "cognito_issuer_uri" {
  description = "prod JWT 발급자 주소 (gateway issuer-uri)"
  value       = module.cognito.issuer_uri
}

output "cognito_jwks_uri" {
  description = "prod 공개 키 주소"
  value       = module.cognito.jwks_uri
}

output "member_cognito_policy_arn" {
  description = "member-service IRSA Role에 붙일 Cognito 관리자 정책 ARN (클러스터 묶음, 할 일 7)"
  value       = module.cognito.member_cognito_policy_arn
}

output "seed_accounts_secret_name" {
  description = "시드 계정 자격 비밀 이름 (scripts/seed-cognito.ps1이 값을 넣는다)"
  value       = module.cognito.seed_accounts_secret_name
}

output "eks_cluster_name" {
  description = "EKS 클러스터 이름 (cluster 묶음이 이 이름으로 만든다)"
  value       = local.eks_cluster_name
}

output "eks_node_group_name" {
  description = "노드 그룹 이름 (cluster 묶음이 이 이름으로 만든다)"
  value       = local.eks_node_group_name
}

output "cluster_actions_role_arn" {
  description = "켜고 끄기 워크플로 Role ARN (infra 레포 Actions 비밀 AWS_PROD_CLUSTER_ROLE_ARN, cluster 묶음 관리자)"
  value       = module.cluster_actions.role_arn
}

output "frontend_bucket" {
  description = "prod 프론트 버킷 (frontend 레포 변수 PROD_FRONTEND_BUCKET)"
  value       = module.frontend.bucket_name
}

output "frontend_distribution_id" {
  description = "prod CloudFront 배포 ID (frontend 레포 변수 PROD_FRONTEND_DISTRIBUTION_ID)"
  value       = module.frontend.distribution_id
}

output "frontend_url" {
  description = "prod 프론트 주소. /api/*는 gateway로 간다"
  value       = module.frontend.url
}

output "frontend_deploy_role_arn" {
  description = "frontend 레포 frontend-deploy.yml이 맡는 Role (변수 PROD_FRONTEND_DEPLOY_ROLE_ARN)"
  value       = module.frontend.deploy_role_arn
}

output "workflow_dispatch_token_secret" {
  description = "켜고 끄기 워크플로 실행 요청에 쓰는 GitHub 토큰 비밀 이름 (README 4-11)"
  value       = module.cluster_dispatch.token_secret_name
}

output "workflow_dispatch_function" {
  description = "켜고 끄기 워크플로 실행 요청 Lambda 이름 (README 4-11 시험)"
  value       = module.cluster_dispatch.function_name
}

output "loki_bucket" {
  description = "Loki 로그 버킷 이름 (cluster 묶음이 root Application에 넘긴다)"
  value       = module.observability.loki_bucket
}

output "loki_bucket_arn" {
  description = "Loki 로그 버킷 ARN (cluster 묶음 Loki IRSA 정책)"
  value       = module.observability.loki_bucket_arn
}
