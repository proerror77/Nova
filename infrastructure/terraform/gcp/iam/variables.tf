variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

# GitHub Configuration
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
