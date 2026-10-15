terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # ephemeral random_password: 앱 DB 비밀번호를 state에 남기지 않고 만든다 (3.7부터)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
