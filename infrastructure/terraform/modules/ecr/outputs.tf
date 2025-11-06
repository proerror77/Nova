output "registry_url" {
  description = "ECR registry URL"
  value       = "025434362120.dkr.ecr.${data.aws_caller_identity.current.account_id}.amazonaws.com"
}

output "repository_urls" {
  description = "ECR repository URLs by service"
  value = {
    for service, repo in aws_ecr_repository.nova_services :
    service => repo.repository_url
  }
}

output "repository_names" {
  description = "ECR repository names by service"
  value = {
    for service, repo in aws_ecr_repository.nova_services :
    service => repo.name
  }
}

output "registry_alias" {
  description = "ECR registry alias"
  value       = var.ecr_registry_alias
}
