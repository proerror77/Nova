# ECR Repositories for all microservices
resource "aws_ecr_repository" "services" {
  for_each = toset(var.services)

  name                 = "nova-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Service = each.key
  }
}

# Lifecycle policy to keep only recent images
resource "aws_ecr_lifecycle_policy" "services" {
  for_each = toset(var.services)

  repository = "nova-${each.key}"

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_image_retention_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR Repository Policy - Allow EKS nodes and GitHub Actions to push/pull images
resource "aws_ecr_repository_policy" "services" {
  for_each = toset(var.services)

  repository = "nova-${each.key}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.eks_node_group.arn,
            aws_iam_role.github_actions.arn
          ]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}
