#!/bin/bash
# ============================================================================
# Neo4j Migration Script
# ============================================================================
# Purpose: Migrate PostgreSQL social graph data to Neo4j
# Usage: ./scripts/neo4j-migrate.sh [command]
# Commands: check | stats | backfill | verify | clear
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check if in correct directory
    if [ ! -f "$PROJECT_ROOT/backend/graph-service/Cargo.toml" ]; then
        log_error "Must be run from project root"
        exit 1
    fi

    log_success "Prerequisites OK"
}

# Get environment
get_environment() {
    NAMESPACE="${NAMESPACE:-nova-staging}"
    log_info "Using namespace: $NAMESPACE"

    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace $NAMESPACE does not exist"
        exit 1
    fi
}

# Get database credentials from Kubernetes secrets
get_credentials() {
    log_info "Fetching database credentials from Kubernetes..."

    # Get credentials from graph-service-secret
    export DATABASE_URL=$(kubectl get secret -n "$NAMESPACE" graph-service-secret \
        -o jsonpath='{.data.DATABASE_URL}' | base64 --decode)

    # Neo4j credentials
    export NEO4J_URI="bolt://neo4j:7687"
    export NEO4J_USER=$(kubectl get secret -n "$NAMESPACE" graph-service-secret \
        -o jsonpath='{.data.NEO4J_USER}' | base64 --decode)
    export NEO4J_PASSWORD=$(kubectl get secret -n "$NAMESPACE" graph-service-secret \
        -o jsonpath='{.data.NEO4J_PASSWORD}' | base64 --decode)

    if [ -z "$DATABASE_URL" ] || [ -z "$NEO4J_PASSWORD" ]; then
        log_error "Failed to fetch credentials"
        exit 1
    fi

    log_success "Credentials loaded"
}

# Build migration binary
build_binary() {
    log_info "Building neo4j-migrate binary..."

    cd "$PROJECT_ROOT/backend/graph-service"

    if ! cargo build --release --bin neo4j-migrate; then
        log_error "Build failed"
        exit 1
    fi

    BINARY_PATH="$PROJECT_ROOT/backend/target/release/neo4j-migrate"

    if [ ! -f "$BINARY_PATH" ]; then
        log_error "Binary not found at $BINARY_PATH"
        exit 1
    fi

    log_success "Binary built: $BINARY_PATH"
}

# Run migration command via kubectl exec
run_via_kubectl() {
    local command=$1
    log_info "Running '$command' via kubectl exec on graph-service pod..."

    # Find graph-service pod
    local pod=$(kubectl get pods -n "$NAMESPACE" -l app=graph-service -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        log_error "graph-service pod not found"
        exit 1
    fi

    log_info "Using pod: $pod"

    # Copy binary to pod
    log_info "Copying binary to pod..."
    kubectl cp "$BINARY_PATH" "$NAMESPACE/$pod:/tmp/neo4j-migrate"

    # Execute migration
    log_info "Executing migration..."
    kubectl exec -n "$NAMESPACE" "$pod" -- /tmp/neo4j-migrate "$command"
}

# Run migration command locally (port-forward)
run_locally() {
    local command=$1
    log_info "Running '$command' locally with port forwarding..."

    # Start port forwarding in background
    log_info "Setting up port forwarding..."

    # Forward PostgreSQL
    kubectl port-forward -n "$NAMESPACE" svc/postgres 5432:5432 &
    PG_PID=$!

    # Forward Neo4j
    kubectl port-forward -n "$NAMESPACE" svc/neo4j 7687:7687 &
    NEO4J_PID=$!

    # Wait for port forwarding
    sleep 3

    # Trap to cleanup port forwarding on exit
    trap "kill $PG_PID $NEO4J_PID 2>/dev/null || true" EXIT

    # Update connection strings for local access
    export DATABASE_URL=$(echo "$DATABASE_URL" | sed 's/@[^/]*/@localhost/')
    export NEO4J_URI="bolt://localhost:7687"

    log_info "Port forwarding established"

    # Run migration
    "$BINARY_PATH" "$command"

    log_success "Migration completed"
}

# Main execution
main() {
    local command=${1:-help}

    log_info "==================================="
    log_info "Neo4j Migration Tool"
    log_info "==================================="

    case "$command" in
        check|stats|backfill|verify|clear)
            check_prerequisites
            get_environment
            get_credentials
            build_binary

            # Ask execution method
            echo ""
            log_info "Choose execution method:"
            echo "  1) Run via kubectl exec (in-cluster)"
            echo "  2) Run locally with port forwarding"
            read -p "Select [1-2]: " method

            case "$method" in
                1)
                    run_via_kubectl "$command"
                    ;;
                2)
                    run_locally "$command"
                    ;;
                *)
                    log_error "Invalid selection"
                    exit 1
                    ;;
            esac
            ;;

        help|*)
            echo ""
            echo "Usage: ./scripts/neo4j-migrate.sh [command]"
            echo ""
            echo "Commands:"
            echo "  check      - Check database connections"
            echo "  stats      - Show database statistics"
            echo "  backfill   - Migrate data from PostgreSQL to Neo4j"
            echo "  verify     - Verify data consistency"
            echo "  clear      - Clear all Neo4j data (WARNING: destructive)"
            echo "  help       - Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  NAMESPACE  - Kubernetes namespace (default: nova-staging)"
            echo ""
            echo "Examples:"
            echo "  ./scripts/neo4j-migrate.sh check"
            echo "  ./scripts/neo4j-migrate.sh stats"
            echo "  NAMESPACE=nova-prod ./scripts/neo4j-migrate.sh backfill"
            echo ""
            ;;
    esac
}

main "$@"
