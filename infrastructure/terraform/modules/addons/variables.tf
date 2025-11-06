variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ecr_access_role_arn" {
  description = "ECR access role ARN"
  type        = string
}

variable "alb_controller_role_arn" {
  description = "ALB controller role ARN"
  type        = string
}

variable "external_dns_role_arn" {
  description = "ExternalDNS role ARN"
  type        = string
}

variable "cert_manager_role_arn" {
  description = "Cert-manager role ARN"
  type        = string
}

variable "ebs_csi_role_arn" {
  description = "EBS CSI role ARN"
  type        = string
}

# Version variables
variable "coredns_version" {
  description = "CoreDNS addon version"
  type        = string
  default     = "v1.10.1-eksbuild.2"
}

variable "kube_proxy_version" {
  description = "Kube-proxy addon version"
  type        = string
  default     = "v1.28.1-eksbuild.1"
}

variable "vpc_cni_version" {
  description = "VPC CNI addon version"
  type        = string
  default     = "v1.14.1-eksbuild.1"
}

variable "ebs_csi_driver_version" {
  description = "EBS CSI driver addon version"
  type        = string
  default     = "v1.24.0-eksbuild.1"
}

# Feature flags
variable "enable_monitoring" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Enable Metrics Server"
  type        = bool
  default     = true
}
