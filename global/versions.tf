terraform {
  # backend "s3"의 use_lockfile(S3 자체 잠금, DynamoDB 없음)은 1.11부터 정식 기능이다
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket은 레포 루트 backend.hcl에서 받는다: terraform init -backend-config=../backend.hcl
  # 맨 처음 한 번은 버킷이 없으므로 README 4장의 순서(로컬 state로 만든 뒤 옮기기)를 따른다.
  backend "s3" {
    key          = "global/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
