output "user_pool_id" {
  description = "User Pool ID (gateway issuer, member-service, frontend VITE_COGNITO_USER_POOL_ID)"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "User Pool ARN"
  value       = aws_cognito_user_pool.this.arn
}

output "user_pool_name" {
  description = "User Pool 이름"
  value       = aws_cognito_user_pool.this.name
}

output "app_client_id" {
  description = "브라우저용 앱 클라이언트 ID (gateway aud 확인, frontend VITE_COGNITO_CLIENT_ID). BFF 전환 뒤 지운다"
  value       = aws_cognito_user_pool_client.web.id
}

output "issuer_uri" {
  description = "JWT 발급자 주소 (gateway spring.security.oauth2.resourceserver.jwt.issuer-uri)"
  value       = "https://${aws_cognito_user_pool.this.endpoint}"
}

output "jwks_uri" {
  description = "공개 키 주소 (issuer_uri + /.well-known/jwks.json)"
  value       = "https://${aws_cognito_user_pool.this.endpoint}/.well-known/jwks.json"
}

output "groups" {
  description = "그룹 이름"
  value       = sort(keys(aws_cognito_user_group.this))
}

output "post_confirmation_function_name" {
  description = "가입 확인 Lambda 이름"
  value       = aws_lambda_function.post_confirmation.function_name
}

output "member_cognito_policy_arn" {
  description = "member-service IRSA Role에 붙일 Cognito 관리자 정책 ARN (클러스터 묶음, 할 일 7)"
  value       = aws_iam_policy.member_cognito.arn
}

output "seed_accounts_secret_name" {
  description = "시드 계정 자격 비밀 이름"
  value       = aws_secretsmanager_secret.seed_accounts.name
}

output "bff_client_id" {
  description = "gateway BFF용 앱 클라이언트 ID. 전환하는 날부터 토큰 aud가 이 값이다. 시크릿은 output에 내보내지 않는다"
  value       = aws_cognito_user_pool_client.bff.id
}

output "gateway_cognito_secret_name" {
  description = "bff 클라이언트 ID·시크릿 비밀 이름 (gitops gateway extraSecrets)"
  value       = aws_secretsmanager_secret.gateway_cognito.name
}

output "gateway_cognito_secret_arn" {
  description = "bff 클라이언트 비밀 ARN (클러스터 묶음 External Secrets 읽기 권한)"
  value       = aws_secretsmanager_secret.gateway_cognito.arn
}

output "domain_url" {
  description = "로그인 도메인 주소. 구글 로그인 /oauth2/authorize, /oauth2/token, /logout"
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

output "google_login_enabled" {
  description = "구글 IdP를 만들었는지"
  value       = length(aws_cognito_identity_provider.google) > 0
}
