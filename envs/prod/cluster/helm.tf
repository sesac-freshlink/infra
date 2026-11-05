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
  # 쓰지 않는 dex(SSO)는 끈다(노드 자원 절약).
  # notifications: 동기화 실패·Health Degraded·Missing을 Discord 오류 채널로 보낸다(README 4-24).
  # 웹훅 주소는 여기·gitops에 쓰지 않는다. gitops argocd/apps가 ExternalSecret으로 Secrets Manager 값을
  # argocd-notifications-secret(키 discord-webhook-url)에 넣는다. 그래서 차트가 그 Secret을 만들지 않게 한다.
  values = [yamlencode({
    dex = { enabled = false }
    notifications = {
      enabled   = true
      argocdUrl = "https://localhost:8443" # README 4-6 port-forward 주소. 링크는 port-forward를 켠 PC에서 열린다
      context   = { env = "prod" }
      secret    = { create = false }
      notifiers = {
        "service.webhook.discord" = yamlencode({
          url = "$discord-webhook-url"
          headers = [
            { name = "Content-Type", value = "application/json" },
            { name = "User-Agent", value = "freshlink-argocd-notifications/1.0" }, # Discord는 기본 User-Agent를 막기도 한다
          ]
        })
      }
      templates = local.argocd_notification_templates
      triggers  = local.argocd_notification_triggers
      # 모든 Application(root, 서비스 6개, 관측성 4개)에 건다
      subscriptions = [{
        recipients = ["discord"]
        triggers   = ["on-sync-failed", "on-health-degraded", "on-missing"]
      }]
    }
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
        for svc in ["gateway", "member-service", "inventory-service", "order-service", "logistics-simulator", "notification-service"] :
        svc => module.irsa.role_arns[svc]
      }
      env = {
        AWS_REGION           = local.region
        COGNITO_ISSUER_URI   = local.persistent.cognito_issuer_uri    # gateway 토큰 iss 확인
        COGNITO_CLIENT_ID    = local.persistent.cognito_bff_client_id # gateway 토큰 aud 확인. prod는 11/3 BFF로 전환(web 토큰은 401)
        COGNITO_USER_POOL_ID = local.persistent.cognito_user_pool_id  # member-service 점포 등록(AD-01)
        # BFF(10/28). prod는 11/3 경우님 코드가 main에 릴리스될 때 위 COGNITO_CLIENT_ID를 bff로 바꿨다(dev는 10/29).
        # 경우님이 프론트를 다 옮기면 web 클라이언트와 함께 아래 BFF 값을 정리한다. 시크릿은 ExternalSecret으로 따로 들어간다
        COGNITO_BFF_CLIENT_ID = local.persistent.cognito_bff_client_id # gateway AdminInitiateAuth·SECRET_HASH
        COGNITO_DOMAIN_URL    = local.persistent.cognito_domain_url    # gateway 구글 로그인 /oauth2/authorize·/oauth2/token
        FRONTEND_URL          = local.persistent.frontend_url          # gateway 구글 콜백 redirect_uri(<주소>/api/auth/callback)·로그인 뒤 돌아갈 곳
        STORE_IMAGE_BUCKET    = local.persistent.frontend_bucket       # member-service 점포 이미지 presigned PUT (키는 images/stores/{storeId}/...)
      }
      # 관측성(할 일 16). gitops argocd/apps templates/observability.yaml의 loki Application이 쓴다
      observability = {
        loki = {
          bucket  = local.persistent.loki_bucket
          roleArn = module.irsa.role_arns["loki"]
        }
        # Grafana CloudWatch 데이터 소스. gitops가 Grafana 서비스 계정 주석으로 단다
        grafana = {
          roleArn = module.irsa.role_arns["grafana"]
        }
      }
      # ArgoCD 알림 웹훅(README 4-24). gitops argocd/apps가 이 비밀로 argocd-notifications-secret을 만든다
      notifications = {
        webhookSecretName = local.persistent.error_webhook_secret_name
      }
    }
  })]

  # order-service의 Valkey 비밀이 먼저 있어야 파드가 바로 뜬다(없으면 ExternalSecret이 만들어질 때까지 기다린다)
  depends_on = [helm_release.argocd, helm_release.external_secrets, module.cache]
}

# ---------------------------------------------------------------------------
# ArgoCD 알림 내용(README 4-24). Discord 웹훅 본문 {"content": "..."}을 toJson으로 만들어 메시지의 따옴표·줄바꿈이 JSON을 깨지 않게 한다.
# 메시지: 환경, 앱 이름, 리비전(커밋 7자리), 이유, ArgoCD 링크.
# ---------------------------------------------------------------------------
locals {
  # 공통 꼬리: 리비전·링크. operationState가 없을 수 있어 dig로 꺼낸다
  argocd_notification_footer = <<-EOT
    {{- $rev := dig "status" "sync" "revision" "" .app | trunc 7 -}}
    {{- $link := printf "%s/applications/%s/%s" .context.argocdUrl .app.metadata.namespace .app.metadata.name -}}
  EOT

  argocd_notification_templates = {
    "template.app-sync-failed" = yamlencode({
      webhook = {
        discord = {
          method = "POST"
          body   = <<-EOT
            ${local.argocd_notification_footer}
            {{- $msg := dig "status" "operationState" "message" "" .app | trunc 500 -}}
            {"content": {{ printf ":x: **[%s] ArgoCD 동기화 실패** `%s`\n리비전: `%s`\n이유: %s\n<%s>" .context.env .app.metadata.name $rev $msg $link | toJson }}}
          EOT
        }
      }
    })
    "template.app-health-degraded" = yamlencode({
      webhook = {
        discord = {
          method = "POST"
          body   = <<-EOT
            ${local.argocd_notification_footer}
            {{- $msg := dig "status" "health" "message" "" .app | trunc 500 -}}
            {"content": {{ printf ":warning: **[%s] ArgoCD Health Degraded** `%s`\n리비전: `%s`\n%s\n<%s>" .context.env .app.metadata.name $rev $msg $link | toJson }}}
          EOT
        }
      }
    })
    "template.app-missing" = yamlencode({
      webhook = {
        discord = {
          method = "POST"
          body   = <<-EOT
            ${local.argocd_notification_footer}
            {"content": {{ printf ":ghost: **[%s] ArgoCD Missing** `%s` 리소스가 클러스터에 없다(지워졌거나 만들지 못했다)\n리비전: `%s`\n<%s>" .context.env .app.metadata.name $rev $link | toJson }}}
          EOT
        }
      }
    })
  }

  argocd_notification_triggers = {
    # 같은 리비전에서는 한 번만(selfHeal이 다시 시도해도 같은 실패를 되풀이해 보내지 않게)
    "trigger.on-sync-failed" = yamlencode([{
      description = "Application syncing has failed"
      oncePer     = "app.status.sync.revision"
      send        = ["app-sync-failed"]
      when        = "app.status.operationState != nil and app.status.operationState.phase in ['Error', 'Failed']"
    }])
    # Healthy → Degraded로 바뀔 때마다. 파드가 계속 죽으면(CrashLoop) 한 번만 온다
    "trigger.on-health-degraded" = yamlencode([{
      description = "Application has degraded"
      send        = ["app-health-degraded"]
      when        = "app.status.health.status == 'Degraded'"
    }])
    # 클러스터를 새로 만들 때 처음 몇 분은 모든 앱이 Missing·OutOfSync라 그때는 보내지 않는다.
    # 동기화가 끝난(Synced) 뒤 리소스가 사라졌을 때만 보낸다
    "trigger.on-missing" = yamlencode([{
      description = "Application resources are missing after sync"
      send        = ["app-missing"]
      when        = "app.status.health.status == 'Missing' and app.status.sync.status == 'Synced'"
    }])
  }
}
