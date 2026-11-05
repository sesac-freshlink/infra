# 인프라 오류 알림(3차 할 일 "디스코드 알림"): CloudWatch 경보·비용 이상·켜고 끄기 워크플로 실패 → SNS → Lambda → Discord 오류 채널.
# DLQ 알림(modules/dlq-alert)·배포 알림(GitHub 비밀 DEPLOY_WEBHOOK_URL)과는 다른 채널·다른 비밀이다.
# 웹훅 주소는 Terraform에 넣지 않는다. 빈 비밀(<접두사>-error-webhook)만 만들고 값은 scripts/set-error-webhook.ps1로 넣는다.
# 같은 비밀을 클러스터의 External Secrets가 argocd-notifications-secret으로 가져가 ArgoCD 알림도 같은 채널로 보낸다(gitops).
#
# 경보 1개(지표 1개)에 월 0.10 USD라 꼭 볼 것만 건다. 기준값은 variables.tf, 이유는 README 4-24.
# 여기 경보는 늘 있는 리소스(RDS, 켜고 끄기 Lambda)에만 건다. 클러스터와 같이 생기고 지워지는 것은
#   노드 상태 → envs/<env>/cluster(노드 그룹 Auto Scaling 그룹 이름을 그때 안다)
#   ALB 5xx   → scripts/sync-alb-alarm.sh(ALB는 클러스터 안 컨트롤러가 만들어 Terraform이 모른다)
# 가 이 SNS 주제로 보낸다.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  function_name = "${var.name_prefix}-infra-alert"
  account_id    = data.aws_caller_identity.current.account_id
  partition     = data.aws_partition.current.partition
}

# ---------------------------------------------------------------------------
# 웹훅 주소 비밀 (JSON {"url": "https://discord.com/api/webhooks/..."})
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "webhook" {
  name                    = "${var.name_prefix}-error-webhook"
  description             = "Discord error channel webhook (url). infra-alert Lambda and ArgoCD notifications read it"
  recovery_window_in_days = var.secret_recovery_window_days
}

# ---------------------------------------------------------------------------
# SNS 주제. CloudWatch 경보, 비용 이상 감지, 켜고 끄기 워크플로(같은 계정 Role)가 보낸다
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "this" {
  name = local.function_name
}

data "aws_iam_policy_document" "topic" {
  # 같은 계정 IAM(관리자, 켜고 끄기 워크플로 Role)은 자기 IAM 권한대로 쓴다
  statement {
    sid       = "AccountOwner"
    actions   = ["sns:Publish", "sns:Subscribe", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:ListSubscriptionsByTopic", "sns:DeleteTopic"]
    resources = [aws_sns_topic.this.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchAlarms"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "CostAnomalyDetection"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this.arn]
    principals {
      type        = "Service"
      identifiers = ["costalerts.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "this" {
  arn    = aws_sns_topic.this.arn
  policy = data.aws_iam_policy_document.topic.json
}

# ---------------------------------------------------------------------------
# CloudWatch 경보 (늘 있는 리소스)
# 모두 missing = notBreaching: RDS가 꺼진 밤에는 지표가 없어 정상으로 본다(밤마다 경보가 울리지 않게).
# OK 알림은 ALARM → OK로 돌아올 때만 Lambda가 보낸다(처음 만들 때 INSUFFICIENT_DATA → OK는 보내지 않는다).
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  alarm_description   = "RDS CPU가 ${var.rds_cpu_percent}% 이상으로 15분 이어졌다. Grafana AWS 대시보드(README 4-23)에서 느린 쿼리·요청 급증을 본다"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.rds_instance_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.rds_cpu_percent
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.this.arn]
  ok_actions          = [aws_sns_topic.this.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.name_prefix}-rds-storage-low"
  alarm_description   = "RDS 남은 저장 공간이 ${var.rds_free_storage_gb}GiB 아래다. 로그·데모 데이터가 커졌는지 보고, 필요하면 modules/rds allocated_storage_gb를 늘린다"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.rds_instance_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = var.rds_free_storage_gb * 1024 * 1024 * 1024
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.this.arn]
  ok_actions          = [aws_sns_topic.this.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.name_prefix}-rds-connections-high"
  alarm_description   = "RDS 연결이 ${var.rds_connections}개 이상으로 10분 이어졌다(db.t4g.small 최대 약 170). 서비스 커넥션 풀·파드 수를 본다"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBInstanceIdentifier = var.rds_instance_identifier }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.rds_connections
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.this.arn]
  ok_actions          = [aws_sns_topic.this.arn]
}

# 켜고 끄기 Lambda(EventBridge → GitHub workflow_dispatch)가 실패하면 워크플로가 아예 돌지 않는다(토큰 만료 등).
# 워크플로 안에서 난 실패는 워크플로가 이 주제로 직접 보낸다(dev-cluster.yml '오류 채널 알림').
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(var.lambda_function_names)

  alarm_name          = "${each.value}-errors"
  alarm_description   = "Lambda ${each.value}가 실패했다. CloudWatch 로그 /aws/lambda/${each.value}에서 원인을 본다(GitHub 토큰 만료면 README 4-11로 다시 넣는다)"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.this.arn]
  ok_actions          = [aws_sns_topic.this.arn]
}

# ---------------------------------------------------------------------------
# 비용 이상 감지 (Cost Anomaly Detection, 무료). 계정 전체(dev·prod 같은 계정)라 한 환경에서만 켠다.
# 계정에 AWS 서비스 모니터가 이미 있으면 새로 만들 수 없다 → cost_anomaly_monitor_arn에 그 ARN을 넣는다.
# ---------------------------------------------------------------------------
resource "aws_ce_anomaly_monitor" "this" {
  count = var.cost_anomaly_enabled && var.cost_anomaly_monitor_arn == "" ? 1 : 0

  name              = "freshlink-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "this" {
  count = var.cost_anomaly_enabled ? 1 : 0

  name             = local.function_name
  frequency        = "IMMEDIATE" # IMMEDIATE는 SNS로만 보낼 수 있다
  monitor_arn_list = [var.cost_anomaly_monitor_arn != "" ? var.cost_anomaly_monitor_arn : aws_ce_anomaly_monitor.this[0].arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.this.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.cost_anomaly_usd)]
    }
  }

  depends_on = [aws_sns_topic_policy.this]
}

# ---------------------------------------------------------------------------
# Lambda (SNS 쪽지를 Discord 메시지로 바꿔 보낸다)
# ---------------------------------------------------------------------------
data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/lambda/infra_alert.py"
  output_path = "${path.module}/.build/infra_alert.zip"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "ReadWebhook"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.webhook.arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "infra-alert"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "this" {
  function_name    = local.function_name
  description      = "Post infra alarms, cost anomalies and workflow failures to Discord"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "infra_alert.handler"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  memory_size      = 128
  timeout          = 15

  environment {
    variables = {
      SECRET_ID = aws_secretsmanager_secret.webhook.name
      ENV_NAME  = var.env
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.this.name
  }
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSnsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.this.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.this.arn
}
