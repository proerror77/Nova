# ============================================================================
# Nova EKS Infrastructure Outputs
# ============================================================================
# These outputs display important information after terraform apply completes

# ============================================================================
# VPC Outputs
# ============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_ips" {
  description = "NAT Gateway public IPs for outbound traffic"
  value       = module.vpc.nat_gateway_ips
}

# ============================================================================
# EKS Cluster Outputs
# ============================================================================

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = module.eks.cluster_version
}

output "cluster_ca_certificate" {
  description = "Base64 encoded cluster CA certificate"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

# ============================================================================
# IAM Outputs
# ============================================================================

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC"
  value       = module.iam.github_actions_role_arn
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for GitHub Actions authentication"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL"
  value       = module.eks.oidc_provider_url
}

# ============================================================================
# ECR Outputs
# ============================================================================

output "ecr_registry_url" {
  description = "ECR registry URL"
  value       = module.ecr.registry_url
}

output "ecr_repositories" {
  description = "Map of ECR repository names to their URLs"
  value       = module.ecr.repository_urls
}

# ============================================================================
# Kubectl Configuration
# ============================================================================

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "configure_kubectl_instructions" {
  description = "Instructions to configure kubectl"
  value       = <<-EOT
    Run the following command to configure kubectl:

    aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}

    Then verify the connection:

    kubectl get nodes
    kubectl get pods -A
  EOT
}

# ============================================================================
# ArgoCD Access Instructions
# ============================================================================

output "argocd_access_instructions" {
  description = "Instructions for accessing ArgoCD"
  value       = <<-EOT
    To access ArgoCD UI:

    1. Get the initial password:
       kubectl -n argocd get secret argocd-initial-admin-secret \
         -o jsonpath="{.data.password}" | base64 -d; echo

    2. Port forward to ArgoCD:
       kubectl port-forward svc/argocd-server -n argocd 8080:443

    3. Open browser:
       https://localhost:8080
       Username: admin
       Password: (from step 1)

    4. Add GitHub repository:
       argocd repo add https://github.com/proerror77/Nova.git \
         --username <github-username> \
         --password <github-token>

    5. Deploy applications:
       kubectl apply -f infrastructure/argocd/nova-staging-app.yaml
       kubectl apply -f infrastructure/argocd/nova-production-app.yaml
  EOT
}

# ============================================================================
# Cost Information
# ============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly AWS cost"
  value       = "~$313 (EKS: $73 + EC2: $150-200 + NAT: $45 + ALB: $20 + Other: $25)"
}

output "cost_optimization_tips" {
  description = "Tips to reduce costs"
  value       = <<-EOT
    To reduce costs:

    1. Use Spot Instances (saves ~70%)
    2. Reduce node count or instance size
    3. Delete unused NAT Gateways
    4. Enable auto-scaling based on demand
    5. Regular cleanup of ECR images
  EOT
}

# ============================================================================
# Next Steps
# ============================================================================

output "next_steps" {
  description = "Next steps after infrastructure deployment"
  value       = <<-EOT
    1. Configure kubectl:
       aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}

    2. Verify cluster health:
       kubectl get nodes
       kubectl get pods -A

    3. Access ArgoCD:
       kubectl port-forward svc/argocd-server -n argocd 8080:443
       # Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

    4. Add GitHub repository to ArgoCD:
       argocd repo add https://github.com/proerror77/Nova.git \
         --username <github-username> \
         --password <github-token>

    5. Deploy applications:
       kubectl apply -f infrastructure/argocd/nova-staging-app.yaml
       kubectl apply -f infrastructure/argocd/nova-production-app.yaml

    6. Monitor deployment:
       kubectl get applications -n argocd -w
       kubectl get pods -n nova-staging
  EOT
}
