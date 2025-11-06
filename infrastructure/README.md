# Nova Infrastructure as Code (IaC)

Complete Terraform-based infrastructure deployment for the Nova microservices platform on AWS EKS with GitOps using ArgoCD.

## 📋 Overview

This infrastructure implements a production-ready Kubernetes platform with:

- **AWS EKS**: Managed Kubernetes cluster with 3 nodes across 2 availability zones
- **ECR**: Private container registries for 8 microservices
- **ArgoCD**: GitOps continuous deployment with automatic synchronization
- **Kustomize**: Multi-environment configuration management (staging/production)
- **GitHub Actions**: CI/CD pipeline with OIDC authentication
- **High Availability**: Multi-AZ setup with load balancing and auto-scaling

## 📁 Directory Structure

```
infrastructure/
├── terraform/                      # Infrastructure as Code
│   ├── main.tf                     # Main configuration
│   ├── variables.tf                # Variable definitions
│   ├── outputs.tf                  # Output values
│   ├── terraform.tfvars.example    # Configuration template
│   ├── deploy.sh                   # Automated deployment script
│   ├── .gitignore                  # Git ignore rules
│   ├── README.md                   # Terraform documentation
│   └── modules/
│       ├── vpc/                    # VPC and networking
│       ├── eks/                    # EKS cluster
│       ├── ecr/                    # Container registries
│       ├── iam/                    # Identity and access
│       └── addons/                 # Kubernetes add-ons
├── argocd/                         # GitOps configuration
│   ├── nova-staging-app.yaml       # Staging deployment
│   ├── nova-production-app.yaml    # Production deployment
│   └── README.md                   # ArgoCD guide
└── README.md                       # This file

k8s/                                # Kubernetes manifests
├── kustomization.yaml              # Base configuration
├── base/                           # Base Kustomize
│   └── kustomization.yaml
└── overlays/                       # Environment overlays
    ├── staging/                    # Staging overrides
    │   └── kustomization.yaml
    └── production/                 # Production overrides
        └── kustomization.yaml
```

## 🚀 Quick Start (5 Minutes)

### Prerequisites

```bash
# Install required tools
brew install terraform aws-cli kubectl

# Configure AWS credentials
aws configure

# Verify credentials
aws sts get-caller-identity
```

### Deployment

```bash
cd infrastructure/terraform

# 1. Copy and customize configuration
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your desired values

# 2. Initialize and deploy
./deploy.sh apply
# This will take 10-15 minutes

# 3. Configure kubectl
aws eks update-kubeconfig --region ap-northeast-1 --name nova-eks

# 4. Verify cluster
kubectl get nodes
kubectl get pods -A
```

### Access ArgoCD

```bash
# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser: https://localhost:8080
# Username: admin
# Password: (from above)
```

## 📋 Phase-Based Deployment

### Phase 1: Infrastructure Deployment
- **Time**: 10-15 minutes
- **Action**: Run `./deploy.sh apply`
- **Verification**: `kubectl get nodes` (3 nodes)

### Phase 2: GitOps Setup
- **Time**: 5-10 minutes
- **Action**: Add GitHub repo to ArgoCD
- **Verification**: `argocd repo list`

### Phase 3: Application Deployment
- **Time**: 5 minutes
- **Action**: Apply ArgoCD applications
- **Verification**: `kubectl get pods -n nova-staging`

### Phase 4: Verification
- **Time**: 5 minutes
- **Action**: Test service connectivity
- **Verification**: Health checks, logs review

## 🔧 Configuration

### terraform.tfvars

**Required settings**:

```hcl
# AWS region
aws_region = "ap-northeast-1"

# Cluster name (must be unique)
cluster_name = "nova-eks"

# Node configuration
node_group_min_size = 2
node_group_desired_size = 3
node_group_max_size = 10

# GitHub configuration
github_repo_owner = "proerror77"
github_repo_name = "Nova"
github_oidc_provider_arn = "" # Set after creating OIDC provider
```

**Optional settings**:

```hcl
# VPC CIDR
vpc_cidr = "10.0.0.0/16"

# Kubernetes version
kubernetes_version = "1.28"

# Feature flags
enable_monitoring = true
enable_logging = true
enable_cert_manager = true
```

## 📊 Deployment Architecture

```
GitHub Repository
    ↓ (on push)
GitHub Actions
    ↓ (build & push)
AWS ECR (Container Registry)
    ↓ (monitor for changes)
ArgoCD
    ↓ (auto-sync)
EKS Cluster (3 nodes, 2 AZs)
    ↓
Nova Services (8 microservices)
```

## 🔒 Security Features

✅ **Network Security**
- Private subnets for EKS nodes
- Public subnets with NAT gateways
- Security groups with least privilege
- VPC Flow Logs enabled

✅ **Identity & Access**
- IAM roles with minimal permissions
- OIDC provider for GitHub Actions
- IRSA for pod-level authentication
- Service accounts per add-on

✅ **Container Security**
- ECR image scanning enabled
- Private repositories
- Secret encryption
- Network policies (can be enabled)

✅ **Kubernetes Security**
- RBAC enabled
- Pod security policies
- Admission controllers

## 💰 Cost Management

### Estimated Monthly Costs

| Component | Cost |
|-----------|------|
| EKS Control Plane | $73 |
| EC2 Nodes (3x t3.medium) | $150-200 |
| NAT Gateways (2x) | $45 |
| Data Transfer | $20 |
| ECR Storage | $5 |
| Load Balancers | $20 |
| **Total** | **~$313** |

### Cost Optimization

1. **Use Spot Instances** (saves ~70%)
   - Edit variables.tf: `node_instance_types = ["t3.medium"]` → spot

2. **Reduce Node Count** (saves ~$50/node)
   - Edit terraform.tfvars: `node_group_desired_size = 2`

3. **Delete Unused NAT Gateways** (saves $45)
   - Only needed if no outbound internet required

4. **Enable Resource Quotas**
   - Prevents resource waste

5. **Regular ECR Cleanup**
   - Delete old images automatically

## 🔍 Monitoring & Logs

### View Cluster Health

```bash
# Nodes
kubectl get nodes
kubectl top nodes

# Pods
kubectl get pods -A
kubectl get pods -n nova-staging

# Services
kubectl get svc -A

# Events
kubectl get events -A --sort-by='.lastTimestamp'
```

### View Logs

```bash
# Pod logs
kubectl logs -f <pod-name> -n <namespace>

# Previous logs (if crashed)
kubectl logs --previous <pod-name> -n <namespace>

# EKS control plane logs
aws logs describe-log-groups --region ap-northeast-1 | grep /aws/eks
```

### CloudWatch Metrics

```bash
# Check enabled logs
aws eks describe-cluster --name nova-eks \
  --query 'cluster.logging.clusterLogging' \
  --region ap-northeast-1
```

## 🐛 Troubleshooting

### Terraform Issues

```bash
# Debug with verbose output
TF_LOG=DEBUG terraform apply

# Check state
terraform show

# Refresh state
terraform refresh
```

### Pods Won't Start

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Common issues:
# - Image pull errors: Check ECR credentials
# - Resource limits: Check node capacity
# - PVC issues: Check EBS volume status
```

### ArgoCD Sync Issues

```bash
# Check app status
argocd app get nova-staging

# Check repo connection
argocd repo list

# Verify Kustomize
kustomize build k8s/overlays/staging
```

### Network Issues

```bash
# Check service endpoints
kubectl get endpoints -n nova-staging

# Test pod-to-pod connectivity
kubectl exec -it <pod> -n <namespace> -- \
  curl http://<service>.<namespace>.svc.cluster.local:8000

# Check security groups
aws ec2 describe-security-groups --region ap-northeast-1 \
  --filters Name=group-name,Values=nova-*
```

## 📚 Documentation

- [Terraform Details](./terraform/README.md) - In-depth Terraform configuration
- [ArgoCD Guide](./argocd/README.md) - GitOps workflow documentation
- [Deployment Guide](../DEPLOYMENT_GUIDE.md) - Complete step-by-step guide
- [Quick Start](../QUICKSTART.md) - 5-minute quick reference
- [Infrastructure Summary](../INFRASTRUCTURE_SUMMARY.md) - Architecture overview
- [Implementation Checklist](../IMPLEMENTATION_CHECKLIST.md) - Deployment checklist

## 🔄 Common Operations

### Scale Cluster

```bash
# Edit terraform.tfvars
# node_group_desired_size = 5

# Apply changes
terraform apply -auto-approve
```

### Update Kubernetes Version

```bash
# Edit terraform.tfvars
# kubernetes_version = "1.29"

# Apply changes (will take 10-15 minutes)
terraform apply -auto-approve
```

### Change Instance Type

```bash
# Edit terraform.tfvars
# node_instance_types = ["t3.large", "t3.xlarge"]

# Drain old nodes
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Apply changes
terraform apply -auto-approve
```

### Destroy Infrastructure

```bash
# WARNING: This will delete everything!
cd infrastructure/terraform
./deploy.sh destroy
```

## ✅ Validation Checklist

Run the validation script:

```bash
bash infrastructure/validate-setup.sh
```

This checks:
- All infrastructure files present
- Terraform configurations valid
- ArgoCD files present
- Kustomize overlays valid
- Documentation complete

## 🚀 Next Steps After Deployment

1. **Configure kubectl** - `aws eks update-kubeconfig ...`
2. **Access ArgoCD** - Port forward and login
3. **Add GitHub repo** - `argocd repo add ...`
4. **Deploy apps** - `kubectl apply -f infrastructure/argocd/...`
5. **Monitor** - Watch pods: `kubectl get pods -n nova-staging -w`
6. **Configure CI/CD** - Set GitHub OIDC provider ARN in terraform.tfvars
7. **Build images** - Trigger GitHub Actions to build and push images
8. **Verify services** - Test health checks and connectivity

## 📞 Support

- **Issues**: GitHub Issues
- **Documentation**: See `/docs/` directory
- **Questions**: Team Slack channel
- **Runbooks**: See troubleshooting section above

## 📄 License

Same as Nova project

---

**Last Updated**: 2025-11-06
**Maintained By**: DevOps Team
**Status**: Production Ready ✅
