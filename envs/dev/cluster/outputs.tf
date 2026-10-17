output "cluster_name" {
  description = "EKS 클러스터 이름 (aws eks update-kubeconfig --name)"
  value       = module.eks.cluster_name
}

output "irsa_role_arns" {
  description = "IRSA Role ARN. 서비스 4개는 gitops envs/dev/<서비스>/values.yaml ServiceAccount annotation에 넣는다"
  value       = module.irsa.role_arns
}

output "nat_enabled" {
  description = "지금 NAT Gateway가 있는지"
  value       = var.nat_enabled
}

output "storage_class" {
  description = "기본 StorageClass 이름 (gitops 관측성 PVC)"
  value       = kubernetes_storage_class_v1.gp3.metadata[0].name
}
