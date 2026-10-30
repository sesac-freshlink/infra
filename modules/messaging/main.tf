# 큐 세트 하나 = inventory-commands.fifo(+DLQ) + inventory-results(+DLQ) + notification-events(+DLQ, 10/30 화면 알림).
# 공용 세트는 접두사 '<env>-', 개발자별 세트는 '<env>-<아이디>-'. 서비스는 QUEUE_PREFIX만 바꿔 같은 코드로 쓴다.

locals {
  prefixes = merge(
    { shared = "${var.env}-" },
    { for d in var.developers : d => "${var.env}-${d}-" },
  )
}

# ---------------------------------------------------------------------------
# inventory-commands (FIFO, 메시지 그룹 = storeId). 중복 제거 ID는 보내는 쪽(Outbox 발행기)이 messageId로 넣는다.
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "commands_dlq" {
  for_each = local.prefixes

  name                      = "${each.value}inventory-commands-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = var.dlq_retention_seconds
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "commands" {
  for_each = local.prefixes

  name                        = "${each.value}inventory-commands.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  visibility_timeout_seconds  = var.visibility_timeout_seconds
  message_retention_seconds   = var.message_retention_seconds
  receive_wait_time_seconds   = 20 # 롱 폴링: 빈 응답 요청 수를 줄인다
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.commands_dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "commands_dlq" {
  for_each = local.prefixes

  queue_url = aws_sqs_queue.commands_dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.commands[each.key].arn]
  })
}

# ---------------------------------------------------------------------------
# inventory-results (표준)
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "results_dlq" {
  for_each = local.prefixes

  name                      = "${each.value}inventory-results-dlq"
  message_retention_seconds = var.dlq_retention_seconds
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "results" {
  for_each = local.prefixes

  name                       = "${each.value}inventory-results"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.results_dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "results_dlq" {
  for_each = local.prefixes

  queue_url = aws_sqs_queue.results_dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.results[each.key].arn]
  })
}

# ---------------------------------------------------------------------------
# notification-events (표준, 10/30 화면 알림). inventory(·order)가 NOTIFICATION을 보내고 notification-service가 받는다.
# 알림은 순서가 상관없고 받는 쪽이 messageId로 중복을 거르므로 FIFO가 아니어도 된다.
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "notifications_dlq" {
  for_each = local.prefixes

  name                      = "${each.value}notification-events-dlq"
  message_retention_seconds = var.dlq_retention_seconds
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "notifications" {
  for_each = local.prefixes

  name                       = "${each.value}notification-events"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "notifications_dlq" {
  for_each = local.prefixes

  queue_url = aws_sqs_queue.notifications_dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.notifications[each.key].arn]
  })
}
