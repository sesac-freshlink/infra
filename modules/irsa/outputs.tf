output "role_arns" {
  description = "Role 키 → IRSA Role ARN (gitops ServiceAccount annotation)"
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}
