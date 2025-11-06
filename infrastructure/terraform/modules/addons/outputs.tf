output "vpc_cni_role_arn" {
  description = "VPC CNI role ARN"
  value       = aws_iam_role.vpc_cni.arn
}

output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace.addons["argocd"].metadata[0].name
}

output "ingress_namespace" {
  description = "Ingress namespace"
  value       = kubernetes_namespace.addons["ingress-nginx"].metadata[0].name
}

output "monitoring_namespace" {
  description = "Monitoring namespace"
  value       = kubernetes_namespace.addons["kube-monitoring"].metadata[0].name
}
