# 켜고 끄기 워크플로를 정해진 시각에 실행한다: EventBridge Scheduler → Lambda → GitHub workflow_dispatch API.
# GitHub 예약(schedule)은 몇 시간 늦거나 빠지기도 한다(2026-10-20 화 09:00 NAT 생성이 빠지고, 전날 21:10 NAT 삭제가 03:41에 돎).
# 시각만 EventBridge가 지키고 Terraform은 그대로 GitHub Actions에서 돈다(클러스터 생성 15~20분이라 Lambda로는 못 한다).
# GitHub 토큰 값은 Terraform에 넣지 않는다(state에 남지 않게). README 4-11 명령으로 김진아가 넣는다.

data "aws_caller_identity" "current" {}

locals {
  function_name = "${var.name_prefix}-workflow-dispatch"
}

# ---------------------------------------------------------------------------
# GitHub 토큰 (fine-grained, infra 저장소 Actions 읽기·쓰기만)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "token" {
  name                    = "${local.function_name}-token"
  description             = "GitHub fine-grained token: ${var.repo} Actions read/write only (workflow_dispatch)"
  recovery_window_in_days = 0
}

# ---------------------------------------------------------------------------
# Lambda
# ---------------------------------------------------------------------------
data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/lambda/dispatch.py"
  output_path = "${path.module}/.build/dispatch.zip"
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
    sid       = "ReadToken"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.token.arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "workflow-dispatch"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "this" {
  function_name    = local.function_name
  description      = "Run ${var.repo} ${var.workflow} on schedule (workflow_dispatch)"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "dispatch.handler"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      REPO      = var.repo
      WORKFLOW  = var.workflow
      REF       = var.ref
      SECRET_ID = aws_secretsmanager_secret.token.arn
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.this.name
  }
}

# ---------------------------------------------------------------------------
# 일정 (EventBridge Scheduler, 한국 시각)
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
    sid       = "InvokeDispatch"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.this.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "invoke-workflow-dispatch"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

resource "aws_scheduler_schedule_group" "this" {
  name = local.function_name
}

resource "aws_scheduler_schedule" "this" {
  for_each = var.schedules

  name        = "${local.function_name}-${each.key}"
  group_name  = aws_scheduler_schedule_group.this.name
  description = "${var.workflow} action ${each.value.action}"
  state       = var.enabled ? "ENABLED" : "DISABLED"

  schedule_expression          = each.value.cron
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.this.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = each.value.action })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 900
    }
  }
}
