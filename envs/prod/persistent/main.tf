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

  # prod 화면은 경우님 BFF 코드가 main에 나갈 때까지 Amplify가 Cognito를 직접 부른다. 그날 이 줄을 지우고 enforce로 바꾼다(README 4-18)
  csp_report_only       = true
  csp_extra_connect_src = ["https://cognito-idp.ap-northeast-2.amazonaws.com"]
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
