# Artifact Registry Repository (for container images)
resource "google_artifact_registry_repository" "main" {
  location      = var.gcp_region
  repository_id = "${var.artifact_repo_name}-${var.environment}"
  format        = "DOCKER"
  description   = "Docker repository for Nova ${var.environment} environment"

  docker_config {
    immutable_tags = false
  }

  cleanup_policies {
    id     = "keep-recent-images"
    action = "DELETE"
    condition {
      most_recent_versions {
        keep_count = var.artifact_keep_recent_versions
      }
    }
  }

  cleanup_policies {
    id     = "delete-old-images"
    action = "DELETE"
    condition {
      older_than = "2592000s" # 30 days in seconds
    }
  }

  labels = merge(
    {
      environment = var.environment
      service     = "registry"
    },
    var.tags
  )
}

# Service Account for Artifact Registry push/pull
resource "google_service_account" "artifact_registry_sa" {
  account_id   = "artifact-registry-${var.environment}"
  display_name = "Artifact Registry Access for ${var.environment}"
  description  = "Service account for pushing/pulling images from Artifact Registry"
}

# Grant Artifact Registry admin role
resource "google_project_iam_member" "artifact_registry_writer" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.artifact_registry_sa.email}"
}

resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.artifact_registry_sa.email}"
}

# Cloud Storage Bucket for Terraform state (backend)
resource "google_storage_bucket" "terraform_state" {
  name          = "${var.gcp_project_id}-terraform-state"
  location      = var.gcp_region
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      num_newer_versions = 5
    }
  }

  encryption {
    default_kms_key_name = var.kms_key != null ? var.kms_key : null
  }

  labels = merge(
    {
      environment = var.environment
      purpose     = "terraform-state"
    },
    var.tags
  )
}

# Enable versioning block for state bucket
resource "google_storage_bucket_versioning" "terraform_state" {
  bucket = google_storage_bucket.terraform_state.name
  versioning_config {
    enabled = true
  }
}

# Cloud Storage Bucket for application backups
resource "google_storage_bucket" "backups" {
  name          = "${var.gcp_project_id}-${var.environment}-backups"
  location      = var.gcp_region
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition {
      age = 90 # After 90 days, move to COLDLINE
    }
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365 # Delete after 1 year
    }
  }

  encryption {
    default_kms_key_name = var.kms_key != null ? var.kms_key : null
  }

  labels = merge(
    {
      environment = var.environment
      purpose     = "backups"
    },
    var.tags
  )
}

# Cloud Storage Bucket for application logs
resource "google_storage_bucket" "logs" {
  name          = "${var.gcp_project_id}-${var.environment}-logs"
  location      = var.gcp_region
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 90 # Delete logs after 90 days
    }
  }

  encryption {
    default_kms_key_name = var.kms_key != null ? var.kms_key : null
  }

  labels = merge(
    {
      environment = var.environment
      purpose     = "logs"
    },
    var.tags
  )
}

# Service Account for Cloud Storage access
resource "google_service_account" "storage_access" {
  account_id   = "storage-access-${var.environment}"
  display_name = "Cloud Storage Access for ${var.environment}"
  description  = "Service account for accessing Cloud Storage from Kubernetes"
}

# Grant Storage object admin role
resource "google_project_iam_member" "storage_admin" {
  project = var.gcp_project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.storage_access.email}"
}

# IAM binding for artifact registry bucket
resource "google_storage_bucket_iam_member" "artifact_registry_sa" {
  bucket = google_artifact_registry_repository.main.id
  role   = "roles/artifactregistry.writer"
  member = "serviceAccount:${google_service_account.artifact_registry_sa.email}"
}

# Outputs
output "artifact_registry_url" {
  description = "Artifact Registry repository URL"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.main.repository_id}"
}

output "artifact_registry_repository_id" {
  description = "Artifact Registry repository ID"
  value       = google_artifact_registry_repository.main.repository_id
}

output "terraform_state_bucket" {
  description = "Terraform state bucket name"
  value       = google_storage_bucket.terraform_state.name
}

output "backups_bucket" {
  description = "Backups bucket name"
  value       = google_storage_bucket.backups.name
}

output "logs_bucket" {
  description = "Logs bucket name"
  value       = google_storage_bucket.logs.name
}

output "artifact_registry_service_account" {
  description = "Artifact Registry service account email"
  value       = google_service_account.artifact_registry_sa.email
}

output "storage_access_service_account" {
  description = "Storage access service account email"
  value       = google_service_account.storage_access.email
}
