output "cluster_name" {
  description = "EKS Cluster name"
  value       = aws_eks_cluster.cluster.name
}

output "cluster_endpoint" {
  description = "EKS Cluster API server endpoint"
  value       = aws_eks_cluster.cluster.endpoint
}

output "cluster_ca" {
  description = "EKS Cluster certificate authority data"
  value       = aws_eks_cluster.cluster.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "EKS Cluster Kubernetes version"
  value       = aws_eks_cluster.cluster.version
}
