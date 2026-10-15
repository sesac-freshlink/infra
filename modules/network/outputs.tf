output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC 대역"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "public 서브넷 ID [a, c]"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "app 서브넷 ID [a, c] (EKS 노드)"
  value       = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  description = "db 서브넷 ID [a, c] (RDS 서브넷 그룹)"
  value       = aws_subnet.db[*].id
}

output "public_route_table_id" {
  description = "public 라우팅 테이블 ID"
  value       = aws_route_table.public.id
}

output "app_route_table_id" {
  description = "app 라우팅 테이블 ID. cluster 묶음이 NAT 경로를 넣는다"
  value       = aws_route_table.app.id
}
