# dev 유지 묶음 (할 일 3): 네트워크, RDS + SSM 접속용 nano + 앱 DB 비밀, 켜고 끄기 일정, SQS, 토스 키 비밀.
# 할 일 6: Cognito User Pool + 가입 확인 Lambda + member Cognito 관리자 정책 + 시드 계정 비밀.
# 할 일 7: 노드 그룹 일정(평일), 켜고 끄기 워크플로가 맡는 GitHub Actions Role, 클러스터·노드 그룹 이름.
# 할 일 13: 프론트 S3 + CloudFront(/api/* → gateway ALB) + frontend 레포 배포 Role.
# 할 일 16: Loki 로그 버킷(S3, 14일). 클러스터를 지워도 로그가 남는다.
# 주말에도 그대로 둔다. RDS·nano는 스케줄러가 평일 09:00에 켜고 21:00·23:00에 끈다.

locals {
  env         = "dev"
  name_prefix = "freshlink-dev"

  # cluster 묶음이 이 이름으로 만든다(remote state로 읽는다). 스케줄러는 이름으로 노드 수를 바꾼다.
  eks_cluster_name    = "${local.name_prefix}-eks"
  eks_node_group_name = "${local.name_prefix}-nodes"
}

module "network" {
  source = "../../../modules/network"

  name_prefix = local.name_prefix
  vpc_cidr    = "10.0.0.0/16"
}

module "rds" {
  source = "../../../modules/rds"

  env                  = local.env
  name_prefix          = local.name_prefix
  vpc_id               = module.network.vpc_id
  db_subnet_ids        = module.network.db_subnet_ids
  ssm_access_subnet_id = module.network.public_subnet_ids[0] # public-a

  apply_immediately           = true
  secret_recovery_window_days = 0 # dev는 지우고 다시 만들 때 이름이 바로 비게
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
}

# 켜고 끄기 워크플로(dev-cluster.yml)를 정해진 시각에 실행한다. GitHub 예약은 몇 시간 늦거나 빠져서
# 시각은 여기서 지킨다(2026-10-20). 워크플로 안의 GitHub 예약은 예비로 남고, 늦게 오면 시각을 보고 건너뛴다.
# 두 번 돌아도 바뀌는 것이 없다(concurrency로 한 줄로 서고, 이미 된 상태면 변경 없음).
module "cluster_dispatch" {
  source = "../../../modules/workflow-dispatch"

  name_prefix = local.name_prefix
  enabled     = var.scheduler_enabled
  schedules = {
    create       = { cron = "cron(40 8 ? * MON *)", action = "create" }       # 월 08:40 클러스터 생성 (노드 2대·NAT 포함)
    nat-on       = { cron = "cron(50 8 ? * TUE-FRI *)", action = "nat-on" }   # 화·수·목·금 08:50 NAT 생성 (노드 09:10보다 먼저)
    nat-off      = { cron = "cron(10 21 ? * MON-THU *)", action = "nat-off" } # 월·화·수·목 21:10 NAT 삭제
    destroy      = { cron = "cron(5 21 ? * FRI *)", action = "destroy" }      # 금 21:05 클러스터 삭제
    nat-off-late = { cron = "cron(5 23 * * ? *)", action = "nat-off" }        # 매일 23:05 NAT가 남아 있으면 삭제
  }
}

module "cluster_actions" {
  source = "../../../modules/cluster-actions"

  name_prefix = local.name_prefix
}

module "cognito" {
  source = "../../../modules/cognito"

  name_prefix                 = local.name_prefix
  secret_recovery_window_days = 0    # dev는 지우고 다시 만들 때 이름이 바로 비게
  admin_password_auth         = true # gateway 401·403 시험 토큰을 PowerShell로 받는다(README 4-7)
}

module "messaging" {
  source = "../../../modules/messaging"

  env        = local.env
  developers = var.developers
}

module "frontend" {
  source = "../../../modules/frontend"

  name_prefix   = local.name_prefix
  deploy_branch = "dev"
  force_destroy = true # dev는 빌드 파일만 있어서 지워도 된다
}

module "observability" {
  source = "../../../modules/observability"

  name_prefix   = local.name_prefix
  force_destroy = true # dev 로그는 지워도 된다
}

# 토스페이먼츠 테스트 키. 값은 Terraform에 넣지 않고 김진아가 README 4-4 명령으로 넣는다(state에 남지 않게).
resource "aws_secretsmanager_secret" "toss" {
  name                    = "${local.name_prefix}-toss"
  description             = "Toss Payments test keys (clientKey, secretKey)"
  recovery_window_in_days = 0
}
