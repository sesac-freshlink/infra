provider "aws" {
  region = "ap-northeast-2"

  # Environment 태그는 팀원 IAM 권한(dev Cognito 조회, SSM 접속)이 dev 리소스를 가려내는 기준이다. 빼지 않는다.
  default_tags {
    tags = {
      Project     = "freshlink"
      Environment = "dev"
      ManagedBy   = "terraform"
      StateKey    = "dev/cluster"
    }
  }
}

# helm·kubernetes는 aws CLI로 그때그때 토큰을 받는다(PC는 AWS_PROFILE, Actions는 OIDC Role 자격 증명).
locals {
  kube_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", "ap-northeast-2"]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec                   = local.kube_exec
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = local.kube_exec.api_version
    command     = local.kube_exec.command
    args        = local.kube_exec.args
  }
}
