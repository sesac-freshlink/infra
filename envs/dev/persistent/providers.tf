provider "aws" {
  region = "ap-northeast-2"

  # Environment 태그는 팀원 IAM 권한(dev Cognito 조회, SSM 접속)이 dev 리소스를 가려내는 기준이다. 빼지 않는다.
  default_tags {
    tags = {
      Project     = "freshlink"
      Environment = "dev"
      ManagedBy   = "terraform"
      StateKey    = "dev/persistent"
    }
  }
}

# CloudFront 인증서(ACM)는 us-east-1에서만 만들 수 있다. modules/frontend가 이 provider로 인증서를 만든다(README 4-21)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "freshlink"
      Environment = "dev"
      ManagedBy   = "terraform"
      StateKey    = "dev/persistent"
    }
  }
}
