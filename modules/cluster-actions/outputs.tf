output "role_arn" {
  description = "Role ARN. infra 레포 Actions 비밀 AWS_DEV_CLUSTER_ROLE_ARN에 넣는다"
  value       = aws_iam_role.this.arn
}
