# Staging Environment Configuration

environment = "staging"
aws_region  = "ap-northeast-1"

# EKS node group sizing for staging (3 x t3.xlarge)
node_desired_size = 3
node_min_size     = 2
node_max_size     = 5

# VPC Configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["ap-northeast-1a", "ap-northeast-1c"]

# Database Configuration
# NOTE: Staging 使用 K8s StatefulSet PostgreSQL，不使用 RDS
# db_instance_class = "db.t4g.micro"
# db_name           = "nova_staging"
# db_username       = "nova_admin"

# Redis Configuration
redis_node_type       = "cache.t4g.micro"
redis_num_cache_nodes = 1

# ECR Configuration
ecr_image_retention_count = 5

# High Availability
enable_multi_az = false
