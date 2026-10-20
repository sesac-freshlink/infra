# prod 클러스터 묶음 (할 일 14): dev 클러스터 묶음(envs/dev/cluster)과 같은 모듈·차트를 부르고 이름만 다르다.
# 평소에는 없다. 필요한 날 dev-cluster 워크플로를 env=prod로 create 해서 만들고, destroy로 지운다(매일 21:05 자동 삭제).
# 같은 환경 persistent 묶음의 값을 remote state로 읽는다(반대 방향 금지).

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "freshlink-prod"
  partition   = data.aws_partition.current.partition
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region

  persistent = data.terraform_remote_state.persistent.outputs

  # 큐 세트 "shared"(prod-)만 있다(prod는 개발자별 큐 없음).
  # 순서: [commands.fifo, commands-dlq.fifo, results, results-dlq] (modules/messaging outputs)
  queue_commands = local.persistent.queue_arns["shared"][0]
  queue_results  = local.persistent.queue_arns["shared"][2]

  app_namespace = "freshlink" # gitops 앱 네임스페이스
}

data "terraform_remote_state" "persistent" {
  backend = "s3"
  config = {
    # global/tfstate.tf와 같은 규칙: freshlink-tfstate-<계정 ID 끝 4자리>
    bucket = "freshlink-tfstate-${substr(local.account_id, 8, 4)}"
    key    = "prod/persistent/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# ---------------------------------------------------------------------------
# NAT Gateway (public-a에 1개). 밤에는 워크플로가 nat_enabled=false로 지운다.
# 노드가 ECR·SQS·Cognito에 닿으려면 NAT가 있어야 한다. 클러스터 생성(10분 넘게)보다 NAT(2분 안팎)가
# 먼저 끝나므로 노드 그룹이 생길 때는 경로가 이미 있다.
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count = var.nat_enabled ? 1 : 0

  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-nat-eip" }
}

resource "aws_nat_gateway" "this" {
  count = var.nat_enabled ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = local.persistent.public_subnet_ids[0] # public-a
  tags          = { Name = "${local.name_prefix}-nat" }
}

resource "aws_route" "app_nat" {
  count = var.nat_enabled ? 1 : 0

  route_table_id         = local.persistent.app_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------
module "eks" {
  source = "../../../modules/eks"

  name_prefix        = local.name_prefix
  cluster_name       = local.persistent.eks_cluster_name
  node_group_name    = local.persistent.eks_node_group_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = local.persistent.app_subnet_ids
  ebs_csi_role_arn   = module.irsa.role_arns["ebs-csi-driver"]

  admin_principal_arns = concat(
    [local.persistent.cluster_actions_role_arn],
    [for u in var.admin_iam_users : "arn:${local.partition}:iam::${local.account_id}:user/${u}"],
  )
}

# 노드·파드 → RDS 3306. 관리형 노드 그룹(시작 템플릿 없음)은 EKS 클러스터 보안 그룹을 쓴다.
resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = local.persistent.rds_security_group_id
  description                  = "MySQL from EKS nodes and pods"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = module.eks.cluster_security_group_id
}

# ---------------------------------------------------------------------------
# IRSA Role: 서비스 4개(gateway는 AWS를 부르지 않아 없음) + 클러스터 부품 3개
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "inventory_service" {
  statement {
    sid       = "ConsumeCommands"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
    resources = [local.queue_commands]
  }
  statement {
    sid       = "SendCommandsAndResults"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
    resources = [local.queue_commands, local.queue_results] # DISPOSE는 자기 commands 큐로 보낸다
  }
}

data "aws_iam_policy_document" "order_service" {
  statement {
    sid       = "SendCommands"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
    resources = [local.queue_commands]
  }
  statement {
    sid       = "ConsumeResults"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
    resources = [local.queue_results]
  }
}

data "aws_iam_policy_document" "logistics_simulator" {
  statement {
    sid       = "SendInbound"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
    resources = [local.queue_commands]
  }
}

# External Secrets Operator: 앱 DB 비밀 3개와 토스 키만 읽는다(시드 계정 비밀은 읽지 않는다).
data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid     = "ReadAppSecrets"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = concat(
      values(local.persistent.app_db_secret_arns),
      # 비밀 ARN 끝에 무작위 6자리가 붙는다
      ["arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${local.persistent.toss_secret_name}-??????"],
    )
  }
}

module "irsa" {
  source = "../../../modules/irsa"

  name_prefix       = local.name_prefix
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer       = module.eks.oidc_issuer

  roles = {
    member-service = {
      namespace       = local.app_namespace
      service_account = "member-service"
      policy_arns     = [local.persistent.member_cognito_policy_arn] # prod User Pool 관리자 정책
    }
    inventory-service = {
      namespace       = local.app_namespace
      service_account = "inventory-service"
      policy_json     = data.aws_iam_policy_document.inventory_service.json
    }
    order-service = {
      namespace       = local.app_namespace
      service_account = "order-service"
      policy_json     = data.aws_iam_policy_document.order_service.json
    }
    logistics-simulator = {
      namespace       = local.app_namespace
      service_account = "logistics-simulator"
      policy_json     = data.aws_iam_policy_document.logistics_simulator.json
    }
    aws-load-balancer-controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      # 컨트롤러 v3.6.0 공식 정책(docs/install/iam_policy.json) 그대로. 차트 버전을 올리면 같이 바꾼다.
      policy_json = file("${path.module}/../../../modules/irsa/policies/aws-load-balancer-controller.json")
    }
    ebs-csi-driver = {
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
      policy_arns     = ["arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
    }
    external-secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      policy_json     = data.aws_iam_policy_document.external_secrets.json
    }
  }
}
