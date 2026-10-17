output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API 서버 주소 (helm·kubernetes provider)"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "API 서버 CA (base64)"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS가 만든 클러스터 보안 그룹. 관리형 노드와 파드가 이 그룹을 쓴다(RDS 3306 허용 대상)"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IRSA OIDC 공급자 ARN"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_issuer" {
  description = "OIDC 발급자 주소 (https:// 포함)"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "node_group_name" {
  description = "노드 그룹 이름"
  value       = aws_eks_node_group.this.node_group_name
}
