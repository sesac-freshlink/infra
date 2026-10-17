# Terraform이 Helm으로 설치하는 4개(aws-리소스-계획.md 8장). 관측성 스택과 앱은 ArgoCD가 gitops 레포에서 설치한다.
# 차트 버전은 고정한다. 모두 노드·애드온이 준비된 뒤(module.eks 전체) 설치하고, destroy 때는 클러스터보다 먼저 지운다.

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.6.0"

  values = [yamlencode({
    clusterName = module.eks.cluster_name
    # AL2023 노드는 IMDS hop limit이 1이라 파드가 리전·VPC를 스스로 못 알아낸다. 직접 넣는다.
    region = local.region
    vpcId  = local.persistent.vpc_id
    serviceAccount = {
      name        = "aws-load-balancer-controller"
      annotations = { "eks.amazonaws.com/role-arn" = module.irsa.role_arns["aws-load-balancer-controller"] }
    }
    # Service 변경 웹훅을 끈다. 켜 두면 컨트롤러가 뜨기 전에 다른 차트가 Service를 만들 때 웹훅 호출이 실패한다.
    # ALB는 Ingress로만 만들고 type LoadBalancer Service는 쓰지 않는다.
    enableServiceMutatorWebhook = false
  })]

  depends_on = [module.eks]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"

  depends_on = [module.eks]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.13.0"

  # SecretStore(어느 비밀을 읽을지)는 gitops 차트가 만든다(할 일 9).
  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      name        = "external-secrets"
      annotations = { "eks.amazonaws.com/role-arn" = module.irsa.role_arns["external-secrets"] }
    }
  })]

  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.10.5"

  # 화면은 kubectl port-forward로 연다(README 4-6). 밖으로 여는 Ingress는 두지 않는다.
  # 쓰지 않는 dex(SSO)·notifications는 끈다(노드 자원 절약).
  values = [yamlencode({
    dex           = { enabled = false }
    notifications = { enabled = false }
  })]

  depends_on = [module.eks]
}

# Prometheus 볼륨용 기본 StorageClass. EKS 1.30부터는 기본 StorageClass가 없다.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name        = "gp3"
    annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete" # PVC를 지우면 EBS도 지운다(금요일 정리)
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [module.eks]
}
