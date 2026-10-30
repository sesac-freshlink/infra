# 선착순 대기열(2차, 10/28 결정)용 ElastiCache for Valkey(Redis 호환) 1대. cluster 묶음에서 부른다.
# 대기열·입장 토큰은 잠깐 쓰는 값이라 클러스터와 같이 만들고 지운다(dev: 월 08:40 생성, 금 21:00 삭제). 복제·백업 없음.
# order-service는 Secrets Manager 비밀(<name_prefix>/order/redis)을 ExternalSecret으로 받아 REDIS_HOST·REDIS_PORT로 쓴다.

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name_prefix}-cache"
  subnet_ids = var.subnet_ids
}

# EKS 노드·파드(클러스터 보안 그룹)에서 6379만 받는다
resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-cache"
  description = "Valkey from EKS nodes and pods"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-cache" }
}

resource "aws_vpc_security_group_ingress_rule" "from_eks" {
  security_group_id            = aws_security_group.this.id
  description                  = "Valkey from EKS"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = var.client_security_group_id
}

# 노드 1개짜리 복제 그룹. 전송 암호화(TLS)를 켜려면 aws_elasticache_cluster가 아니라 복제 그룹으로 만들어야 한다.
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-cache"
  description          = "FreshLink first-come queue (${var.name_prefix})"

  engine               = "valkey"
  engine_version       = var.engine_version
  parameter_group_name = "default.valkey${split(".", var.engine_version)[0]}"
  node_type            = var.node_type
  num_cache_clusters   = 1
  port                 = 6379

  automatic_failover_enabled = false
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  transit_encryption_enabled = true # 클라이언트는 TLS로 붙는다(spring.data.redis.ssl.enabled=true, valkey-cli --tls)
  at_rest_encryption_enabled = true

  snapshot_retention_limit = 0 # 백업 없음(지워져도 되는 값)
  apply_immediately        = true
}

# 접속 정보. 비밀번호는 없지만(보안 그룹으로만 막는다) 다른 서비스 값처럼 Secrets Manager → ExternalSecret 길로 넣는다.
# 클러스터와 같이 지웠다 다시 만들므로 복구 대기 기간을 두지 않는다(두면 월요일에 같은 이름으로 못 만든다).
resource "aws_secretsmanager_secret" "order_redis" {
  name                    = "${var.name_prefix}/order/redis"
  description             = "order-service Valkey endpoint (REDIS_HOST, REDIS_PORT)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "order_redis" {
  secret_id = aws_secretsmanager_secret.order_redis.id
  secret_string = jsonencode({
    host = aws_elasticache_replication_group.this.primary_endpoint_address
    port = tostring(aws_elasticache_replication_group.this.port)
  })
}
