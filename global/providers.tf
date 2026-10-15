provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "freshlink"
      Environment = "global"
      ManagedBy   = "terraform"
      StateKey    = "global"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
}
