terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # 실행 요청 Lambda 코드(lambda/dispatch.py)를 zip으로 묶는다
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}
