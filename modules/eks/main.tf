# EKS 클러스터, 관리형 노드 그룹 1개, IRSA용 OIDC 공급자, 애드온 4개(VPC CNI, kube-proxy, CoreDNS, EBS CSI).
# 금요일에 지우고 월요일에 다시 만드는 cluster 묶음에서 부른다. 지울 때 사람 손이 필요한 것을 넣지 않는다.

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition
}

# ---------------------------------------------------------------------------
# 클러스터
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name_prefix}-eks-cluster-role"
  description        = "EKS control plane for ${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # 접근 권한은 아래 access entry로만 준다(aws-auth ConfigMap 안 씀).
  # 만든 사람 자동 관리자는 끈다. 사람(PC)이 만들든 Actions가 만들든 같은 두 주체가 관리자가 되게.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  # 표준 지원이 끝나도 Extended Support(시간당 0.60 USD)로 넘어가지 않게 한다.
  upgrade_policy {
    support_type = "STANDARD"
  }

  vpc_config {
    subnet_ids = var.subnet_ids
    # 공개 엔드포인트: PC와 GitHub Actions 러너(IP가 매번 바뀐다)에서 kubectl·helm을 쓴다. 인증은 IAM.
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = aws_eks_access_entry.admin

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# 팀원: 관리자 권한 없이 Grafana·Zipkin을 port-forward로 열고, 서비스 파드·로그를 본다(QA, 2026-10-27).
# observability는 편집(port-forward에 pods/portforward가 필요하다), freshlink는 보기만. 다른 네임스페이스는 권한 없음.
locals {
  developer_access = merge([
    for arn in var.developer_principal_arns : {
      "${arn}|observability" = { principal_arn = arn, namespace = "observability", policy = "AmazonEKSEditPolicy" }
      "${arn}|freshlink"     = { principal_arn = arn, namespace = "freshlink", policy = "AmazonEKSViewPolicy" }
    }
  ]...)
}

resource "aws_eks_access_entry" "developer" {
  for_each = toset(var.developer_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "developer" {
  for_each = local.developer_access

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.developer[each.value.principal_arn].principal_arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/${each.value.policy}"

  access_scope {
    type       = "namespace"
    namespaces = [each.value.namespace]
  }
}

# IRSA: 파드가 ServiceAccount 토큰으로 IAM Role을 맡는다.
resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}

# ---------------------------------------------------------------------------
# 노드 그룹
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name_prefix}-eks-node-role"
  description        = "EKS worker nodes for ${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",               # VPC CNI가 노드 Role로 ENI·IP를 받는다
    "AmazonEC2ContainerRegistryPullOnly", # ECR 이미지 받기
    "AmazonSSMManagedInstanceCore",       # 노드 접속은 SSH 대신 SSM Session Manager
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND" # 시연 중 회수되면 안 되므로 스팟을 쓰지 않는다
  instance_types = [var.node_instance_type]
  disk_size      = 20

  scaling_config {
    desired_size = var.node_desired_size
    # 밤에 스케줄러가 desired를 0으로 내리므로 min은 0이어야 한다.
    min_size = 0
    max_size = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # 스케줄러가 바꾼 desired 값을 apply가 되돌리지 않게 한다(aws-리소스-계획.md 6-5).
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_nodes,
  ]
}

# ---------------------------------------------------------------------------
# 애드온. 버전은 이 Kubernetes 버전의 기본값(most_recent = false)이라 버전을 올릴 때만 바뀐다.
# ---------------------------------------------------------------------------
locals {
  # 노드가 뜨기 전에 있어야 하는 것(파드 네트워크·서비스 프록시)
  addons_before_nodes = ["vpc-cni", "kube-proxy"]
}

data "aws_eks_addon_version" "this" {
  for_each = toset(concat(local.addons_before_nodes, ["coredns", "aws-ebs-csi-driver"]))

  addon_name         = each.value
  kubernetes_version = aws_eks_cluster.this.version
}

resource "aws_eks_addon" "before_nodes" {
  for_each = toset(local.addons_before_nodes)

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  addon_version               = data.aws_eks_addon_version.this[each.value].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# CoreDNS는 파드라 노드가 있어야 ACTIVE가 된다.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.this["coredns"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

# EBS CSI 드라이버: Prometheus 볼륨(PVC)용. 권한은 IRSA Role로 받는다(var.ebs_csi_role_arn).
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.this["aws-ebs-csi-driver"].version
  service_account_role_arn    = var.ebs_csi_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}
