terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.35.1"
    }
  }

  backend "s3" {
    bucket         = "company-terraform-state-demo-project"
    key            = "prod/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "terraform-lock-demo-project"
  }
}

provider "aws" {
  region = var.aws_region
}

# ──────────────────────────────────────────
# VPC
# ──────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  name_project    = var.name_project
  Environment     = var.Environment
  cidr_vpc        = var.cidr_vpc
  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

# ──────────────────────────────────────────
# IAM Roles & Policies
# ──────────────────────────────────────────
module "iam" {
  source = "./modules/iam"
  name_project = var.name_project

}

# ──────────────────────────────────────────
# Security Groups
# ──────────────────────────────────────────
module "security_group" {
  source = "./modules/security"
  vpc_id = module.vpc.vpc_id
}

# ──────────────────────────────────────────
# EKS Cluster (Control Plane)
# ──────────────────────────────────────────
module "eks_cluster" {
  source = "./modules/compute/eks_cluster"

  name_project        = var.name_project
  Environment         = var.Environment
  private_subnets     = module.vpc.private_subnet_ids
  eks_cluster_role_arn = module.iam.eks_cluster_role_arn
  eks_node_sg_id      = module.security_group.eks_node_sg_id
}

# ──────────────────────────────────────────
# EKS Node Group (Worker Nodes)
# ──────────────────────────────────────────
module "eks_node" {
  source = "./modules/compute/eks_node"

  Environment        = var.Environment
  private_subnets    = module.vpc.private_subnet_ids
  eks_cluster_name   = module.eks_cluster.cluster_name
  eks_node_role_arn  = module.iam.eks_node_role_arn
  eks_node_role_name = module.iam.eks_node_role_name

  depends_on = [module.eks_cluster]
}
