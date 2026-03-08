# ──────────────────────────────────────────
# 1. Security Group shells (name + VPC only)
# ──────────────────────────────────────────
resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id
  tags        = { Name = "alb_sg", ManagedBy = "Terraform" }
}

resource "aws_security_group" "eks_node_sg" {
  name        = "eks_node_sg"
  description = "Security group for EKS Worker Nodes"
  vpc_id      = var.vpc_id
  tags        = { Name = "eks_node_sg", ManagedBy = "Terraform" }
}

resource "aws_security_group" "database_sg" {
  name        = "database_sg"
  description = "Security group for databases (RDS/ElastiCache)"
  vpc_id      = var.vpc_id
  tags        = { Name = "database_sg", ManagedBy = "Terraform" }
}

resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "vpc_endpoint_sg"
  description = "Security group for VPC Endpoints"
  vpc_id      = var.vpc_id
  tags        = { Name = "vpc_endpoint_sg", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────
# 2. ALB Rules
# ──────────────────────────────────────────

# Allow HTTP + HTTPS from internet
resource "aws_security_group_rule" "alb_allow_http_https" {
  for_each = {
    http  = 80
    https = 443
  }

  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_sg.id
}

# ALB egress → EKS Nodes (NodePort range)
resource "aws_security_group_rule" "alb_egress_to_nodes" {
  type                     = "egress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node_sg.id
  description              = "ALB to EKS NodePort range"
  security_group_id        = aws_security_group.alb_sg.id
}

# ──────────────────────────────────────────
# 3. EKS Node Rules
# ──────────────────────────────────────────

# Ingress from ALB (NodePort)
resource "aws_security_group_rule" "nodes_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  description              = "Allow NodePort traffic from ALB"
  security_group_id        = aws_security_group.eks_node_sg.id
}

# Node-to-node communication (all protocols)
resource "aws_security_group_rule" "nodes_internal_tcp" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  self              = true
  description       = "Allow all TCP between nodes"
  security_group_id = aws_security_group.eks_node_sg.id
}

resource "aws_security_group_rule" "nodes_internal_udp" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "udp"
  self              = true
  description       = "Allow all UDP between nodes (e.g. CoreDNS)"
  security_group_id = aws_security_group.eks_node_sg.id
}

# Egress → Database (Redis 6379, Postgres 5432)
resource "aws_security_group_rule" "nodes_egress_redis" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.database_sg.id
  description              = "Nodes to Redis"
  security_group_id        = aws_security_group.eks_node_sg.id
}

resource "aws_security_group_rule" "nodes_egress_postgres" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.database_sg.id
  description              = "Nodes to PostgreSQL"
  security_group_id        = aws_security_group.eks_node_sg.id
}

# Egress → internet (HTTPS only, for ECR/S3 pull via NAT)
resource "aws_security_group_rule" "nodes_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Nodes HTTPS egress (ECR, S3, AWS APIs)"
  security_group_id = aws_security_group.eks_node_sg.id
}

# ──────────────────────────────────────────
# 4. Database Rules
# ──────────────────────────────────────────

resource "aws_security_group_rule" "db_ingress_redis_from_nodes" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node_sg.id
  description              = "Redis ingress from EKS nodes"
  security_group_id        = aws_security_group.database_sg.id
}

resource "aws_security_group_rule" "db_ingress_postgres_from_nodes" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node_sg.id
  description              = "PostgreSQL ingress from EKS nodes"
  security_group_id        = aws_security_group.database_sg.id
}

# ──────────────────────────────────────────
# 5. VPC Endpoint Rules
# ──────────────────────────────────────────

resource "aws_security_group_rule" "vpce_ingress_from_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node_sg.id
  description              = "HTTPS from EKS nodes to VPC Endpoints"
  security_group_id        = aws_security_group.vpc_endpoint_sg.id
}
