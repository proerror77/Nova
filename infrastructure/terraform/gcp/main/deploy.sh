#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}"
ENVIRONMENT="${1:-staging}"
ACTION="${2:-plan}"

# Validate inputs
if [[ ! "${ENVIRONMENT}" =~ ^(staging|production)$ ]]; then
    echo -e "${RED}Error: Environment must be 'staging' or 'production'${NC}"
    exit 1
fi

if [[ ! "${ACTION}" =~ ^(plan|apply|destroy)$ ]]; then
    echo -e "${RED}Error: Action must be 'plan', 'apply', or 'destroy'${NC}"
    exit 1
fi

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi
    log_success "Terraform $(terraform version | head -1)"

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud SDK is not installed"
        exit 1
    fi
    log_success "gcloud is installed"

    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    log_success "kubectl is installed"
}

# Initialize Terraform
init_terraform() {
    log_info "Initializing Terraform for ${ENVIRONMENT}..."
    cd "${TERRAFORM_DIR}"

    terraform init \
        -backend-config="bucket=nova-terraform-state" \
        -backend-config="prefix=gcp/${ENVIRONMENT}" \
        -upgrade

    log_success "Terraform initialized"
}

# Plan deployment
plan_deployment() {
    log_info "Planning Terraform deployment for ${ENVIRONMENT}..."
    cd "${TERRAFORM_DIR}"

    terraform plan \
        -var-file="terraform.tfvars.${ENVIRONMENT}" \
        -out="tfplan.${ENVIRONMENT}"

    log_success "Plan saved to tfplan.${ENVIRONMENT}"
}

# Apply deployment
apply_deployment() {
    log_info "Applying Terraform deployment for ${ENVIRONMENT}..."
    cd "${TERRAFORM_DIR}"

    # Confirm with user
    read -p "Are you sure you want to apply changes to ${ENVIRONMENT}? (yes/no): " confirmation
    if [[ "${confirmation}" != "yes" ]]; then
        log_warning "Deployment cancelled"
        exit 0
    fi

    terraform apply "tfplan.${ENVIRONMENT}"

    log_success "Deployment completed for ${ENVIRONMENT}"

    # Get kubeconfig
    log_info "Updating kubeconfig..."
    CLUSTER_NAME=$(terraform output -raw gke_cluster_name)
    GCP_PROJECT=$(terraform output -raw project_number 2>/dev/null || echo "$(gcloud config get-value project)")
    GCP_REGION=$(grep "^gcp_region" terraform.tfvars.${ENVIRONMENT} | awk -F'"' '{print $2}')

    gcloud container clusters get-credentials "${CLUSTER_NAME}" \
        --region="${GCP_REGION}" \
        --project="${GCP_PROJECT}"

    log_success "kubeconfig updated"
}

# Destroy infrastructure
destroy_deployment() {
    log_warning "This will destroy all ${ENVIRONMENT} infrastructure!"
    read -p "Are you absolutely sure? Type '${ENVIRONMENT}' to confirm: " confirmation
    if [[ "${confirmation}" != "${ENVIRONMENT}" ]]; then
        log_warning "Destruction cancelled"
        exit 0
    fi

    log_info "Destroying Terraform deployment for ${ENVIRONMENT}..."
    cd "${TERRAFORM_DIR}"

    terraform destroy \
        -var-file="terraform.tfvars.${ENVIRONMENT}" \
        -auto-approve

    log_success "Infrastructure destroyed for ${ENVIRONMENT}"
}

# Validate GCP credentials
validate_gcp_auth() {
    log_info "Validating GCP authentication..."

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        log_error "Not authenticated with Google Cloud. Run: gcloud auth login"
        exit 1
    fi

    log_success "GCP authentication valid"
}

# Main execution
main() {
    log_info "Nova GCP Terraform Deployment Script"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "Action: ${ACTION}"

    check_prerequisites
    validate_gcp_auth
    init_terraform

    case "${ACTION}" in
        plan)
            plan_deployment
            ;;
        apply)
            plan_deployment
            apply_deployment
            ;;
        destroy)
            destroy_deployment
            ;;
    esac

    log_success "Done!"
}

# Run main
main
