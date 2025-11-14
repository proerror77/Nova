# ============================================================================
# ECR Repositories for Nova Services
# ============================================================================

resource "aws_ecr_repository" "nova_services" {
  for_each = toset(var.services)

  name                       = "${var.ecr_registry_alias}/${each.value}"
  image_tag_mutability       = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = "${var.ecr_registry_alias}/${each.value}"
    Service = each.value
  }
}

# ============================================================================
# ECR Repository Policies (allow pull from any source in account)
# ============================================================================

resource "aws_ecr_repository_policy" "nova_services" {
  for_each = aws_ecr_repository.nova_services

  repository = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ============================================================================
# ECR Lifecycle Policy (clean up old images)
# ============================================================================

resource "aws_ecr_lifecycle_policy" "nova_services" {
  for_each = aws_ecr_repository.nova_services

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images, remove untagged after 30 days"
        selection = {
          tagStatus       = "untagged"
          countType       = "sinceImagePushed"
          countUnit       = "days"
          countNumber     = 30
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 30 tagged images"
        selection = {
          tagStatus       = "tagged"
          tagPrefixList   = ["main", "develop", "staging", "prod"]
          countType       = "imageCountMoreThan"
          countNumber     = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ============================================================================
# Data source for current AWS account
# ============================================================================

data "aws_caller_identity" "current" {}

data "aws_ecr_authorization_token" "token" {}
