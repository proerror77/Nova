# Production Environment Configuration

environment = "production"
aws_region  = "us-east-1"

# VPC Configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# ECS Configuration
ecs_task_cpu    = 1024
ecs_task_memory = 2048
ecs_task_count  = 3

# Database Configuration
db_instance_class = "db.r6g.xlarge"
db_name           = "nova_production"
db_username       = "nova_admin"

# Redis Configuration
redis_node_type        = "cache.r6g.large"
redis_num_cache_nodes  = 3

# ECR Configuration
ecr_image_retention_count = 20

# High Availability
enable_multi_az = true
