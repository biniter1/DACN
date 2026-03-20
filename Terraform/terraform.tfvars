# ──────────────────────────────────────────
# General
# ──────────────────────────────────────────
aws_region   = "ap-southeast-2"
name_project = "devsecops"
Environment  = "Development"

# ──────────────────────────────────────────
# VPC
# ──────────────────────────────────────────
cidr_vpc        = "172.16.0.0/16"
azs             = ["ap-southeast-2a", "ap-southeast-2b"]
public_subnets  = ["172.16.0.0/24", "172.16.2.0/24"]
private_subnets = ["172.16.1.0/24", "172.16.3.0/24"]
