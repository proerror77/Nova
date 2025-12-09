#!/bin/bash
set -euo pipefail

# Matrix Synapse Deployment Script for Nova
# Usage: ./deploy-matrix-synapse.sh <environment> [server_name]
# Example: ./deploy-matrix-synapse.sh staging staging.nova.local

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="nova-backend"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check required tools
check_prerequisites() {
    log_info "Checking prerequisites..."

    command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is required but not installed."; exit 1; }
    command -v openssl >/dev/null 2>&1 || { log_error "openssl is required but not installed."; exit 1; }

    # Check cluster connection
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    log_info "Prerequisites OK"
}

# Generate random secrets
generate_secret() {
    openssl rand -base64 32 | tr -d '=/+' | cut -c1-32
}

# Create PostgreSQL database for Synapse
create_synapse_database() {
    log_info "Creating Synapse database..."

    local pg_password="$1"

    # Check if postgres pod exists
    local pg_pod=$(kubectl get pods -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [ -z "$pg_pod" ]; then
        log_warn "No postgres pod found in namespace $NAMESPACE"
        log_warn "Please create the synapse database manually:"
        echo ""
        echo "  CREATE DATABASE synapse ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' template=template0;"
        echo "  CREATE USER synapse WITH PASSWORD '<password>';"
        echo "  GRANT ALL PRIVILEGES ON DATABASE synapse TO synapse;"
        echo ""
        return 1
    fi

    # Create database and user
    kubectl exec -n "$NAMESPACE" "$pg_pod" -- psql -U postgres -c "
        SELECT 'CREATE DATABASE synapse ENCODING ''UTF8'' LC_COLLATE=''C'' LC_CTYPE=''C'' template=template0'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'synapse')\gexec
    " 2>/dev/null || true

    kubectl exec -n "$NAMESPACE" "$pg_pod" -- psql -U postgres -c "
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'synapse') THEN
                CREATE USER synapse WITH PASSWORD '$pg_password';
            END IF;
        END
        \$\$;
        GRANT ALL PRIVILEGES ON DATABASE synapse TO synapse;
    " 2>/dev/null || log_warn "Could not create synapse user (may already exist)"

    log_info "Database setup complete"
}

# Create secrets
create_secrets() {
    local server_name="$1"

    log_info "Creating Matrix Synapse secrets..."

    # Generate secrets
    local pg_password=$(generate_secret)
    local registration_secret=$(generate_secret)
    local macaroon_secret=$(generate_secret)
    local form_secret=$(generate_secret)

    # Create synapse secrets
    kubectl create secret generic matrix-synapse-secrets \
        -n "$NAMESPACE" \
        --from-literal=POSTGRES_PASSWORD="$pg_password" \
        --from-literal=REGISTRATION_SHARED_SECRET="$registration_secret" \
        --from-literal=MACAROON_SECRET_KEY="$macaroon_secret" \
        --from-literal=FORM_SECRET="$form_secret" \
        --dry-run=client -o yaml | kubectl apply -f -

    log_info "Secrets created"

    # Save registration secret for later use
    echo "$registration_secret" > /tmp/synapse_registration_secret.txt
    echo "$pg_password" > /tmp/synapse_pg_password.txt

    log_warn "Registration secret saved to /tmp/synapse_registration_secret.txt (delete after use)"

    # Try to create database
    create_synapse_database "$pg_password" || true
}

# Deploy Synapse
deploy_synapse() {
    local environment="$1"

    log_info "Deploying Matrix Synapse for environment: $environment"

    if [ "$environment" == "staging" ]; then
        kubectl apply -k "$K8S_DIR/overlays/staging"
    elif [ "$environment" == "prod" ]; then
        kubectl apply -k "$K8S_DIR/overlays/prod"
    else
        kubectl apply -k "$K8S_DIR/base"
    fi

    log_info "Waiting for Synapse to be ready..."
    kubectl rollout status deployment/matrix-synapse -n "$NAMESPACE" --timeout=300s

    log_info "Synapse deployed successfully"
}

# Register service account
register_service_account() {
    local server_name="$1"
    local registration_secret

    if [ -f /tmp/synapse_registration_secret.txt ]; then
        registration_secret=$(cat /tmp/synapse_registration_secret.txt)
    else
        log_error "Registration secret not found. Please provide it manually."
        read -sp "Enter registration shared secret: " registration_secret
        echo ""
    fi

    log_info "Registering nova-service account..."

    # Wait for Synapse to be fully ready
    sleep 10

    # Get Synapse pod
    local synapse_pod=$(kubectl get pods -n "$NAMESPACE" -l app=matrix-synapse -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$synapse_pod" ]; then
        log_error "Synapse pod not found"
        exit 1
    fi

    # Generate service account password
    local service_password=$(generate_secret)

    # Register the service user
    kubectl exec -n "$NAMESPACE" "$synapse_pod" -- \
        register_new_matrix_user \
        -u nova-service \
        -p "$service_password" \
        -a \
        -k "$registration_secret" \
        http://localhost:8008 2>/dev/null || {
            log_warn "User may already exist, attempting login instead..."
        }

    # Get access token by logging in
    log_info "Getting access token..."

    local login_response=$(kubectl exec -n "$NAMESPACE" "$synapse_pod" -- \
        curl -s -X POST http://localhost:8008/_matrix/client/v3/login \
        -H "Content-Type: application/json" \
        -d "{
            \"type\": \"m.login.password\",
            \"user\": \"nova-service\",
            \"password\": \"$service_password\",
            \"device_id\": \"NOVA_SERVICE_DEVICE\",
            \"initial_device_display_name\": \"Nova Realtime Chat Service\"
        }")

    local access_token=$(echo "$login_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$access_token" ]; then
        log_error "Failed to get access token. Response: $login_response"
        exit 1
    fi

    log_info "Access token obtained"

    # Create/update the service token secret
    kubectl create secret generic nova-matrix-service-token \
        -n "$NAMESPACE" \
        --from-literal=MATRIX_ACCESS_TOKEN="$access_token" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Update the main backend secrets to include the token
    log_info "Updating nova-backend-secrets with Matrix token..."

    # Patch existing secret or create if not exists
    kubectl patch secret nova-backend-secrets -n "$NAMESPACE" \
        --type='json' \
        -p="[{\"op\": \"add\", \"path\": \"/data/MATRIX_ACCESS_TOKEN\", \"value\": \"$(echo -n "$access_token" | base64)\"}]" 2>/dev/null || {
            log_warn "Could not patch nova-backend-secrets, creating nova-matrix-service-token instead"
        }

    log_info "Service account registered successfully!"
    echo ""
    echo "============================================"
    echo "Matrix Synapse Setup Complete!"
    echo "============================================"
    echo ""
    echo "Service User: @nova-service:$server_name"
    echo "Homeserver URL: http://matrix-synapse:8008"
    echo ""
    echo "Next steps:"
    echo "1. Update ConfigMap to set MATRIX_ENABLED=true"
    echo "2. Restart realtime-chat-service to pick up new config"
    echo ""
    echo "   kubectl set env deployment/realtime-chat-service -n $NAMESPACE MATRIX_ENABLED=true"
    echo "   kubectl rollout restart deployment/realtime-chat-service -n $NAMESPACE"
    echo ""

    # Cleanup temp files
    rm -f /tmp/synapse_registration_secret.txt /tmp/synapse_pg_password.txt
}

# Health check
health_check() {
    log_info "Running health check..."

    local synapse_pod=$(kubectl get pods -n "$NAMESPACE" -l app=matrix-synapse -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$synapse_pod" ]; then
        log_error "Synapse pod not found"
        return 1
    fi

    local health=$(kubectl exec -n "$NAMESPACE" "$synapse_pod" -- curl -s http://localhost:8008/health)

    if [ "$health" == "OK" ]; then
        log_info "Synapse is healthy"

        # Check federation disabled
        local well_known=$(kubectl exec -n "$NAMESPACE" "$synapse_pod" -- curl -s http://localhost:8008/.well-known/matrix/server 2>/dev/null || echo "disabled")
        log_info "Federation status: $well_known"

        return 0
    else
        log_error "Synapse health check failed: $health"
        return 1
    fi
}

# Main
main() {
    local environment="${1:-staging}"
    local server_name="${2:-${environment}.nova.local}"

    echo ""
    echo "=========================================="
    echo "Matrix Synapse Deployment for Nova"
    echo "=========================================="
    echo "Environment: $environment"
    echo "Server Name: $server_name"
    echo "Namespace: $NAMESPACE"
    echo ""

    check_prerequisites

    # Update ConfigMap with server name
    kubectl patch configmap nova-backend-config -n "$NAMESPACE" \
        --type='json' \
        -p="[{\"op\": \"replace\", \"path\": \"/data/MATRIX_SERVER_NAME\", \"value\": \"$server_name\"}]" 2>/dev/null || true

    create_secrets "$server_name"
    deploy_synapse "$environment"

    # Wait a bit for Synapse to fully initialize
    log_info "Waiting for Synapse to initialize..."
    sleep 30

    health_check
    register_service_account "$server_name"
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        echo "Usage: $0 <environment> [server_name]"
        echo ""
        echo "Arguments:"
        echo "  environment   Environment to deploy (staging, prod, or base)"
        echo "  server_name   Matrix server name (default: <environment>.nova.local)"
        echo ""
        echo "Examples:"
        echo "  $0 staging"
        echo "  $0 staging staging.nova.local"
        echo "  $0 prod chat.yourcompany.com"
        exit 0
        ;;
    health)
        check_prerequisites
        health_check
        ;;
    register)
        check_prerequisites
        register_service_account "${2:-nova.local}"
        ;;
    *)
        main "$@"
        ;;
esac
