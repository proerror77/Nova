# =============================================================================
# Cloud CDN Variables
# =============================================================================

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for bucket location"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (e.g., staging, production)"
  type        = string
}

variable "media_bucket_name" {
  description = "Name of the GCS bucket for media storage"
  type        = string
}

variable "cdn_domain" {
  description = "Domain name for CDN (e.g., media.nova.social)"
  type        = string
}

variable "cors_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = ["*"]
}

variable "create_dns_record" {
  description = "Whether to create DNS record in Cloud DNS"
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "Cloud DNS zone name (required if create_dns_record is true)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional labels to apply to resources"
  type        = map(string)
  default     = {}
}
