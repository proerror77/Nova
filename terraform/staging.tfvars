# Staging Environment Configuration

environment = "staging"
aws_region  = "ap-northeast-1"

# VPC Configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["ap-northeast-1a", "ap-northeast-1c"]

# ECS Configuration
ecs_task_cpu    = 512
ecs_task_memory = 1024
ecs_task_count  = 2

# Database Configuration
db_instance_class = "db.t4g.medium"
db_name           = "nova_staging"
db_username       = "nova_admin"

# Redis Configuration
redis_node_type        = "cache.t4g.micro"
redis_num_cache_nodes  = 1

# ECR Configuration
ecr_image_retention_count = 10

# High Availability
enable_multi_az = false
