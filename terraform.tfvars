aws_region         = "us-west-2"
vpc_cidr           = "10.0.0.0/16"
node_instance_type = "m5.large"
desired_node_count = 3
max_node_count     = 5
min_node_count     = 2
eks_cluster_name   = "verifaro-eks-cluster"
subnet_count       = 3
