terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket은 레포 루트 backend.hcl에서 받는다: terraform init -backend-config=../../../backend.hcl
  backend "s3" {
    key          = "dev/cluster/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
