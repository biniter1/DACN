output "alb_sg_id" {
  value       = aws_security_group.alb_sg.id
}

output "eks_node_sg_id" {
  value       = aws_security_group.eks_node_sg.id
}

output "database_sg_id" {
  value       = aws_security_group.database_sg.id
}

output "vpc_endpoint_sg_id" {
  value       = aws_security_group.vpc_endpoint_sg.id
}
