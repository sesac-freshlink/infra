locals {
  months = sort(keys(var.monthly_limits))

  # AWS는 planned_limit을 첫 달부터 12개월치 요구한다. 첫 달부터 12개월을 만들고,
  # monthly_limits에 없는 달은 마지막 달 금액으로 채운다(프로젝트가 끝난 뒤 달도 알림은 계속 온다).
  start_year     = tonumber(substr(local.months[0], 0, 4))
  start_month    = tonumber(substr(local.months[0], 5, 2))
  planned_months = [for i in range(12) : format("%04d-%02d", local.start_year + floor((local.start_month - 1 + i) / 12), (local.start_month - 1 + i) % 12 + 1)]
  last_limit     = var.monthly_limits[local.months[length(local.months) - 1]]
  planned_limits = { for m in local.planned_months : m => lookup(var.monthly_limits, m, local.last_limit) }
}

# 계정 전체 월 예산. 월마다 금액이 달라서 planned_limit으로 나눈다.
resource "aws_budgets_budget" "monthly" {
  name              = "${var.name_prefix}-monthly"
  budget_type       = "COST"
  time_unit         = "MONTHLY"
  time_period_start = "${local.months[0]}-01_00:00"

  dynamic "planned_limit" {
    for_each = local.planned_limits
    content {
      start_time = "${planned_limit.key}-01_00:00"
      amount     = tostring(planned_limit.value)
      unit       = "USD"
    }
  }

  # 지원금이 크레딧으로 들어오면 크레딧 차감 뒤 금액은 0에 가까워 알림이 오지 않는다.
  # 크레딧·환불을 빼고 실제 사용 금액으로 본다.
  cost_types {
    include_credit = false
    include_refund = false
  }

  dynamic "notification" {
    for_each = var.actual_thresholds
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.alert_emails
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_emails
  }
}

# 알림 시험용. 이번 달 실제 비용이 0.01 USD를 넘으면 메일이 간다(평가는 하루 몇 번이라 수 시간 걸릴 수 있다).
resource "aws_budgets_budget" "test" {
  count = var.create_test_budget ? 1 : 0

  name         = "${var.name_prefix}-alert-test"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = "1"
  limit_unit   = "USD"

  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 1
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_emails
  }
}

# 비용 이상 탐지: 서비스별로 평소와 다른 지출을 잡는다.
resource "aws_ce_anomaly_monitor" "services" {
  name              = "${var.name_prefix}-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "email" {
  name             = "${var.name_prefix}-anomaly-email"
  frequency        = "DAILY" # 메일 구독은 DAILY·WEEKLY만 된다
  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]

  dynamic "subscriber" {
    for_each = var.alert_emails
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }
}
