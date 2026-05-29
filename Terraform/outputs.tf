output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_name" {
  description = "EKS Cluster name"
  value       = module.eks_cluster.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster API endpoint"
  value       = module.eks_cluster.cluster_endpoint
}

output "eks_cluster_ca" {
  description = "EKS Cluster certificate authority"
  value       = module.eks_cluster.cluster_ca
  sensitive   = true
}

output "github_actions_role_arn" {
  description = "IAM Role ARN cho GitHub Actions OIDC"
  value       = module.iam.github_actions_role_arn
}

output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}