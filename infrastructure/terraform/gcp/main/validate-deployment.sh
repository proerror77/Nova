#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENVIRONMENT="${1:-staging}"
NAMESPACE="nova-${ENVIRONMENT}"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Validation checks
check_cluster_health() {
    log_info "Checking GKE cluster health..."

    # Get cluster name and region
    CLUSTER_NAME=$(kubectl config current-context | cut -d'_' -f4)
    if [[ -z "${CLUSTER_NAME}" ]]; then
        log_error "Could not determine cluster name from context"
        return 1
    fi

    # Check nodes
    NODES=$(kubectl get nodes --no-headers | wc -l)
    if [[ ${NODES} -gt 0 ]]; then
        log_success "Cluster has ${NODES} nodes"
    else
        log_error "No nodes found in cluster"
        return 1
    fi

    # Check nodes status
    READY_NODES=$(kubectl get nodes --no-headers | grep -c "Ready" || true)
    if [[ ${READY_NODES} -eq ${NODES} ]]; then
        log_success "All nodes are Ready"
    else
        log_warning "${NODES} total nodes, ${READY_NODES} Ready"
        return 1
    fi
}

check_cloud_sql() {
    log_info "Checking Cloud SQL connectivity..."

    NAMESPACE="nova-${ENVIRONMENT}"

    # Check if database secret exists
    if kubectl get secret nova-db-credentials -n "${NAMESPACE}" &>/dev/null; then
        log_success "Database credentials secret found"
    else
        log_warning "Database credentials secret not found (will be synced by cron)"
    fi

    # Try to get connection string from terraform output
    DB_HOST=$(terraform output -raw cloud_sql_private_ip 2>/dev/null || echo "N/A")
    if [[ "${DB_HOST}" != "N/A" ]]; then
        log_success "Cloud SQL private IP: ${DB_HOST}"
    fi
}

check_redis() {
    log_info "Checking Memorystore Redis connectivity..."

    NAMESPACE="nova-${ENVIRONMENT}"

    # Check if redis secret exists
    if kubectl get secret nova-redis-connection -n "${NAMESPACE}" &>/dev/null; then
        log_success "Redis connection secret found"
    else
        log_warning "Redis connection secret not found (will be synced by cron)"
    fi

    # Try to get redis host from terraform output
    REDIS_HOST=$(terraform output -raw redis_host 2>/dev/null || echo "N/A")
    if [[ "${REDIS_HOST}" != "N/A" ]]; then
        log_success "Redis host: ${REDIS_HOST}"
    fi
}

check_artifact_registry() {
    log_info "Checking Artifact Registry..."

    ARTIFACT_URL=$(terraform output -raw artifact_registry_url 2>/dev/null || echo "N/A")
    if [[ "${ARTIFACT_URL}" != "N/A" ]]; then
        log_success "Artifact Registry URL: ${ARTIFACT_URL}"

        # Check authentication
        if gcloud auth configure-docker "${ARTIFACT_URL%%/*}" 2>/dev/null; then
            log_success "Docker authentication configured"
        else
            log_warning "Docker authentication needs setup"
        fi
    fi
}

check_service_accounts() {
    log_info "Checking service accounts..."

    # Check GitHub Actions service account
    GH_SA=$(terraform output -raw github_actions_service_account 2>/dev/null || echo "N/A")
    if [[ "${GH_SA}" != "N/A" ]]; then
        log_success "GitHub Actions service account: ${GH_SA}"
    fi

    # Check K8s workloads service account
    K8S_SA=$(terraform output -raw k8s_workloads_service_account 2>/dev/null || echo "N/A")
    if [[ "${K8S_SA}" != "N/A" ]]; then
        log_success "K8s workloads service account: ${K8S_SA}"
    fi
}

check_workload_identity() {
    log_info "Checking Workload Identity configuration..."

    # Check Workload Identity Pool
    WIP=$(terraform output -raw workload_identity_pool_resource_name 2>/dev/null || echo "N/A")
    if [[ "${WIP}" != "N/A" ]]; then
        log_success "Workload Identity Pool: ${WIP}"
    fi

    # Check for test secret
    if kubectl get secret -n "${NAMESPACE}" 2>/dev/null | grep -q nova; then
        log_success "K8s secrets found in namespace"
    else
        log_warning "No K8s secrets found yet (may be synced by cron)"
    fi
}

create_namespace() {
    log_info "Creating Kubernetes namespace if needed..."

    if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_success "Namespace '${NAMESPACE}' exists"
    else
        log_info "Creating namespace '${NAMESPACE}'..."
        kubectl create namespace "${NAMESPACE}"
        log_success "Namespace created"
    fi
}

create_service_account() {
    log_info "Creating Kubernetes service account for Workload Identity..."

    if kubectl get serviceaccount k8s-workloads -n "${NAMESPACE}" &>/dev/null; then
        log_success "Service account 'k8s-workloads' exists"
        return
    fi

    # Get K8s service account email from terraform
    K8S_SA=$(terraform output -raw k8s_workloads_service_account 2>/dev/null || echo "")
    if [[ -z "${K8S_SA}" ]]; then
        log_warning "Could not get K8s service account from terraform"
        return
    fi

    kubectl create serviceaccount k8s-workloads -n "${NAMESPACE}" || true

    # Add Workload Identity annotation
    kubectl annotate serviceaccount k8s-workloads \
        -n "${NAMESPACE}" \
        "iam.gke.io/gcp-service-account=${K8S_SA}" \
        --overwrite

    log_success "Service account configured with Workload Identity"
}

run_health_check() {
    log_info "Running health check pod..."

    # Create a simple test pod to verify connectivity
    kubectl run health-check \
        --image=gcr.io/google.com/cloudsdktool/cloud-sdk:slim \
        --rm -it \
        -n "${NAMESPACE}" \
        --serviceaccount=k8s-workloads \
        --restart=Never \
        -- gcloud projects describe --format="value(projectId)" &>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "Health check pod ran successfully"
    else
        log_warning "Health check pod test inconclusive"
    fi
}

generate_summary() {
    log_info "Generating deployment summary..."

    cat > "${ENVIRONMENT}-deployment-summary.txt" <<EOF
=================================================
Nova GCP Deployment Summary - ${ENVIRONMENT}
=================================================
Date: $(date)

Cluster Information:
  Cluster Name: $(kubectl config current-context | cut -d'_' -f4 || echo "N/A")
  Namespace: ${NAMESPACE}

Resources:
  GKE Cluster: $(terraform output -raw gke_cluster_name 2>/dev/null || echo "N/A")
  Cloud SQL: $(terraform output -raw cloud_sql_instance_name 2>/dev/null || echo "N/A")
  Redis: $(terraform output -raw redis_host 2>/dev/null || echo "N/A")
  Artifact Registry: $(terraform output -raw artifact_registry_url 2>/dev/null || echo "N/A")

Service Accounts:
  GitHub Actions: $(terraform output -raw github_actions_service_account 2>/dev/null || echo "N/A")
  K8s Workloads: $(terraform output -raw k8s_workloads_service_account 2>/dev/null || echo "N/A")

Next Steps:
  1. Deploy microservices: kubectl apply -k k8s/overlays/${ENVIRONMENT}
  2. Configure secrets: kubectl apply -f k8s/secrets/
  3. Verify deployments: kubectl get deployments -n ${NAMESPACE}
  4. Check logs: kubectl logs -n ${NAMESPACE} -l app=<service-name>

=================================================
EOF

    log_success "Summary saved to ${ENVIRONMENT}-deployment-summary.txt"
    cat "${ENVIRONMENT}-deployment-summary.txt"
}

# Main execution
main() {
    log_info "Nova GCP Deployment Validation"
    log_info "Environment: ${ENVIRONMENT}"

    check_cluster_health || true
    create_namespace
    create_service_account || true
    check_cloud_sql || true
    check_redis || true
    check_artifact_registry || true
    check_service_accounts || true
    check_workload_identity || true
    generate_summary

    log_success "Validation completed!"
}

# Run main
main
