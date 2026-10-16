# dev 유지 묶음 (할 일 3): 네트워크, RDS + SSM 접속용 nano + 앱 DB 비밀, 켜고 끄기 일정, SQS, 토스 키 비밀.
# 할 일 6: Cognito User Pool + 가입 확인 Lambda + member Cognito 관리자 정책 + 시드 계정 비밀.
# 주말에도 그대로 둔다. RDS·nano는 스케줄러가 평일 09:00에 켜고 21:00·23:00에 끈다.

locals {
  env         = "dev"
  name_prefix = "freshlink-dev"
}

module "network" {
  source = "../../../modules/network"

  name_prefix = local.name_prefix
  vpc_cidr    = "10.0.0.0/16"
}

module "rds" {
  source = "../../../modules/rds"

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
  enabled                 = var.scheduler_enabled
}

module "cognito" {
  source = "../../../modules/cognito"

  name_prefix                 = local.name_prefix
  secret_recovery_window_days = 0 # dev는 지우고 다시 만들 때 이름이 바로 비게
}

module "messaging" {
  source = "../../../modules/messaging"

  env        = local.env
  developers = var.developers
}

# 토스페이먼츠 테스트 키. 값은 Terraform에 넣지 않고 김진아가 README 4-4 명령으로 넣는다(state에 남지 않게).
resource "aws_secretsmanager_secret" "toss" {
  name                    = "${local.name_prefix}-toss"
  description             = "Toss Payments test keys (clientKey, secretKey)"
  recovery_window_in_days = 0
}
