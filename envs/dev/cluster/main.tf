# dev 클러스터 묶음 (할 일 7): NAT Gateway, EKS + 노드 그룹 + 애드온, IRSA Role, Helm 4개, gp3 StorageClass, 노드 → RDS 3306.
# 금요일 21:00에 지우고 월요일 08:40에 다시 만든다(.github/workflows/dev-cluster.yml). 지우고 다시 만들 때 사람 손이 필요한 것을 넣지 않는다.
# 같은 환경 persistent 묶음의 값을 remote state로 읽는다(반대 방향 금지).

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "freshlink-dev"
  partition   = data.aws_partition.current.partition
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region

  persistent = data.terraform_remote_state.persistent.outputs

  # 큐 세트 "shared"(dev-)만 클러스터 파드가 쓴다. 개발자별 큐는 각자 PC에서 IAM 사용자로 쓴다.
  # 순서: [commands.fifo, commands-dlq.fifo, results, results-dlq] (modules/messaging outputs)
  queue_commands = local.persistent.queue_arns["shared"][0]
  queue_results  = local.persistent.queue_arns["shared"][2]

  app_namespace           = "freshlink"     # gitops 앱 네임스페이스
  observability_namespace = "observability" # gitops 관측성 네임스페이스
}

data "terraform_remote_state" "persistent" {
  backend = "s3"
  config = {
    # global/tfstate.tf와 같은 규칙: freshlink-tfstate-<계정 ID 끝 4자리>
    bucket = "freshlink-tfstate-${substr(local.account_id, 8, 4)}"
    key    = "dev/persistent/terraform.tfstate"
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
  # 팀원 사용자는 global에서 path /freshlink/로 만든다. access entry ARN에도 path가 들어가야 맞는다
  developer_principal_arns = [for u in var.developer_iam_users : "arn:${local.partition}:iam::${local.account_id}:user/freshlink/${u}"]
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
# 선착순 대기열 Valkey(2차). 클러스터와 같이 만들고 지운다. order-service가 REDIS_HOST·REDIS_PORT로 받는다
# ---------------------------------------------------------------------------
module "cache" {
  source = "../../../modules/cache"

  name_prefix              = local.name_prefix
  vpc_id                   = local.persistent.vpc_id
  subnet_ids               = local.persistent.app_subnet_ids
  client_security_group_id = module.eks.cluster_security_group_id
}

# ---------------------------------------------------------------------------
# IRSA Role: 서비스 5개 + 클러스터 부품 3개 + Loki
# ---------------------------------------------------------------------------
# gateway BFF(10/28): 로그인·토큰 갱신(AdminInitiateAuth)만 이 User Pool에. SignUp·ConfirmSignUp·RevokeToken·/oauth2/token은
# IAM이 필요 없는 공개 API라 bff 클라이언트 시크릿(ExternalSecret)만 있으면 된다.
data "aws_iam_policy_document" "gateway" {
  statement {
    sid       = "BffLoginInThisPool"
    actions   = ["cognito-idp:AdminInitiateAuth"]
    resources = [local.persistent.cognito_user_pool_arn]
  }
}

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

# External Secrets Operator: 앱 DB 비밀 3개, 토스 키, gateway bff 클라이언트 비밀, order Valkey 주소만 읽는다(시드 계정 비밀은 읽지 않는다).
data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid     = "ReadAppSecrets"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = concat(
      values(local.persistent.app_db_secret_arns),
      # 비밀 ARN 끝에 무작위 6자리가 붙는다
      ["arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${local.persistent.toss_secret_name}-??????"],
      [local.persistent.cognito_gateway_secret_arn], # gateway bff 클라이언트 ID·시크릿
      [module.cache.order_redis_secret_arn],         # order Valkey 주소·포트
    )
  }
}

# Loki(gitops platform/observability): persistent 묶음의 로그 버킷만 읽고 쓴다.
data "aws_iam_policy_document" "loki" {
  statement {
    sid       = "ListLogBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.persistent.loki_bucket_arn]
  }
  statement {
    sid       = "ReadWriteLogObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.persistent.loki_bucket_arn}/*"]
  }
}

module "irsa" {
  source = "../../../modules/irsa"

  name_prefix       = local.name_prefix
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer       = module.eks.oidc_issuer

  roles = {
    gateway = {
      namespace       = local.app_namespace
      service_account = "gateway"
      policy_json     = data.aws_iam_policy_document.gateway.json
    }
    member-service = {
      namespace       = local.app_namespace
      service_account = "member-service"
      policy_arns     = [local.persistent.member_cognito_policy_arn] # 할 일 6에서 만든 dev User Pool 관리자 정책
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
    loki = {
      namespace       = local.observability_namespace
      service_account = "loki" # gitops platform/observability/values/loki.yaml serviceAccount.name
      policy_json     = data.aws_iam_policy_document.loki.json
    }
  }
}
