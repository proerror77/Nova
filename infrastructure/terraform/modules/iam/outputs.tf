output "eks_cluster_role_arn" {
  description = "EKS cluster IAM role ARN"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "eks_node_role_arn" {
  description = "EKS node IAM role ARN"
  value       = aws_iam_role.eks_node_role.arn
}

output "eks_node_instance_profile_name" {
  description = "EKS node instance profile name"
  value       = aws_iam_instance_profile.eks_node_instance_profile.name
}

output "ecr_access_role_arn" {
  description = "ECR access role ARN"
  value       = aws_iam_role.ecr_access_role.arn
}

output "alb_controller_role_arn" {
  description = "ALB controller role ARN"
  value       = aws_iam_role.alb_controller_role.arn
}

output "external_dns_role_arn" {
  description = "ExternalDNS role ARN"
  value       = aws_iam_role.external_dns_role.arn
}

output "cert_manager_role_arn" {
  description = "Cert-manager role ARN"
  value       = aws_iam_role.cert_manager_role.arn
}

output "ebs_csi_role_arn" {
  description = "EBS CSI driver role ARN"
  value       = aws_iam_role.ebs_csi_driver_role.arn
}

output "github_actions_role_arn" {
  description = "GitHub Actions role ARN"
  value       = aws_iam_role.github_actions_role.arn
}
