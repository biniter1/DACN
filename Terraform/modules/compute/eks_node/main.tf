resource "aws_eks_node_group" "workers" {
  cluster_name    = var.eks_cluster_name
  node_group_name = "${var.eks_cluster_name}-workers"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnets
  instance_types  = var.instance_types

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  # Use latest EKS optimized AMI
  ami_type       = "AL2_x86_64"
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  tags = {
    Name        = "${var.eks_cluster_name}-workers"
    Environment = var.Environment
    ManagedBy   = "Terraform"
  }
}