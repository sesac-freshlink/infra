# DLQ 알림: DLQ에 쪽지가 1개라도 보이면 CloudWatch 경보 → SNS → Lambda → Discord 채널 웹훅.
# 웹훅 주소는 Terraform에 넣지 않는다. 빈 비밀(<접두사>-dlq-webhook)만 만들고 값은 scripts/set-dlq-webhook.ps1로 넣는다.
# 비밀에 값이 없으면 Lambda는 로그만 남기고 끝낸다(apply 직후 값을 넣기 전에도 에러가 나지 않게).

locals {
  function_name = "${var.name_prefix}-dlq-alert"
}

# ---------------------------------------------------------------------------
# 웹훅 주소 비밀 (JSON {"url": "https://discord.com/api/webhooks/..."})
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "webhook" {
  name                    = "${var.name_prefix}-dlq-webhook"
  description             = "Discord DLQ channel webhook (url)"
  recovery_window_in_days = var.secret_recovery_window_days
}

# ---------------------------------------------------------------------------
# 경보 → SNS 주제
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "this" {
  name = local.function_name
}

# SQS 지표는 1분마다 오지만 빈 큐는 지표가 끊길 수 있어 없는 값은 정상으로 본다.
# 쪽지가 남아 있는 동안은 경보가 한 번만 울리고, DLQ를 비우면(재처리·삭제) OK 알림이 한 번 더 간다.
resource "aws_cloudwatch_metric_alarm" "dlq" {
  for_each = toset(var.dlq_names)

  alarm_name          = "${each.value}-not-empty"
  alarm_description   = "DLQ ${each.value}에 처리 못 한 쪽지가 있다. infra README 4-16으로 원인을 보고 재처리한다"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = each.value }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.this.arn]
  ok_actions          = [aws_sns_topic.this.arn]
}

# ---------------------------------------------------------------------------
# Lambda (SNS 쪽지를 Discord 메시지로 바꿔 보낸다)
# ---------------------------------------------------------------------------
data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/lambda/dlq_alert.py"
  output_path = "${path.module}/.build/dlq_alert.zip"
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
  name   = "dlq-alert"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "this" {
  function_name    = local.function_name
  description      = "Post DLQ alarms to Discord"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "dlq_alert.handler"
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
