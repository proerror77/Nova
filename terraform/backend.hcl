# Terraform S3 Backend Configuration
# 使用方式: terraform init -backend-config=backend.hcl

bucket         = "nova-terraform-state-025434362120"
key            = "staging/terraform.tfstate"
region         = "ap-northeast-1"
dynamodb_table = "nova-terraform-locks"
encrypt        = true
