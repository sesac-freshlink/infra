# 매일 아침 비용 메일: EventBridge Scheduler가 Lambda를 부르고, Lambda가 Cost Explorer에서
# 어제 비용·이번 달 누계·프로젝트 총 비용을 읽어 SNS 주제로 보낸다. 받는 사람은 SNS 이메일 구독이다.
# 구독은 받는 사람이 확인 메일의 "Confirm subscription"을 한 번 눌러야 시작된다.

data "aws_caller_identity" "current" {}

locals {
  function_name = "${var.name_prefix}-cost-report"
  months        = sort(keys(var.monthly_limits))
  project_start = "${local.months[0]}-01"
}

# ---------------------------------------------------------------------------
# 받는 사람 (SNS 이메일 구독)
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "this" {
  name         = local.function_name
  display_name = "FreshLink Cost"
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.emails)

  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------------------------------------------------------------------------
# Lambda
# ---------------------------------------------------------------------------
data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/lambda/cost_report.py"
  output_path = "${path.module}/.build/cost_report.zip"
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
  # Cost Explorer 읽기는 리소스로 좁힐 수 없다
  statement {
    sid       = "ReadCost"
    actions   = ["ce:GetCostAndUsage"]
    resources = ["*"]
  }

  statement {
    sid       = "PublishReport"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this.arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "cost-report"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "this" {
  function_name    = local.function_name
  description      = "Daily cost mail: yesterday, month-to-date, total since ${local.project_start}"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "cost_report.handler"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      TOPIC_ARN      = aws_sns_topic.this.arn
      PROJECT_START  = local.project_start
      MONTHLY_LIMITS = jsonencode(var.monthly_limits)
      TOTAL_BUDGET   = tostring(var.total_budget_usd)
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.this.name
  }
}

# ---------------------------------------------------------------------------
# 매일 아침 실행 (EventBridge Scheduler)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.function_name}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "InvokeCostReport"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.this.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "invoke-cost-report"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

resource "aws_scheduler_schedule" "this" {
  name                         = local.function_name
  description                  = "매일 아침 비용 메일"
  schedule_expression          = var.schedule_cron
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.this.arn
    role_arn = aws_iam_role.scheduler.arn

    retry_policy {
      maximum_retry_attempts = 1
    }
  }
}
