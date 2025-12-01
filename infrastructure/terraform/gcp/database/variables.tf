variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

# Cloud SQL Variables
variable "database_instance_name" {
  description = "Cloud SQL instance name prefix"
  type        = string
  default     = "nova"
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "nova"
}

variable "database_user" {
  description = "Database user (username)"
  type        = string
  default     = "nova_admin"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "database_machine_type" {
  description = "Cloud SQL machine type (tier)"
  type        = string
  default     = "db-custom-4-16384"
}

variable "database_disk_size" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 100
}

# Memorystore Redis Variables
variable "redis_instance_name" {
  description = "Memorystore Redis instance name prefix"
  type        = string
  default     = "nova-redis"
}

variable "redis_size_gb" {
  description = "Redis memory size in GB"
  type        = number
  default     = 1
}

variable "redis_tier" {
  description = "Redis tier (BASIC or STANDARD)"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["BASIC", "STANDARD"], var.redis_tier)
    error_message = "Redis tier must be 'BASIC' or 'STANDARD'."
  }
}

variable "redis_version" {
  description = "Redis version"
  type        = string
  default     = "7.0"
}

# Networking Variables
variable "network_id" {
  description = "VPC network ID"
  type        = string
}

variable "private_vpc_connection" {
  description = "Private VPC connection resource reference (required for private instance)"
  type        = any
}

variable "tags" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
