terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # 가입 확인 Lambda 코드(lambda/post_confirmation.py)를 zip으로 묶는다
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}
