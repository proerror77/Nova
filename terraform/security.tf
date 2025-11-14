# ============================================
# IAM Roles
# ============================================

# GitHub Actions Role (for CI/CD)
resource "aws_iam_role" "github_actions" {
  name = "nova-${var.environment}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.account_id
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  name = "github-actions-permissions"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
    ]
  })
}

# ============================================
# Security Groups
# ============================================

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "nova-${var.environment}-alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nova-${var.environment}-alb"
  }
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "nova-${var.environment}-rds"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nova-${var.environment}-rds"
  }
}

# ElastiCache Security Group
resource "aws_security_group" "elasticache" {
  name        = "nova-${var.environment}-elasticache"
  description = "Security group for ElastiCache Redis"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "Redis from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nova-${var.environment}-elasticache"
  }
}

# ============================================
# Data Sources
# ============================================

data "aws_caller_identity" "current" {}
