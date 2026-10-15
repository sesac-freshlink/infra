# RDS MySQL 1대(스키마 3개), DB 서브넷 그룹, 보안 그룹, 앱 DB 비밀 3개, SSM 접속용 t4g.nano.
# 스키마·앱 사용자는 Terraform이 아니라 사람이 SQL로 만든다(README 4-4). 테이블은 각 서비스 Flyway가 만든다.

data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# 보안 그룹
# ---------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "RDS MySQL: 3306 from SSM access instance and EKS nodes only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-rds-sg" }
}

# EKS 노드 → 3306 규칙은 cluster 묶음이 output rds_security_group_id에 붙인다.
resource "aws_vpc_security_group_ingress_rule" "rds_from_ssm" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from SSM access instance"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.ssm_access.id
}

# 인바운드 규칙이 하나도 없다. SSM 에이전트가 밖으로 나가 세션을 받는다.
resource "aws_security_group" "ssm_access" {
  name        = "${var.name_prefix}-ssm-access-sg"
  description = "SSM access instance: no inbound, HTTPS out for SSM agent, 3306 to RDS"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-ssm-access-sg" }
}

resource "aws_vpc_security_group_egress_rule" "ssm_https" {
  security_group_id = aws_security_group.ssm_access.id
  description       = "HTTPS to SSM endpoints and OS package repos"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "ssm_to_rds" {
  security_group_id            = aws_security_group.ssm_access.id
  description                  = "MySQL to RDS (port forwarding)"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.rds.id
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-db-subnets"
  description = "db-a, db-c (no internet route)"
  subnet_ids  = var.db_subnet_ids
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-mysql"
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  username                    = var.master_username
  manage_master_user_password = true # 비밀번호를 RDS가 만들고 Secrets Manager에 둔다. state에 남지 않는다

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  # 시각은 UTC. 켜 두는 평일 낮(한국 12시대)에 잡는다. 꺼져 있는 밤에는 백업이 돌지 않는다.
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-03:30" # 한국 12:00
  maintenance_window      = "wed:03:40-wed:04:10"

  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = true # dev·prod 데이터는 다시 넣을 수 있는 더미·시연 데이터
}

# ---------------------------------------------------------------------------
# 앱 DB 비밀 (서비스마다 하나, External Secrets Operator와 팀원이 읽는다)
# 비밀번호는 ephemeral로 만들어 쓰기 전용 속성(secret_string_wo)에 넣으므로 state에 남지 않는다.
# app_password_version을 올릴 때만 새 값을 쓴다.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "app_db" {
  for_each = var.app_databases

  name                    = "${var.name_prefix}-${each.key}-db"
  description             = "${each.key} service DB user (${each.value.username}, schema ${each.value.schema})"
  recovery_window_in_days = var.secret_recovery_window_days
}

ephemeral "random_password" "app_db" {
  for_each = var.app_databases

  length           = 24
  special          = true
  override_special = "!#%^*-_=+" # SQL 작은따옴표·JDBC URL·PowerShell에서 문제없는 기호만
}

resource "aws_secretsmanager_secret_version" "app_db" {
  for_each = var.app_databases

  secret_id = aws_secretsmanager_secret.app_db[each.key].id
  secret_string_wo = jsonencode({
    engine   = "mysql"
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = each.value.schema
    username = each.value.username
    password = ephemeral.random_password.app_db[each.key].result
  })
  secret_string_wo_version = var.app_password_version
}

# ---------------------------------------------------------------------------
# SSM 접속용 t4g.nano
# public 서브넷 + 공인 IP에 둔다. NAT는 cluster 묶음에 있어 밤·주말·클러스터를 만들기 전에는 없으므로,
# app 서브넷에 두면 SSM 에이전트가 AWS에 닿지 못한다. 인바운드 규칙이 없어 밖에서 들어올 길은 없다.
# 공인 IPv4 요금(0.005 USD/시간)은 켜져 있는 동안만 붙는다.
# ---------------------------------------------------------------------------
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64" # SSM 에이전트가 들어 있는 이미지
}

data "aws_iam_policy_document" "ssm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_access" {
  name               = "${var.name_prefix}-ssm-access-role"
  description        = "SSM access instance: Session Manager only"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_access.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_access" {
  name = "${var.name_prefix}-ssm-access-profile"
  role = aws_iam_role.ssm_access.name
}

resource "aws_instance" "ssm_access" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.value
  instance_type               = var.ssm_instance_type
  subnet_id                   = var.ssm_access_subnet_id
  vpc_security_group_ids      = [aws_security_group.ssm_access.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm_access.name
  associate_public_ip_address = true

  metadata_options {
    http_tokens   = "required" # IMDSv2만
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  # 팀원 IAM은 태그 Environment(provider default_tags)로 이 인스턴스에만 포트 포워딩을 허용한다.
  tags = { Name = "${var.name_prefix}-ssm-access" }

  lifecycle {
    # 새 AMI가 나와도 인스턴스를 다시 만들지 않는다(인스턴스 ID가 바뀌면 팀원 명령도 바뀐다)
    ignore_changes = [ami]
  }
}
