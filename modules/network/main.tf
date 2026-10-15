# VPC, 서브넷 6개(AZ마다 public·app·db), IGW, 라우팅 테이블 3종, S3 Gateway 엔드포인트.
# NAT Gateway는 여기 두지 않는다. 시간당 과금이라 cluster 묶음이 만들고 지우며,
# 그때 app 라우팅 테이블(output app_route_table_id)에 0.0.0.0/0 → NAT 경로를 넣는다.

data "aws_region" "current" {}

locals {
  az_suffix = [for az in var.availability_zones : substr(az, -1, 1)] # ["a", "c"]

  # aws-리소스-계획.md 5-2: public x.x.0.0/24·1.0/24, app x.x.16.0/20·32.0/20, db x.x.48.0/24·49.0/24
  public_cidrs = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i)]
  app_cidrs    = [for i in range(2) : cidrsubnet(var.vpc_cidr, 4, i + 1)]
  db_cidrs     = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, 48 + i)]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # SSM·RDS 엔드포인트 이름 풀이에 필요

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = local.public_cidrs[count.index]
  map_public_ip_on_launch = false # 공인 IP는 필요한 리소스만 직접 켠다

  tags = {
    Name                     = "${var.name_prefix}-public-${local.az_suffix[count.index]}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1" # AWS Load Balancer Controller가 인터넷용 ALB를 둘 곳
  }
}

resource "aws_subnet" "app" {
  count = 2

  vpc_id            = aws_vpc.this.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = local.app_cidrs[count.index]

  tags = {
    Name                              = "${var.name_prefix}-app-${local.az_suffix[count.index]}"
    Tier                              = "app"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "db" {
  count = 2

  vpc_id            = aws_vpc.this.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = local.db_cidrs[count.index]

  tags = {
    Name = "${var.name_prefix}-db-${local.az_suffix[count.index]}"
    Tier = "db"
  }
}

# public: 0.0.0.0/0 → IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# app: 두 AZ가 같은 테이블을 쓴다(NAT는 public-a에 1개). 기본 경로는 cluster 묶음이 NAT와 함께 넣는다.
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-app-rt" }
}

resource "aws_route_table_association" "app" {
  count = 2

  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# db: VPC 내부 경로(local)만. 인터넷으로 나갈 길이 아예 없다.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-db-rt" }
}

resource "aws_route_table_association" "db" {
  count = 2

  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# S3 Gateway 엔드포인트(무료): ECR 이미지 레이어 등 S3 트래픽이 NAT를 거치지 않는다.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id, aws_route_table.public.id]

  tags = { Name = "${var.name_prefix}-s3-endpoint" }
}
