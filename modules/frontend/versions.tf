terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      # CloudFront 인증서는 us-east-1에서만 만든다. 부르는 쪽(envs/<env>/persistent)이 넘긴다
      configuration_aliases = [aws.us_east_1]
    }
  }
}
