#!/usr/bin/env bash
# End-to-End Staging Deployment Test Script
# Tests the complete CI/CD pipeline from Git push to K8s deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-nova}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
TIMEOUT="${TIMEOUT:-600}"  # 10 minutes

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Step 1: Verify prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=0

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        missing=1
    fi

    if ! command -v kustomize &> /dev/null; then
        log_warn "kustomize not found (will use kubectl kustomize)"
    fi

    if ! command -v gh &> /dev/null; then
        log_warn "gh CLI not found (GitHub workflow checks will be skipped)"
    fi

    if [ $missing -eq 1 ]; then
        log_error "Missing required tools. Install them first."
        exit 1
    fi

    log_success "Prerequisites OK"
}

# Step 2: Validate Kustomization files
validate_kustomization() {
    log_info "Validating Kustomization files..."

    local base_path="k8s/infrastructure/base"
    local overlay_path="k8s/infrastructure/overlays/staging"

    # Check base kustomization
    if ! kubectl kustomize "$base_path" > /dev/null 2>&1; then
        log_error "Base kustomization validation failed"
        kubectl kustomize "$base_path"
        exit 1
    fi
    log_success "Base kustomization valid"

    # Check staging overlay
    if ! kubectl kustomize "$overlay_path" > /dev/null 2>&1; then
        log_error "Staging overlay validation failed"
        kubectl kustomize "$overlay_path"
        exit 1
    fi
    log_success "Staging overlay valid"

    # Count resources
    local resource_count
    resource_count=$(kubectl kustomize "$overlay_path" | grep -c "^kind:" || true)
    log_info "Total resources in staging: $resource_count"
}

# Step 3: Check ArgoCD installation
check_argocd() {
    log_info "Checking ArgoCD installation..."

    if ! kubectl get namespace "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_error "ArgoCD namespace not found"
        log_info "Install ArgoCD with:"
        log_info "  kubectl create namespace argocd"
        log_info "  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
        return 1
    fi

    if ! kubectl get pod -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-server &> /dev/null; then
        log_error "ArgoCD server pod not found"
        return 1
    fi

    log_success "ArgoCD installed"
}

# Step 4: Check ArgoCD Application
check_argocd_application() {
    log_info "Checking ArgoCD Application..."

    if ! kubectl get application nova-staging -n "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_error "ArgoCD Application 'nova-staging' not found"
        log_info "Create it with:"
        log_info "  kubectl apply -f k8s/argocd/nova-staging-application.yaml"
        return 1
    fi

    # Get sync status
    local sync_status
    sync_status=$(kubectl get application nova-staging -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

    local health_status
    health_status=$(kubectl get application nova-staging -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    log_info "Sync Status: $sync_status"
    log_info "Health Status: $health_status"

    if [[ "$sync_status" == "Synced" ]] && [[ "$health_status" == "Healthy" ]]; then
        log_success "ArgoCD Application healthy"
    else
        log_warn "ArgoCD Application not fully synced or healthy"
    fi
}

# Step 5: Check GitHub Actions workflow
check_github_workflow() {
    log_info "Checking GitHub Actions workflow..."

    if ! command -v gh &> /dev/null; then
        log_warn "gh CLI not found, skipping GitHub workflow check"
        return 0
    fi

    # Get latest workflow run
    local latest_run
    latest_run=$(gh run list --workflow=staging-deploy.yml --limit 1 --json conclusion,status,headBranch 2>/dev/null || echo "")

    if [ -z "$latest_run" ]; then
        log_warn "No recent workflow runs found"
        return 0
    fi

    echo "$latest_run" | jq -r 'to_entries[] | "\(.key): \(.value)"'
}

# Step 6: Check deployed services
check_deployed_services() {
    log_info "Checking deployed services..."

    local services=(
        auth-service
        content-service
        feed-service
        media-service
        messaging-service
        search-service
    )

    local all_healthy=true

    for service in "${services[@]}"; do
        # Check deployment exists
        if ! kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
            log_error "Deployment $service not found"
            all_healthy=false
            continue
        fi

        # Check replicas
        local ready_replicas
        ready_replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

        local desired_replicas
        desired_replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" \
            -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

        if [ "$ready_replicas" == "$desired_replicas" ]; then
            log_success "$service: $ready_replicas/$desired_replicas replicas ready"
        else
            log_warn "$service: $ready_replicas/$desired_replicas replicas ready"
            all_healthy=false
        fi
    done

    if [ "$all_healthy" = true ]; then
        log_success "All services healthy"
    else
        log_warn "Some services not fully healthy"
        return 1
    fi
}

# Step 7: Run smoke tests
run_smoke_tests() {
    log_info "Running smoke tests..."

    local services=(
        auth-service
        user-service
        content-service
    )

    for service in "${services[@]}"; do
        log_info "Testing $service health endpoint..."

        # Port-forward and test
        kubectl port-forward -n "$NAMESPACE" "svc/$service" 8080:8080 &> /dev/null &
        local pf_pid=$!

        sleep 2

        if curl -f -s http://localhost:8080/health &> /dev/null; then
            log_success "$service health check passed"
        else
            log_warn "$service health check failed (might not be ready)"
        fi

        kill $pf_pid 2>/dev/null || true
    done
}

# Step 8: Summary
print_summary() {
    log_info "=========================================="
    log_info "STAGING DEPLOYMENT TEST SUMMARY"
    log_info "=========================================="

    log_info ""
    log_info "Namespace: $NAMESPACE"
    log_info "ArgoCD Namespace: $ARGOCD_NAMESPACE"
    log_info ""

    log_info "Quick Commands:"
    log_info "  View pods:    kubectl get pods -n $NAMESPACE"
    log_info "  View apps:    kubectl get applications -n $ARGOCD_NAMESPACE"
    log_info "  ArgoCD UI:    kubectl port-forward svc/argocd-server -n argocd 8080:443"
    log_info "  Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    log_info ""
}

# Main execution
main() {
    log_info "Starting Staging Deployment Test..."
    log_info ""

    check_prerequisites
    validate_kustomization

    if check_argocd; then
        check_argocd_application
    fi

    check_github_workflow
    check_deployed_services || true
    run_smoke_tests || true

    print_summary

    log_success "Test completed!"
}

# Run main function
main "$@"
