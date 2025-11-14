terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 本地后端配置 (用于 staging 环境)
  # 注意: 在生产环境中应使用 S3 远程后端
  backend "local" {
    path = "terraform.tfstate"
  }
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
