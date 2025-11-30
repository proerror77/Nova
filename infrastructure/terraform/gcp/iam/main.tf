# Workload Identity Pool for GitHub Actions
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  location                  = "global"
  disabled                  = false
  description               = "Workload Identity Pool for GitHub Actions CI/CD"

  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.actor"       = "assertion.actor"
    "attribute.repository"  = "assertion.repository"
    "attribute.environment" = "assertion.environment"
  }

  attribute_condition = "assertion.aud == 'https://github.com/${var.github_org}'"
}

# Workload Identity Provider for GitHub
resource "google_iam_workload_identity_pool_provider" "github" {
  display_name                       = "GitHub Provider"
  location                           = "global"
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  disabled                           = false

  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.actor"       = "assertion.actor"
    "attribute.repository"  = "assertion.repository"
    "attribute.environment" = "assertion.environment"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service Account for GitHub Actions CI/CD
resource "google_service_account" "github_actions" {
  account_id   = "github-actions"
  display_name = "GitHub Actions CI/CD"
  description  = "Service account for GitHub Actions to build, push images, and deploy"
}

# Workload Identity binding: Allow GitHub Actions to impersonate service account
resource "google_service_account_iam_binding" "github_actions_oidc" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/projects/${data.google_client_config.current.project_number}/locations/global/workloadIdentityPools/github/attribute.repository/${var.github_org}/${var.github_repo}"
  ]
}

# More granular binding for specific branch (e.g., main)
resource "google_service_account_iam_binding" "github_actions_main_branch" {
  count              = var.enable_branch_specific_oidc ? 1 : 0
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/projects/${data.google_client_config.current.project_number}/locations/global/workloadIdentityPools/github/attribute.repository/${var.github_org}/${var.github_repo}/ref:refs/heads/${var.github_main_branch}"
  ]
}

# Grant GitHub Actions permissions to push to Artifact Registry
resource "google_project_iam_member" "github_artifact_push" {
  project = data.google_client_config.current.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Grant GitHub Actions permissions to pull from Artifact Registry
resource "google_project_iam_member" "github_artifact_pull" {
  project = data.google_client_config.current.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Grant GitHub Actions permissions to manage GKE
resource "google_project_iam_member" "github_gke_admin" {
  project = data.google_client_config.current.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Grant GitHub Actions permissions to read from Secret Manager
resource "google_project_iam_member" "github_secrets_read" {
  project = data.google_client_config.current.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Grant GitHub Actions permissions for Cloud SQL operations
resource "google_project_iam_member" "github_sql_client" {
  project = data.google_client_config.current.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Grant GitHub Actions permissions for Cloud Storage access (backups)
resource "google_project_iam_member" "github_storage_access" {
  project = data.google_client_config.current.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Service Account for K8s Workload Identity (microservices)
resource "google_service_account" "k8s_workloads" {
  account_id   = "k8s-workloads-${var.environment}"
  display_name = "K8s Workloads for ${var.environment}"
  description  = "Service account for Kubernetes microservices to access GCP services"
}

# Bind K8s Service Account to GCP Service Account (Workload Identity)
resource "google_service_account_iam_binding" "k8s_workload_identity" {
  service_account_id = google_service_account.k8s_workloads.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${data.google_client_config.current.project_id}.svc.id.goog[${var.k8s_namespace}/k8s-workloads]"
  ]
}

# Grant K8s workloads access to Secret Manager
resource "google_project_iam_member" "k8s_secrets_access" {
  project = data.google_client_config.current.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.k8s_workloads.email}"
}

# Grant K8s workloads access to Cloud SQL
resource "google_project_iam_member" "k8s_sql_client" {
  project = data.google_client_config.current.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.k8s_workloads.email}"
}

# Grant K8s workloads access to Cloud Storage
resource "google_project_iam_member" "k8s_storage_admin" {
  project = data.google_client_config.current.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.k8s_workloads.email}"
}

# Grant K8s workloads access to Redis
resource "google_project_iam_member" "k8s_redis_access" {
  project = data.google_client_config.current.project_id
  role    = "roles/redis.editor"
  member  = "serviceAccount:${google_service_account.k8s_workloads.email}"
}

# Retrieve current config for references
data "google_client_config" "current" {}

# Outputs
output "workload_identity_pool_resource_name" {
  description = "Workload Identity Pool resource name"
  value       = google_iam_workload_identity_pool.github.name
}

output "workload_identity_provider_resource_name" {
  description = "Workload Identity Provider resource name"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_actions_service_account" {
  description = "GitHub Actions service account email"
  value       = google_service_account.github_actions.email
}

output "k8s_workloads_service_account" {
  description = "K8s Workloads service account email"
  value       = google_service_account.k8s_workloads.email
}

output "workload_identity_pool_id" {
  description = "Workload Identity Pool ID (for GitHub Actions config)"
  value       = google_iam_workload_identity_pool.github.workload_identity_pool_id
}

output "project_number" {
  description = "GCP Project Number"
  value       = data.google_client_config.current.project_number
}
