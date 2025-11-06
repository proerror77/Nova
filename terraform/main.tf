terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # NOTE: S3 backend temporarily disabled due to access restrictions
  # Backends can be configured via: terraform init -backend-config=path/to/backend.hcl
  #
  # For local development/planning:
  #   terraform plan -var-file=staging.tfvars
  #
  # For production deployment with S3 state:
  #   - Ensure S3 bucket exists in ca-central-1
  #   - Ensure IAM role has S3/DynamoDB permissions
  #   - Run: terraform init -backend-config=backend.hcl
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Nova"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
