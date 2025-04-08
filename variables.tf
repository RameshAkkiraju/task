variable "aws_region" {
  description = "The AWS region to deploy resources into"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_type" {
  description = "EC2 instance type for the worker nodes"
  type        = string
  default     = "m5.large"
}

variable "desired_node_count" {
  description = "The desired number of nodes in the EKS node group"
  type        = number
  default     = 3
}

variable "max_node_count" {
  description = "The maximum number of nodes in the EKS node group"
  type        = number
  default     = 5
}

variable "min_node_count" {
  description = "The minimum number of nodes in the EKS node group"
  type        = number
  default     = 2
}

variable "subnet_count" {
  description = "The number of subnets to create for high availability"
  type        = number
  default     = 3
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default     = "verifaro-eks-cluster"
}

variable "eks_node_role_name" {
  description = "IAM role name for the EKS nodes"
  type        = string
  default     = "eks-node-role"
}

variable "eks_cluster_role_name" {
  description = "IAM role name for the EKS cluster"
  type        = string
  default     = "eks-cluster-role"
}
