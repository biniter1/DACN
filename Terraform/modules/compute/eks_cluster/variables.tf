variable "name_project" {
  type        = string
  description = "Name of the project"
}

variable "Environment" {
  type        = string
  description = "Environment"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.31"
}

variable "private_subnets" {
  type        = list(string)
  description = "Private subnet IDs for the EKS cluster"
}

variable "eks_cluster_role_arn" {
  type        = string
  description = "ARN of the EKS cluster IAM role"
}

variable "eks_node_sg_id" {
  type        = string
  description = "Security Group ID for EKS nodes"
}
