terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # 비용 메일 Lambda 코드(lambda/cost_report.py)를 zip으로 묶는다
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}
