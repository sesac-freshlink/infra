# prod 유지 묶음 (할 일 14): dev 유지 묶음(envs/dev/persistent)과 같은 모듈을 부르고 값만 다르다.
# 다른 값: 이름 접두사 freshlink-prod, VPC 10.1.0.0/16, 개발자별 큐 없음, 프론트 배포 브랜치 main, 켜고 끄기 일정.
# prod는 평소 꺼 둔다. 켜는 것은 사람이 한다(prod-cluster 워크플로 create가 RDS·접속용 인스턴스도 켠다).
# 일정은 끄기만 둔다: RDS·nano 매일 21:00·23:00 끄기, 클러스터 매일 21:05·23:05 지우기.
# 오래 꺼 둔 RDS는 7일 뒤 AWS가 스스로 켜는데, 매일 23:00 끄기가 다시 끈다.

locals {
  env         = "prod"
  name_prefix = "freshlink-prod"

  # cluster 묶음이 이 이름으로 만든다(remote state로 읽는다). 스케줄러는 이름으로 노드 수를 바꾼다.
  eks_cluster_name    = "${local.name_prefix}-eks"
  eks_node_group_name = "${local.name_prefix}-nodes"

  # 켜는 일정은 두지 않는다. scheduler 모듈에 null을 넘기면 그 일정을 만들지 않는다.
  # 오지 않는 날 cron(0 0 1 1 ? 2199)은 AWS가 "will never schedule an invocation"으로 거부한다.
  never = null
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

  start_cron             = local.never
  stop_cron              = "cron(0 21 * * ? *)" # 매일 21:00 (시연이 주말이어도 끈다)
  nodes_up_cron          = local.never
  nodes_down_cron        = local.never          # 21:05에 클러스터를 통째로 지운다
  nodes_safety_down_cron = "cron(0 23 * * ? *)" # 매일 23:00 (클러스터 지우기가 실패했을 때)
}

# prod 클러스터를 매일 밤 지운다(켜 둔 채 잊었을 때). 켜는 일정은 없다.
# Lambda는 action만 넘길 수 있어서 prod 입구 워크플로(prod-cluster.yml)를 부른다. 그 워크플로가 dev-cluster.yml을 env=prod로 부른다.
module "cluster_dispatch" {
  source = "../../../modules/workflow-dispatch"

  name_prefix = local.name_prefix
  workflow    = "prod-cluster.yml"
  enabled     = var.scheduler_enabled
  schedules = {
    destroy      = { cron = "cron(5 21 * * ? *)", action = "destroy" } # 매일 21:05 클러스터 삭제 (없으면 그대로)
    destroy-late = { cron = "cron(5 23 * * ? *)", action = "destroy" } # 매일 23:05 한 번 더
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
  domain_prefix      = "${local.name_prefix}-auth"
  callback_urls      = ["${module.frontend.url}/api/auth/callback"]
  logout_urls        = ["${module.frontend.url}/login"]
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
  ]
}

module "frontend" {
  source = "../../../modules/frontend"

  name_prefix   = local.name_prefix
  deploy_branch = "main"
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
