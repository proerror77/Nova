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

# Artifact Registry Variables
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

# KMS Encryption
variable "kms_key" {
  description = "KMS key for bucket encryption (optional)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
