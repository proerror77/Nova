variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
  default     = "staging"
}

variable "services" {
  description = "List of microservices to deploy"
  type        = list(string)
  default = [
    "auth-service",
    "user-service",
    "content-service",
    "feed-service",
    "media-service",
    "messaging-service",
    "search-service",
    "streaming-service",
    "notification-service",
    "cdn-service",
    "events-service"
  ]
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "ecs_task_cpu" {
  description = "Fargate task CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Fargate task memory in MB (512, 1024, 2048, 4096, 8192)"
  type        = number
  default     = 1024
}

variable "ecs_task_count" {
  description = "Number of ECS tasks to run per service"
  type        = number
  default     = 2
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t4g.medium"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "nova"
}

variable "db_username" {
  description = "PostgreSQL database username"
  type        = string
  default     = "nova_admin"
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_num_cache_nodes" {
  description = "Number of Redis cache nodes"
  type        = number
  default     = 3
}

variable "ecr_image_retention_count" {
  description = "Number of ECR images to retain"
  type        = number
  default     = 10
}

variable "enable_multi_az" {
  description = "Enable multi-AZ for RDS and ElastiCache"
  type        = bool
  default     = false
}
