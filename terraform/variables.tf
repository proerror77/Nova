variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-northeast-1"
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
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
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
