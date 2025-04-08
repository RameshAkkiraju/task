provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Create a VPC with CIDR from variables
resource "aws_vpc" "eks_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "eks-vpc"
  }
}

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Create subnets across multiple Availability Zones for high availability (3 AZs)
resource "aws_subnet" "eks_subnet" {
  count = 3  # Adjust based on number of AZs you want to span
  vpc_id     = aws_vpc.eks_vpc.id
  cidr_block = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "eks-subnet-${count.index}"
  }
}

# Create an Internet Gateway for the VPC
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id
}

# Route Table and Associations
resource "aws_route_table" "eks_route_table" {
  vpc_id = aws_vpc.eks_vpc.id
}

resource "aws_route_table_association" "eks_route_association" {
  count          = 3  # Adjust based on the number of subnets
  subnet_id      = aws_subnet.eks_subnet[count.index].id
  route_table_id = aws_route_table.eks_route_table.id
}

# Create IAM roles for EKS Cluster and Node Groups
resource "aws_iam_role" "eks_cluster_role" {
  name = var.eks_cluster_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Effect   = "Allow"
        Sid      = ""
      }
    ]
  })
}

# Attach the necessary policies to the EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy_attach" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Create the EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  vpc_config {
    subnet_ids = aws_subnet.eks_subnet[*].id
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}

# Create IAM Role for Worker Nodes
resource "aws_iam_role" "eks_node_role" {
  name = var.eks_node_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect   = "Allow"
        Sid      = ""
      }
    ]
  })
}

# Attach necessary policies to the EKS Node Role
resource "aws_iam_role_policy_attachment" "eks_node_policy_attach" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_policy_attach" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}

# Configure the EKS Node Group (set instance types, desired size, etc.)
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "eks-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn  
  subnet_ids      = aws_subnet.eks_subnet[*].id
  scaling_config {
    desired_size = var.desired_node_count
    max_size     = var.max_node_count
    min_size     = var.min_node_count
  }
  instance_types = ["m5.2xlarge"]  # Adjust to instances with enough memory (e.g., 32GB memory per node)
}

# Enable CloudWatch logging for the EKS cluster
resource "aws_cloudwatch_log_group" "eks_log_group" {
  name = "/aws/eks/${aws_eks_cluster.eks_cluster.name}/cluster"
}

# Create CloudWatch Log Streams for each enabled log type in the cluster
resource "aws_cloudwatch_log_stream" "eks_log_stream" {
  count          = length(aws_eks_cluster.eks_cluster.enabled_cluster_log_types)
  name           = "${aws_eks_cluster.eks_cluster.name}-${aws_eks_cluster.eks_cluster.enabled_cluster_log_types[count.index]}"
  log_group_name = aws_cloudwatch_log_group.eks_log_group.name
}

# Create an IAM policy for read access to the incoming orders S3 bucket
resource "aws_iam_policy" "order_processor_policy" {
  name        = "order-processor-s3-access-policy"
  description = "Policy granting read access to the incomingorders S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "s3:ListBucket"
        Effect   = "Allow"
        Resource = "arn:aws:s3:::incomingorders"
      },
      {
        Action   = "s3:GetObject"
        Effect   = "Allow"
        Resource = "arn:aws:s3:::incomingorders/*"
      }
    ]
  })
}

# Create an IAM role for the Kubernetes service account
resource "aws_iam_role" "order_processor_role" {
  name = "order-processor-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/id/${aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer}"
        }
        Effect   = "Allow"
        Sid      = ""
      }
    ]
  })
}

# Attach the order processor policy to the IAM role
resource "aws_iam_role_policy_attachment" "order_processor_policy_attach" {
  role       = aws_iam_role.order_processor_role.name
  policy_arn = aws_iam_policy.order_processor_policy.arn
}

# Create a Kubernetes service account for the order processor
resource "kubernetes_service_account" "order_processor_service_account" {
  metadata {
    name      = "order-processor"
    namespace = "default"  
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.order_processor_role.arn
    }
  }
}

# Create an IAM policy for view-only access to the ops namespace
resource "aws_iam_policy" "ops_view_policy" {
  name        = "ops-view-policy"
  description = "Policy granting view-only access to everything in the ops namespace"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:ListUpdates",
          "eks:DescribeNodegroup",
          "eks:DescribeUpdate"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = [
          "eks:ListNamespaces",
          "eks:DescribeNamespace"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:namespace/ops"
      }
    ]
  })
}

# Create an IAM Role for OpsUser (ops-alice)
resource "aws_iam_role" "ops_user_role" {
  name = "ops-user-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          AWS = "arn:aws:iam::1234566789001:user/ops-alice"
        }
        Effect   = "Allow"
        Sid      = ""
      }
    ]
  })
}

# Attach the ops view policy to the IAM role
resource "aws_iam_role_policy_attachment" "ops_view_policy_attach" {
  role       = aws_iam_role.ops_user_role.name
  policy_arn = aws_iam_policy.ops_view_policy.arn
}

# Create a Kubernetes RoleBinding to bind the OpsUser IAM role to the ops namespace
resource "kubernetes_role_binding" "ops_user_role_binding" {
  metadata {
    name      = "ops-user-role-binding"
    namespace = "ops"  # The Kubernetes namespace for which the view permissions are given
  }

  role_ref {
    kind     = "Role"
    name     = "view"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "User"
    name      = "arn:aws:iam::1234566789001:user/ops-alice"
    api_group = "rbac.authorization.k8s.io"
  }
}
