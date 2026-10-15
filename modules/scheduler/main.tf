# EventBridge Scheduler: Lambda 없이 AWS API를 바로 부른다(universal target).
# RDS와 SSM 접속용 인스턴스를 같은 시각에 켜고 끈다. 노드 그룹 일정은 할 일 9에서 더한다.
# 이미 꺼진 것을 끄거나 켜진 것을 켜면 API가 오류를 내지만 상태는 원하는 대로라 문제없다(재시도는 1번만).

data "aws_caller_identity" "current" {}

locals {
  rds_input = jsonencode({ DbInstanceIdentifier = var.rds_instance_identifier })
  ec2_input = jsonencode({ InstanceIds = var.ec2_instance_ids })

  schedules = {
    rds-start              = { cron = var.start_cron, target = "rds:startDBInstance", input = local.rds_input, desc = "RDS 켜기" }
    rds-stop               = { cron = var.stop_cron, target = "rds:stopDBInstance", input = local.rds_input, desc = "RDS 끄기" }
    rds-safety-stop        = { cron = var.safety_stop_cron, target = "rds:stopDBInstance", input = local.rds_input, desc = "RDS 안전 끄기" }
    ssm-access-start       = { cron = var.start_cron, target = "ec2:startInstances", input = local.ec2_input, desc = "SSM 접속용 인스턴스 켜기" }
    ssm-access-stop        = { cron = var.stop_cron, target = "ec2:stopInstances", input = local.ec2_input, desc = "SSM 접속용 인스턴스 끄기" }
    ssm-access-safety-stop = { cron = var.safety_stop_cron, target = "ec2:stopInstances", input = local.ec2_input, desc = "SSM 접속용 인스턴스 안전 끄기" }
  }
}

resource "aws_scheduler_schedule_group" "this" {
  name = var.name_prefix
}

data "aws_iam_policy_document" "assume" {
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

resource "aws_iam_role" "this" {
  name               = "${var.name_prefix}-scheduler-role"
  description        = "EventBridge Scheduler: start/stop ${var.rds_instance_identifier} and SSM access instance only"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "StartStopRds"
    actions   = ["rds:StartDBInstance", "rds:StopDBInstance"]
    resources = [var.rds_instance_arn]
  }

  statement {
    sid       = "StartStopSsmAccessInstance"
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = var.ec2_instance_arns
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "start-stop"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_scheduler_schedule" "this" {
  for_each = local.schedules

  name        = "${var.name_prefix}-${each.key}"
  group_name  = aws_scheduler_schedule_group.this.name
  description = each.value.desc
  state       = var.enabled ? "ENABLED" : "DISABLED"

  schedule_expression          = each.value.cron
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:${each.value.target}"
    role_arn = aws_iam_role.this.arn
    input    = each.value.input

    retry_policy {
      maximum_retry_attempts       = 1
      maximum_event_age_in_seconds = 300
    }
  }
}
