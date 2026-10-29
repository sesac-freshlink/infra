# Terraform이 Helm으로 설치하는 4개(aws-리소스-계획.md 8장)와 ArgoCD root Application. 관측성 스택과 앱은 ArgoCD가 gitops 레포에서 설치한다.
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

# App of Apps 시작점(root Application) 등록. 이 뒤로 클러스터 안의 앱은 전부 gitops 레포가 정한다.
# 계정·클러스터마다 다른 값(ECR 주소, IRSA Role ARN, Cognito 주소·클라이언트 ID)은 공개 레포인 gitops에 적지 않고 여기서 넘긴다.
# ArgoCD(Application CRD)와 External Secrets Operator(ClusterSecretStore CRD)가 먼저 떠 있어야 한다.
resource "helm_release" "argocd_root" {
  name      = "argocd-root"
  namespace = "argocd"
  chart     = "${path.module}/../../../charts/argocd-root"

  values = [yamlencode({
    env = "prod"
    cluster = {
      imageRegistry = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
      irsaRoleArns = {
        for svc in ["gateway", "member-service", "inventory-service", "order-service", "logistics-simulator"] :
        svc => module.irsa.role_arns[svc]
      }
      env = {
        AWS_REGION           = local.region
        COGNITO_ISSUER_URI   = local.persistent.cognito_issuer_uri    # gateway 토큰 iss 확인
        COGNITO_CLIENT_ID    = local.persistent.cognito_app_client_id # gateway 토큰 aud 확인
        COGNITO_USER_POOL_ID = local.persistent.cognito_user_pool_id  # member-service 점포 등록(AD-01)
        # BFF(10/28). 전환하는 날 위 COGNITO_CLIENT_ID를 cognito_bff_client_id로 바꾸고(토큰 aud가 bff가 된다)
        # 경우님이 프론트를 다 옮기면 web 클라이언트와 함께 아래 BFF 값을 정리한다. 시크릿은 ExternalSecret으로 따로 들어간다
        COGNITO_BFF_CLIENT_ID = local.persistent.cognito_bff_client_id # gateway AdminInitiateAuth·SECRET_HASH
        COGNITO_DOMAIN_URL    = local.persistent.cognito_domain_url    # gateway 구글 로그인 /oauth2/authorize·/oauth2/token
        FRONTEND_URL          = local.persistent.frontend_url          # gateway 구글 콜백 redirect_uri(<주소>/api/auth/callback)·로그인 뒤 돌아갈 곳
      }
      # 관측성(할 일 16). gitops argocd/apps templates/observability.yaml의 loki Application이 쓴다
      observability = {
        loki = {
          bucket  = local.persistent.loki_bucket
          roleArn = module.irsa.role_arns["loki"]
        }
      }
    }
  })]

  depends_on = [helm_release.argocd, helm_release.external_secrets]
}
