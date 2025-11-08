# 🚀 Pre-Deployment Checklist

Before deploying the Nova EKS infrastructure, ensure you have completed all items below.

## ✅ Prerequisites

### AWS Account & Credentials
- [ ] AWS Account created and active
- [ ] AWS credentials configured locally: `aws configure`
- [ ] Verified credentials: `aws sts get-caller-identity`
- [ ] AWS user has required IAM permissions (EC2, EKS, ECR, IAM, VPC, RDS, CloudWatch)
- [ ] AWS region set to `ap-northeast-1` (or modify in terraform.tfvars)

### Local Development Environment
- [ ] Terraform installed (v1.0+): `terraform --version`
- [ ] AWS CLI v2 installed: `aws --version`
- [ ] kubectl installed: `kubectl version --client`
- [ ] Git installed and configured: `git --version`
- [ ] Docker installed (for local image building): `docker --version`
- [ ] ArgoCD CLI installed (optional): `argocd --version`
- [ ] Kustomize installed (optional): `kustomize version`

### Repository Setup
- [ ] Nova repository cloned locally
- [ ] Current branch: `feature/phase1-grpc-migration` (or main)
- [ ] Repository has write access
- [ ] All uncommitted changes committed or stashed

### GitHub Configuration
- [ ] GitHub Personal Access Token created
  - [ ] Scopes: `repo`, `read:org`
  - [ ] Token saved securely
- [ ] GitHub repository owner is `proerror77`
- [ ] GitHub repository name is `Nova`
- [ ] Verify repository URL: `https://github.com/proerror77/Nova.git`

## 📋 Infrastructure Configuration

### Terraform Configuration
- [ ] Terraform directory exists: `infrastructure/terraform/`
- [ ] Copy template: `cp terraform.tfvars.example terraform.tfvars`
- [ ] Edit `terraform.tfvars` with your values:
  - [ ] `aws_region = "ap-northeast-1"`
  - [ ] `cluster_name = "nova-eks"` (must be unique)
  - [ ] `environment = "staging"`
  - [ ] `node_group_desired_size = 3` (or your preferred size)
  - [ ] `github_repo_owner = "proerror77"`
  - [ ] `github_repo_name = "Nova"`
  - [ ] `enable_monitoring = true`
  - [ ] `enable_logging = true`

### Validate Configuration
- [ ] Run validation script: `bash infrastructure/validate-setup.sh`
- [ ] All checks passed (✓ marks)
- [ ] All required files present

## 🏗️ Deployment Preparation

### Terraform Initialization
- [ ] Navigate to terraform directory: `cd infrastructure/terraform`
- [ ] Run: `./deploy.sh init`
- [ ] Terraform backend initialized
- [ ] `.terraform` directory created

### Terraform Validation
- [ ] Run: `./deploy.sh validate`
- [ ] No configuration errors

### Terraform Plan
- [ ] Run: `./deploy.sh plan`
- [ ] Review `tfplan` output
- [ ] Confirm resource creation (VPC, EKS, ECR, IAM, etc.)
- [ ] Verify node count and instance types
- [ ] Estimated cost acceptable (~$313/month)

## 🔐 Security Pre-Checks

### AWS Security
- [ ] AWS IAM user has minimum required permissions
- [ ] No hardcoded credentials in any files
- [ ] AWS credentials only in `~/.aws/credentials` (not in code)
- [ ] S3 bucket for Terraform state will be created
- [ ] DynamoDB table for state locking will be created

### GitHub Security
- [ ] GitHub token is temporary (not permanent)
- [ ] Token scopes are minimal (repo, read:org only)
- [ ] Token NOT committed to repository
- [ ] Token stored securely (1Password, secrets manager, etc.)

### Network Security
- [ ] VPC CIDR range acceptable (`10.0.0.0/16`)
- [ ] Understand multi-AZ setup (2 availability zones)
- [ ] NAT Gateway costs understood (~$45/month)
- [ ] Public and private subnet architecture understood

## 📊 Planning & Documentation

### Documentation Review
- [ ] Read `QUICKSTART.md` (5-minute guide)
- [ ] Read `DEPLOYMENT_GUIDE.md` (complete guide)
- [ ] Read `INFRASTRUCTURE_SUMMARY.md` (architecture overview)
- [ ] Understand 6-phase deployment in `IMPLEMENTATION_CHECKLIST.md`

### Team Coordination
- [ ] Team informed of deployment timing
- [ ] Maintenance window scheduled
- [ ] Runbook for incidents prepared
- [ ] On-call team assigned

### Backup & Recovery
- [ ] Current application state backed up
- [ ] Database backups enabled
- [ ] GitOps repository backed up
- [ ] Disaster recovery plan documented

## 💡 Optional Pre-Work

### Cost Optimization
- [ ] Reviewed cost optimization options (Spot Instances, node count, etc.)
- [ ] Decided on cost optimization strategy
- [ ] Updated terraform.tfvars accordingly (if needed)

### Monitoring & Observability
- [ ] Understood monitoring approach
- [ ] Prepared Slack/email for notifications
- [ ] Reviewed CloudWatch logs setup
- [ ] Prepared Prometheus/Grafana setup (optional)

### Custom Configuration
- [ ] Prepared any custom domain names (optional)
- [ ] Prepared SSL certificates (optional)
- [ ] Reviewed ingress configuration (optional)
- [ ] Prepared external DNS setup (optional)

## ✨ Ready to Deploy?

If all items above are checked ✓, you're ready to deploy!

### Deployment Command

```bash
cd infrastructure/terraform
./deploy.sh apply
```

This will:
1. Initialize Terraform
2. Validate configuration
3. Create and apply terraform plan
4. Deploy EKS cluster and all resources (~10-15 minutes)
5. Configure kubeconfig

### Expected Outputs

After successful deployment, you should see:
- 3 EKS nodes in "Ready" state
- ArgoCD running in `argocd` namespace
- 8 ECR repositories created
- ALB Controller running
- Metrics Server running
- Cert-Manager running (optional)

### Post-Deployment

After deployment, proceed with:
1. Configure kubectl: `aws eks update-kubeconfig --region ap-northeast-1 --name nova-eks`
2. Follow Phase 2 in `IMPLEMENTATION_CHECKLIST.md`

---

## 🛑 If Something Goes Wrong

### Before Redeploying
- [ ] Check error message in console
- [ ] Review troubleshooting section in `DEPLOYMENT_GUIDE.md`
- [ ] Check AWS CloudFormation events
- [ ] Review IAM permissions

### Rollback
- [ ] Destroy infrastructure: `./deploy.sh destroy`
- [ ] Fix configuration issues
- [ ] Redeploy: `./deploy.sh apply`

### Getting Help
- [ ] Check GitHub Issues
- [ ] Review Slack channel
- [ ] Contact DevOps team
- [ ] Consult AWS documentation

---

**Date Completed**: _______________
**Completed By**: _______________
**Notes/Issues**: _______________________________________________

---

Last Updated: 2025-11-06
