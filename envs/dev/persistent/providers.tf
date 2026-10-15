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
