output "function_name" {
  description = "비용 메일 Lambda 이름 (aws lambda invoke로 지금 한 번 보내 볼 때 쓴다)"
  value       = aws_lambda_function.this.function_name
}

output "topic_arn" {
  description = "비용 메일 SNS 주제 ARN"
  value       = aws_sns_topic.this.arn
}
