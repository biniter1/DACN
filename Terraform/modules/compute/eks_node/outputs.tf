output "node_group_name" {
  description = "EKS Node Group name"
  value       = aws_eks_node_group.workers.node_group_name
}

output "node_group_status" {
  description = "EKS Node Group status"
  value       = aws_eks_node_group.workers.status
}
