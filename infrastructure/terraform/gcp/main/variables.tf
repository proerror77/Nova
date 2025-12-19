variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "banded-pad-479802-k9"
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "asia-northeast1"
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

# VPC Configuration
variable "vpc_name" {
  description = "VPC network name"
  type        = string
  default     = "nova-vpc"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet CIDR block"
  type        = string
  default     = "10.0.0.0/20"
}

# GKE Configuration
variable "gke_cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "nova-staging-gke"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.27"
}

# On-Demand Node Pool
variable "on_demand_initial_node_count" {
  description = "Initial node count for on-demand pool"
  type        = number
  default     = 2
}

variable "on_demand_min_node_count" {
  description = "Minimum node count for on-demand pool"
  type        = number
  default     = 2
}

variable "on_demand_max_node_count" {
  description = "Maximum node count for on-demand pool"
  type        = number
  default     = 5
}

variable "on_demand_machine_type" {
  description = "Machine type for on-demand nodes"
  type        = string
  default     = "n2-standard-4"
}

# Spot Node Pool
variable "spot_initial_node_count" {
  description = "Initial node count for spot pool"
  type        = number
  default     = 0  # Disabled for staging
}

variable "spot_min_node_count" {
  description = "Minimum node count for spot pool"
  type        = number
  default     = 0
}

variable "spot_max_node_count" {
  description = "Maximum node count for spot pool"
  type        = number
  default     = 3
}

variable "spot_machine_type" {
  description = "Machine type for spot nodes"
  type        = string
  default     = "n2-standard-4"
}

# Cloud SQL Configuration
variable "database_instance_name" {
  description = "Cloud SQL instance name prefix"
  type        = string
  default     = "nova"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "nova"
}

variable "database_user" {
  description = "Database user"
  type        = string
  default     = "nova_admin"
}

variable "database_machine_type" {
  description = "Cloud SQL machine type"
  type        = string
  default     = "db-custom-4-16384"
}

variable "database_disk_size" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 100
}

# Memorystore Redis Configuration
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
}

variable "redis_version" {
  description = "Redis version"
  type        = string
  default     = "7.0"
}

# Artifact Registry Configuration
variable "artifact_repo_name" {
  description = "Artifact Registry repository name prefix"
  type        = string
  default     = "nova"
}

variable "artifact_keep_recent_versions" {
  description = "Number of recent images to keep in Artifact Registry"
  type        = number
  default     = 10
}

# GitHub Actions OIDC Configuration
variable "github_org" {
  description = "GitHub organization or username"
  type        = string
  default     = "proerror"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "nova"
}

variable "github_main_branch" {
  description = "GitHub main branch name"
  type        = string
  default     = "main"
}

variable "enable_branch_specific_oidc" {
  description = "Enable branch-specific OIDC binding (recommended for production)"
  type        = bool
  default     = false
}

# Kubernetes Configuration
variable "k8s_namespace" {
  description = "Kubernetes namespace for workloads"
  type        = string
  default     = "nova-staging"
}

variable "k8s_service_account" {
  description = "Kubernetes service account name"
  type        = string
  default     = "k8s-workloads"
}

# Tags (for resource labeling)
variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default = {
    project     = "nova"
    environment = "staging"
    managed_by  = "terraform"
  }
}

# CDN Configuration
variable "media_bucket_name" {
  description = "GCS bucket name for media storage"
  type        = string
  default     = "nova-media-staging"
}

variable "cdn_domain" {
  description = "Domain name for CDN (e.g., media.nova.social)"
  type        = string
  default     = "media-staging.nova.social"
}

variable "cdn_cors_origins" {
  description = "Allowed CORS origins for media CDN"
  type        = list(string)
  default     = ["*"]
}

variable "cdn_create_dns_record" {
  description = "Whether to create DNS record in Cloud DNS"
  type        = bool
  default     = false
}

variable "cdn_dns_zone_name" {
  description = "Cloud DNS zone name (required if cdn_create_dns_record is true)"
  type        = string
  default     = ""
}
