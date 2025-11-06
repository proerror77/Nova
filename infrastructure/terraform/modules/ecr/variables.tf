variable "environment" {
  description = "Environment name"
  type        = string
}

variable "services" {
  description = "List of services to create ECR repositories for"
  type        = list(string)
}

variable "ecr_registry_alias" {
  description = "ECR registry alias (namespace)"
  type        = string
}
