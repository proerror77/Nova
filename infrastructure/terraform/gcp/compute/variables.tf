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

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
}

variable "network_name" {
  description = "VPC network name"
  type        = string
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.27"
}

# On-Demand Node Pool Configuration
variable "on_demand_initial_node_count" {
  description = "Initial number of on-demand nodes"
  type        = number
  default     = 2
}

variable "on_demand_min_node_count" {
  description = "Minimum number of on-demand nodes"
  type        = number
  default     = 2
}

variable "on_demand_max_node_count" {
  description = "Maximum number of on-demand nodes"
  type        = number
  default     = 5
}

variable "on_demand_machine_type" {
  description = "Machine type for on-demand nodes"
  type        = string
  default     = "n2-standard-4"
}

# Spot Node Pool Configuration
variable "spot_initial_node_count" {
  description = "Initial number of spot (preemptible) nodes"
  type        = number
  default     = 0
}

variable "spot_min_node_count" {
  description = "Minimum number of spot nodes"
  type        = number
  default     = 0
}

variable "spot_max_node_count" {
  description = "Maximum number of spot nodes"
  type        = number
  default     = 3
}

variable "spot_machine_type" {
  description = "Machine type for spot nodes"
  type        = string
  default     = "n2-standard-4"
}

variable "tags" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
