output "queue_prefixes" {
  description = "세트 이름(shared 또는 개발자 아이디) → QUEUE_PREFIX 값"
  value       = local.prefixes
}

output "queues" {
  description = "세트 이름 → 큐 이름 4개"
  value = {
    for k in keys(local.prefixes) : k => {
      commands     = aws_sqs_queue.commands[k].name
      commands_dlq = aws_sqs_queue.commands_dlq[k].name
      results      = aws_sqs_queue.results[k].name
      results_dlq  = aws_sqs_queue.results_dlq[k].name
    }
  }
}

output "queue_arns" {
  description = "세트 이름 → 큐 ARN 4개 (IRSA 권한에 쓴다)"
  value = {
    for k in keys(local.prefixes) : k => [
      aws_sqs_queue.commands[k].arn,
      aws_sqs_queue.commands_dlq[k].arn,
      aws_sqs_queue.results[k].arn,
      aws_sqs_queue.results_dlq[k].arn,
    ]
  }
}
