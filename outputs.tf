
output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.name
}

output "vpc_id" {
  description = "The VPC ID"
  value       = aws_vpc.eks_vpc.id
}

output "subnet_ids" {
  description = "The IDs of the subnets created"
  value       = aws_subnet.eks_subnet[*].id
}
