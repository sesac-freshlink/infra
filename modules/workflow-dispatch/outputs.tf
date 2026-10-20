output "function_name" {
  description = "실행 요청 Lambda 이름 (aws lambda invoke로 지금 한 번 시험할 때 쓴다)"
  value       = aws_lambda_function.this.function_name
}

output "token_secret_name" {
  description = "GitHub 토큰을 넣을 Secrets Manager 비밀 이름 (값은 README 명령으로 넣는다)"
  value       = aws_secretsmanager_secret.token.name
}
