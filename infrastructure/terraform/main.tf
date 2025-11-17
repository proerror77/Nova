terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # Temporary local backend to bypass STS connectivity issue during init
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "nova"
      Environment = var.environment
      CreatedBy   = "terraform"
      ManagedBy   = "terraform"
    }
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Data sources for provider configuration
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# ============================================================================
# VPC 网络
# ============================================================================
module "vpc" {
  source = "./modules/vpc"

  environment = var.environment
  cidr_block  = var.vpc_cidr

  availability_zones = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  enable_nat_gateway = true
  enable_dns_support = true
}

# ============================================================================
# IAM 角色和策略
# ============================================================================
module "iam" {
  source = "./modules/iam"

  environment   = var.environment
  cluster_name  = var.cluster_name

  github_oidc_provider_arn = var.github_oidc_provider_arn
  github_repo_owner        = var.github_repo_owner
  github_repo_name         = var.github_repo_name
}

# ============================================================================
# ECR 仓库
# ============================================================================
module "ecr" {
  source = "./modules/ecr"

  environment = var.environment

  services = [
    "auth-service",
    "content-service",
    "feed-service",
    "media-service",
    "messaging-service",
    "search-service",
  ]

  ecr_registry_alias = var.ecr_registry_alias
}

# ============================================================================
# EKS 集群
# ============================================================================
module "eks" {
  source = "./modules/eks"

  environment  = var.environment
  cluster_name = var.cluster_name

  vpc_id            = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  cluster_version = var.kubernetes_version

  # Node group configuration
  node_group_name       = "${var.cluster_name}-node-group"
  node_group_min_size   = var.node_group_min_size
  node_group_max_size   = var.node_group_max_size
  node_group_desired_size = var.node_group_desired_size
  node_instance_types   = var.node_instance_types

  # IAM roles
  cluster_role_arn = module.iam.eks_cluster_role_arn
  node_role_arn    = module.iam.eks_node_role_arn

  # Enable control plane logging
  enable_cluster_autoscaler = true
  enable_metrics_server     = true
}

# ============================================================================
# EKS Add-ons（OIDC、VPC CNI 等）
# ============================================================================
module "addons" {
  source = "./modules/addons"

  cluster_name           = module.eks.cluster_name
  cluster_oidc_issuer_url = module.eks.oidc_provider_url

  environment = var.environment

  # IRSA (IAM Roles for Service Accounts) 配置
  ecr_access_role_arn       = module.iam.ecr_access_role_arn
  alb_controller_role_arn   = module.iam.alb_controller_role_arn
  external_dns_role_arn     = module.iam.external_dns_role_arn
  cert_manager_role_arn     = module.iam.cert_manager_role_arn
  ebs_csi_role_arn         = module.iam.ebs_csi_role_arn

  # 版本配置
  coredns_version           = "v1.10.1-eksbuild.2"
  kube_proxy_version        = "v1.28.1-eksbuild.1"
  vpc_cni_version           = "v1.14.1-eksbuild.1"
  ebs_csi_driver_version    = "v1.24.0-eksbuild.1"

  depends_on = [module.eks]
}

# ============================================================================
# 输出
# ============================================================================
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = data.aws_eks_cluster.cluster.endpoint
}

output "eks_cluster_version" {
  description = "EKS cluster version"
  value       = module.eks.cluster_version
}

output "ecr_registry_url" {
  description = "ECR registry URL"
  value       = module.ecr.registry_url
}

output "ecr_repositories" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}

output "kubeconfig_update_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
