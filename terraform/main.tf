terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 本地后端（临时用于本地部署/测试）
  backend "local" {}
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
