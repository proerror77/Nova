terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "gcs" {
    bucket  = "nova-terraform-state"
    prefix  = "gcp/staging"
    # encryption_key = "..." # Optional: GCS encryption
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "random" {}

# Data source for current GCP configuration
data "google_client_config" "current" {}

# Network Module (VPC, Subnets, Cloud NAT, Firewall)
module "network" {
  source = "../network"

  gcp_project_id = var.gcp_project_id
  gcp_region     = var.gcp_region
  environment    = var.environment

  vpc_name    = var.vpc_name
  vpc_cidr    = var.vpc_cidr
  subnet_cidr = var.subnet_cidr

  tags = local.common_labels
}

# Private VPC Connection (for Cloud SQL and Redis)
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = module.network.vpc_name
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = ["google-managed-services-${var.vpc_name}"]
}

# Compute Module (GKE Cluster and Node Pools)
module "compute" {
  source = "../compute"

  gcp_project_id     = var.gcp_project_id
  gcp_region         = var.gcp_region
  environment        = var.environment
  kubernetes_version = var.kubernetes_version

  network_name    = module.network.vpc_name
  subnet_name     = module.network.subnet_name
  cluster_name    = var.gke_cluster_name

  # On-Demand Node Pool Configuration
  on_demand_initial_node_count = var.on_demand_initial_node_count
  on_demand_min_node_count     = var.on_demand_min_node_count
  on_demand_max_node_count     = var.on_demand_max_node_count
  on_demand_machine_type       = var.on_demand_machine_type

  # Spot Node Pool Configuration
  spot_initial_node_count = var.spot_initial_node_count
  spot_min_node_count     = var.spot_min_node_count
  spot_max_node_count     = var.spot_max_node_count
  spot_machine_type       = var.spot_machine_type

  tags       = local.common_labels
  depends_on = [module.network]
}

# Database Module (Cloud SQL PostgreSQL + Memorystore Redis)
module "database" {
  source = "../database"

  gcp_project_id = var.gcp_project_id
  gcp_region     = var.gcp_region
  environment    = var.environment

  # Cloud SQL
  database_instance_name = var.database_instance_name
  database_name          = var.database_name
  database_user          = var.database_user
  postgres_version       = var.postgres_version
  database_machine_type  = var.database_machine_type
  database_disk_size     = var.database_disk_size

  # Memorystore Redis
  redis_instance_name = var.redis_instance_name
  redis_size_gb       = var.redis_size_gb
  redis_tier          = var.redis_tier
  redis_version       = var.redis_version

  # Networking
  network_id              = module.network.vpc_name
  private_vpc_connection  = google_service_networking_connection.private_vpc_connection

  tags       = local.common_labels
  depends_on = [module.network, google_service_networking_connection.private_vpc_connection]
}

# Storage Module (Artifact Registry + Cloud Storage Buckets)
module "storage" {
  source = "../storage"

  gcp_project_id = var.gcp_project_id
  gcp_region     = var.gcp_region
  environment    = var.environment

  artifact_repo_name           = var.artifact_repo_name
  artifact_keep_recent_versions = var.artifact_keep_recent_versions

  tags = local.common_labels
}

# IAM Module (Service Accounts + Workload Identity Federation)
module "iam" {
  source = "../iam"

  environment = var.environment

  # GitHub Configuration for OIDC
  github_org              = var.github_org
  github_repo             = var.github_repo
  github_main_branch      = var.github_main_branch
  enable_branch_specific_oidc = var.enable_branch_specific_oidc

  # Kubernetes Configuration
  k8s_namespace          = var.k8s_namespace
  k8s_service_account    = var.k8s_service_account

  depends_on = [module.compute]
}

# CDN Module (Cloud CDN + Media Storage)
module "cdn" {
  source = "../cdn"

  gcp_project       = var.gcp_project_id
  gcp_region        = var.gcp_region
  environment       = var.environment
  media_bucket_name = var.media_bucket_name
  cdn_domain        = var.cdn_domain
  cors_origins      = var.cdn_cors_origins
  create_dns_record = var.cdn_create_dns_record
  dns_zone_name     = var.cdn_dns_zone_name

  tags = local.common_labels
}

# Local variables
locals {
  common_labels = {
    environment = var.environment
    project     = "nova"
    managed_by  = "terraform"
  }
}

# Outputs - Compute
output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = module.compute.gke_cluster_name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.compute.gke_cluster_endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = module.compute.gke_cluster_ca_certificate
  sensitive   = true
}

output "gke_network_name" {
  description = "GKE network name"
  value       = module.compute.gke_network_name
}

output "gke_subnetwork_name" {
  description = "GKE subnetwork name"
  value       = module.compute.gke_subnetwork_name
}

# Outputs - Database
output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = module.database.cloud_sql_instance_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP address"
  value       = module.database.cloud_sql_private_ip
  sensitive   = true
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name (project:region:instance)"
  value       = module.database.cloud_sql_connection_name
  sensitive   = true
}

output "redis_host" {
  description = "Memorystore Redis host IP"
  value       = module.database.redis_host
  sensitive   = true
}

output "redis_port" {
  description = "Memorystore Redis port"
  value       = module.database.redis_port
}

output "cloudsql_proxy_service_account" {
  description = "Cloud SQL Proxy service account email"
  value       = module.database.cloudsql_proxy_service_account
}

output "redis_access_service_account" {
  description = "Redis access service account email"
  value       = module.database.redis_access_service_account
}

output "db_password_secret" {
  description = "Secret Manager secret ID for DB password"
  value       = module.database.db_password_secret
}

output "db_connection_string_secret" {
  description = "Secret Manager secret ID for DB connection string"
  value       = module.database.db_connection_string_secret
}

output "redis_connection_secret" {
  description = "Secret Manager secret ID for Redis connection"
  value       = module.database.redis_connection_secret
}

# Outputs - Storage
output "artifact_registry_url" {
  description = "Artifact Registry repository URL"
  value       = module.storage.artifact_registry_url
}

output "artifact_registry_repository_id" {
  description = "Artifact Registry repository ID"
  value       = module.storage.artifact_registry_repository_id
}

output "terraform_state_bucket" {
  description = "Terraform state bucket name"
  value       = module.storage.terraform_state_bucket
}

output "backups_bucket" {
  description = "Backups bucket name"
  value       = module.storage.backups_bucket
}

output "logs_bucket" {
  description = "Logs bucket name"
  value       = module.storage.logs_bucket
}

output "artifact_registry_service_account" {
  description = "Artifact Registry service account email"
  value       = module.storage.artifact_registry_service_account
}

output "storage_access_service_account" {
  description = "Storage access service account email"
  value       = module.storage.storage_access_service_account
}

# Outputs - IAM
output "workload_identity_pool_resource_name" {
  description = "Workload Identity Pool resource name"
  value       = module.iam.workload_identity_pool_resource_name
}

output "workload_identity_provider_resource_name" {
  description = "Workload Identity Provider resource name"
  value       = module.iam.workload_identity_provider_resource_name
}

output "github_actions_service_account" {
  description = "GitHub Actions service account email"
  value       = module.iam.github_actions_service_account
}

output "k8s_workloads_service_account" {
  description = "K8s Workloads service account email"
  value       = module.iam.k8s_workloads_service_account
}

output "workload_identity_pool_id" {
  description = "Workload Identity Pool ID (for GitHub Actions config)"
  value       = module.iam.workload_identity_pool_id
}

output "project_number" {
  description = "GCP Project Number"
  value       = module.iam.project_number
}

# Outputs - CDN
output "cdn_ip_address" {
  description = "CDN static IP address"
  value       = module.cdn.cdn_ip_address
}

output "cdn_url" {
  description = "CDN URL for media access"
  value       = module.cdn.cdn_url
}

output "media_bucket_name" {
  description = "Media storage bucket name"
  value       = module.cdn.media_bucket_name
}

output "media_bucket_url" {
  description = "Direct GCS URL (for fallback)"
  value       = module.cdn.media_bucket_url
}

output "media_uploader_service_account" {
  description = "Service account email for media uploads"
  value       = module.cdn.media_uploader_service_account
}
