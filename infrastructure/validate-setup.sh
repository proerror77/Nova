#!/bin/bash

# ============================================================================
# Nova Infrastructure Validation Script
# ============================================================================
# Validates that all required infrastructure files are in place

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Utility Functions
# ============================================================================

check_file() {
    local file=$1
    local description=$2

    if [ -f "${PROJECT_ROOT}/${file}" ]; then
        echo -e "${GREEN}✓${NC} ${description}"
        return 0
    else
        echo -e "${RED}✗${NC} Missing: ${description} (${file})"
        return 1
    fi
}

check_directory() {
    local dir=$1
    local description=$2

    if [ -d "${PROJECT_ROOT}/${dir}" ]; then
        echo -e "${GREEN}✓${NC} ${description}"
        return 0
    else
        echo -e "${RED}✗${NC} Missing: ${description} (${dir})"
        return 1
    fi
}

check_file_executable() {
    local file=$1
    local description=$2

    if [ -x "${PROJECT_ROOT}/${file}" ]; then
        echo -e "${GREEN}✓${NC} ${description} (executable)"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Warning: ${description} is not executable (${file})"
        # Make it executable
        chmod +x "${PROJECT_ROOT}/${file}" 2>/dev/null || true
        return 0
    fi
}

# ============================================================================
# Main Validation
# ============================================================================

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Nova Infrastructure Validation${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

ERRORS=0

# Check Terraform files
echo -e "${BLUE}Checking Terraform Configuration...${NC}"
check_file "infrastructure/terraform/main.tf" "Terraform main configuration" || ((ERRORS++))
check_file "infrastructure/terraform/variables.tf" "Terraform variables" || ((ERRORS++))
check_file "infrastructure/terraform/outputs.tf" "Terraform outputs" || ((ERRORS++))
check_file "infrastructure/terraform/terraform.tfvars.example" "Terraform variables example" || ((ERRORS++))
check_file "infrastructure/terraform/.gitignore" "Terraform .gitignore" || ((ERRORS++))
check_file "infrastructure/terraform/deploy.sh" "Terraform deployment script" || ((ERRORS++))
check_file_executable "infrastructure/terraform/deploy.sh" "Deploy script executable"
echo ""

# Check Terraform modules
echo -e "${BLUE}Checking Terraform Modules...${NC}"
check_directory "infrastructure/terraform/modules/vpc" "VPC module" || ((ERRORS++))
check_directory "infrastructure/terraform/modules/eks" "EKS module" || ((ERRORS++))
check_directory "infrastructure/terraform/modules/ecr" "ECR module" || ((ERRORS++))
check_directory "infrastructure/terraform/modules/iam" "IAM module" || ((ERRORS++))
check_directory "infrastructure/terraform/modules/addons" "Add-ons module" || ((ERRORS++))

check_file "infrastructure/terraform/modules/vpc/main.tf" "VPC main" || ((ERRORS++))
check_file "infrastructure/terraform/modules/eks/main.tf" "EKS main" || ((ERRORS++))
check_file "infrastructure/terraform/modules/ecr/main.tf" "ECR main" || ((ERRORS++))
check_file "infrastructure/terraform/modules/iam/main.tf" "IAM main" || ((ERRORS++))
check_file "infrastructure/terraform/modules/addons/main.tf" "Add-ons main" || ((ERRORS++))
echo ""

# Check ArgoCD files
echo -e "${BLUE}Checking ArgoCD Configuration...${NC}"
check_file "infrastructure/argocd/nova-staging-app.yaml" "ArgoCD staging application" || ((ERRORS++))
check_file "infrastructure/argocd/nova-production-app.yaml" "ArgoCD production application" || ((ERRORS++))
check_file "infrastructure/argocd/README.md" "ArgoCD documentation" || ((ERRORS++))
echo ""

# Check Kustomize files
echo -e "${BLUE}Checking Kustomize Configuration...${NC}"
check_file "k8s/kustomization.yaml" "Root Kustomization" || ((ERRORS++))
check_file "k8s/base/kustomization.yaml" "Base Kustomization" || ((ERRORS++))
check_file "k8s/overlays/staging/kustomization.yaml" "Staging overlay" || ((ERRORS++))
check_file "k8s/overlays/production/kustomization.yaml" "Production overlay" || ((ERRORS++))
echo ""

# Check documentation
echo -e "${BLUE}Checking Documentation...${NC}"
check_file "DEPLOYMENT_GUIDE.md" "Deployment guide" || ((ERRORS++))
check_file "QUICKSTART.md" "Quick start guide" || ((ERRORS++))
check_file "INFRASTRUCTURE_SUMMARY.md" "Infrastructure summary" || ((ERRORS++))
check_file "IMPLEMENTATION_CHECKLIST.md" "Implementation checklist" || ((ERRORS++))
check_file "infrastructure/terraform/README.md" "Terraform README" || ((ERRORS++))
echo ""

# Check GitHub Actions
echo -e "${BLUE}Checking GitHub Actions...${NC}"
check_file ".github/workflows/ecr-build-push.yml" "ECR build and push workflow" || ((ERRORS++))
check_file ".github/workflows/integration-tests.yml" "Integration tests workflow" || ((ERRORS++))
echo ""

# ============================================================================
# Summary
# ============================================================================

echo -e "${BLUE}================================================${NC}"

if [ ${ERRORS} -eq 0 ]; then
    echo -e "${GREEN}✓ All infrastructure files are in place!${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Review and update terraform.tfvars:"
    echo "     cd infrastructure/terraform"
    echo "     cp terraform.tfvars.example terraform.tfvars"
    echo "     # Edit terraform.tfvars with your configuration"
    echo ""
    echo "  2. Deploy infrastructure:"
    echo "     ./deploy.sh apply"
    echo ""
    echo "  3. Configure kubectl:"
    echo "     aws eks update-kubeconfig --region ap-northeast-1 --name nova-eks"
    echo ""
    echo "  4. Deploy applications:"
    echo "     kubectl apply -f infrastructure/argocd/nova-staging-app.yaml"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Found ${ERRORS} missing files or issues${NC}"
    echo ""
    echo -e "${YELLOW}Please review the errors above and ensure all files are present.${NC}"
    exit 1
fi
