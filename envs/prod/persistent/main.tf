# prod 유지 묶음 (할 일 14): dev 유지 묶음(envs/dev/persistent)과 같은 모듈을 부르고 값만 다르다.
# 다른 값: 이름 접두사 freshlink-prod, VPC 10.1.0.0/16, 개발자별 큐 없음, 프론트 배포 브랜치 main, 켜고 끄기 일정.
# prod는 데모 환경이라 주말 포함 매일 09:00–21:00 켠다(2026-11-05 결정, .github docs/할일/3차멘토링-사람별-할일.md 1-4).
# 뼈대는 dev와 같다: 클러스터는 일주일 두고 밤에는 노드 0대·NAT 삭제·RDS 끄기. 다시 만들기는 일요일 밤 → 월요일 아침 한 번.
# 오래 꺼 둔 RDS는 7일 뒤 AWS가 스스로 켜는데, 매일 23:00 끄기가 다시 끈다.

locals {
  env         = "prod"
  name_prefix = "freshlink-prod"

  # cluster 묶음이 이 이름으로 만든다(remote state로 읽는다). 스케줄러는 이름으로 노드 수를 바꾼다.
  eks_cluster_name    = "${local.name_prefix}-eks"
  eks_node_group_name = "${local.name_prefix}-nodes"

  # 화면 주소(README 4-21). 도메인을 사기 전(domain_name = "")에는 CloudFront 기본 주소만 쓴다.
  # prod는 <도메인> 그 자체, dev는 dev.<도메인>
  site_hostnames = var.domain_name == "" ? [] : [var.domain_name]
}

# 도메인을 사면 Route 53이 호스팅 영역을 자동으로 만든다. Terraform은 읽기만 한다(지우지 않게).
data "aws_route53_zone" "site" {
  count = var.domain_name == "" ? 0 : 1

  name         = var.domain_name
  private_zone = false
}

module "network" {
  source = "../../../modules/network"

  name_prefix = local.name_prefix
  vpc_cidr    = "10.1.0.0/16"
}

module "rds" {
  source = "../../../modules/rds"

  env                  = local.env
  name_prefix          = local.name_prefix
  vpc_id               = module.network.vpc_id
  db_subnet_ids        = module.network.db_subnet_ids
  ssm_access_subnet_id = module.network.public_subnet_ids[0] # public-a

  apply_immediately = true
}

module "scheduler" {
  source = "../../../modules/scheduler"

  name_prefix             = local.name_prefix
  rds_instance_identifier = module.rds.db_instance_identifier
  rds_instance_arn        = module.rds.db_instance_arn
  ec2_instance_ids        = [module.rds.ssm_access_instance_id]
  ec2_instance_arns       = [module.rds.ssm_access_instance_arn]
  eks_cluster_name        = local.eks_cluster_name
  eks_node_group_name     = local.eks_node_group_name
  enabled                 = var.scheduler_enabled

  start_cron             = "cron(0 9 * * ? *)"        # 매일 09:00 RDS·nano 켜기 (월요일은 08:40 create도 켠다)
  stop_cron              = "cron(0 21 * * ? *)"       # 매일 21:00 RDS·nano 끄기
  nodes_up_cron          = "cron(10 9 ? * TUE-SUN *)" # 화–일 09:10 노드 2대 (08:50 NAT 뒤. 월요일은 create가 2대로 만든다)
  nodes_down_cron        = "cron(0 21 ? * MON-SAT *)" # 월–토 21:00 노드 0대 (일요일은 21:05에 클러스터를 지운다)
  nodes_safety_down_cron = "cron(0 23 * * ? *)"       # 매일 23:00 노드 0대 한 번 더
}

# prod 클러스터·NAT 일정 (dev와 같은 모양, 주말 포함 매일). 클러스터 생성은 월요일, 삭제는 일요일 밤만.
# EventBridge → Lambda가 부르는 workflow_dispatch라 dev-cluster.yml의 "평일만" 시각 검사(GitHub 예약에만 걸림)를 타지 않는다.
# Lambda는 action만 넘길 수 있어서 prod 입구 워크플로(prod-cluster.yml)를 부른다. 그 워크플로가 dev-cluster.yml을 env=prod로 부른다.
module "cluster_dispatch" {
  source = "../../../modules/workflow-dispatch"

  name_prefix = local.name_prefix
  workflow    = "prod-cluster.yml"
  enabled     = var.scheduler_enabled
  schedules = {
    create       = { cron = "cron(40 8 ? * MON *)", action = "create" }       # 월 08:40 클러스터 생성 (노드 2대·NAT 포함)
    nat-on       = { cron = "cron(50 8 ? * TUE-SUN *)", action = "nat-on" }   # 화–일 08:50 NAT 생성 (노드 09:10보다 먼저)
    nat-off      = { cron = "cron(10 21 ? * MON-SAT *)", action = "nat-off" } # 월–토 21:10 NAT 삭제
    destroy      = { cron = "cron(5 21 ? * SUN *)", action = "destroy" }      # 일 21:05 클러스터 삭제
    nat-off-late = { cron = "cron(5 23 * * ? *)", action = "nat-off" }        # 매일 23:05 NAT가 남아 있으면 삭제
    destroy-late = { cron = "cron(15 23 ? * SUN *)", action = "destroy" }     # 일 23:15 클러스터 삭제 한 번 더 (23:05 NAT 정리 뒤)
  }
}

module "cluster_actions" {
  source = "../../../modules/cluster-actions"

  name_prefix = local.name_prefix
}

module "cognito" {
  source = "../../../modules/cognito"

  name_prefix = local.name_prefix

  # BFF·구글 로그인(README 4-17). 콜백은 gateway /api/auth/callback
  domain_prefix = "${local.name_prefix}-auth"
  # 화면이 열리는 주소 전부(도메인 + CloudFront 기본 주소, README 4-21)를 받는다
  callback_urls      = [for u in module.frontend.urls : "${u}/api/auth/callback"]
  logout_urls        = [for u in module.frontend.urls : "${u}/login"]
  google_secret_name = "${local.name_prefix}-google-oauth" # scripts/set-google-oauth.ps1 -Env prod가 만든다. 없으면 구글 IdP 없이 만든다
}

module "messaging" {
  source = "../../../modules/messaging"

  env        = local.env
  developers = var.developers
}

# DLQ에 쪽지가 쌓이면 Discord DLQ 채널로 알린다. 웹훅 주소는 scripts/set-dlq-webhook.ps1 -Env prod로 넣는다(README 4-16).
module "dlq_alert" {
  source = "../../../modules/dlq-alert"

  env         = local.env
  name_prefix = local.name_prefix
  dlq_names = [
    module.messaging.queues["shared"].commands_dlq,
    module.messaging.queues["shared"].results_dlq,
    module.messaging.queues["shared"].notifications_dlq, # 화면 알림(10/30)
  ]
}

# 인프라 오류(RDS·켜고 끄기 Lambda 경보, 비용 이상, 워크플로 실패)를 Discord 오류 채널로 알린다. DLQ 채널과 다른 웹훅이다.
# 웹훅 주소는 scripts/set-error-webhook.ps1 -Env prod로 넣는다. ArgoCD 알림도 같은 비밀을 쓴다(README 4-24).
module "infra_alert" {
  source = "../../../modules/infra-alert"

  env                     = local.env
  name_prefix             = local.name_prefix
  rds_instance_identifier = module.rds.db_instance_identifier
  lambda_function_names   = [module.cluster_dispatch.function_name]

  # 비용 이상 감지는 계정 전체(dev 포함)라 prod에서만 받는다
  cost_anomaly_enabled     = true
  cost_anomaly_monitor_arn = var.cost_anomaly_monitor_arn
}

module "frontend" {
  source = "../../../modules/frontend"

  name_prefix   = local.name_prefix
  deploy_branch = "main"

  hostnames = local.site_hostnames
  zone_id   = one(data.aws_route53_zone.site[*].zone_id)
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  # prod 화면은 BFF로 바뀌어(11/3 릴리스) 브라우저가 Cognito를 직접 부르지 않는다.
  # dev에서 11/2 Report-Only 위반이 없어 prod도 실제로 막는다(README 4-18의 4)·5))
  csp_report_only = false
}

# 할 일 16: Loki 로그 버킷(S3, 14일). prod 로그는 지우지 않게 force_destroy를 켜지 않는다
module "observability" {
  source = "../../../modules/observability"

  name_prefix = local.name_prefix
}

# 토스페이먼츠 테스트 키(prod도 테스트 키). 값은 Terraform에 넣지 않고 scripts/set-toss-key.ps1 -Env prod로 넣는다.
resource "aws_secretsmanager_secret" "toss" {
  name                    = "${local.name_prefix}-toss"
  description             = "Toss Payments test keys (clientKey, secretKey)"
  recovery_window_in_days = 7
}

# logistics-simulator 매일 시나리오가 주문할 가상 고객 (3차 1-1). 값 {"customers": "<sub>:<점포>,<점포>;..."}은
# scripts/seed-cognito.ps1이 넣는다(비밀번호 없음). 클러스터의 External Secrets가 읽어 SIMULATOR_CUSTOMERS로 넣는다.
resource "aws_secretsmanager_secret" "simulator_customers" {
  name                    = "${local.name_prefix}/simulator/customers"
  description             = "logistics-simulator virtual customers (Cognito sub and favorite store IDs)"
  recovery_window_in_days = 7
}
