#!/usr/bin/env bash
# =============================================================================
# Nova Platform - Kubernetes Manifest Generator
# =============================================================================
# Generates Kubernetes deployment and service manifests for all microservices
#
# Usage:
#   ./generate-manifests.sh [OPTIONS] [ENVIRONMENT]
#
# Arguments:
#   ENVIRONMENT    Target environment (dev|staging|prod) [default: dev]
#
# Options:
#   -o, --output DIR    Output directory [default: k8s/]
#   --dry-run          Show what would be generated without creating files
#   --validate         Validate port assignments and manifest completeness
#   -h, --help         Show this help message
#   -v, --version      Show version information
#
# Examples:
#   ./generate-manifests.sh staging
#   ./generate-manifests.sh --dry-run prod
#   ./generate-manifests.sh --validate --output ./k8s-test
#
# Generated: 2025-11-12
# Version: 1.0.0
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly VERSION="1.0.0"
readonly DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}"
readonly DEFAULT_ENV="dev"

# Color codes for output
readonly COLOR_RESET='\033[0m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'

# Flags
DRY_RUN=false
VALIDATE_ONLY=false
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
ENVIRONMENT="${DEFAULT_ENV}"

# =============================================================================
# Service Configuration (14 microservices + 1 gateway)
# =============================================================================
# Format: service_name:http_port:grpc_port:tier:cpu_req:mem_req:cpu_lim:mem_lim
#
# Tier 1 (Core): Critical services, highest resources
# Tier 2 (Essential): Important services, medium resources
# Tier 3 (Supporting): Supporting services, standard resources

declare -a SERVICES=(
  # Tier 1: Core Services
  "identity-service:8081:9081:tier1:500m:512Mi:1000m:1Gi"
  "content-service:8082:9082:tier1:500m:512Mi:1000m:1Gi"

  # Tier 2: Essential Services
  "media-service:8083:9083:tier2:300m:256Mi:600m:512Mi"
  "social-service:8084:9084:tier2:300m:256Mi:600m:512Mi"
  "feed-service:8087:9087:tier2:400m:384Mi:800m:768Mi"
  "notification-service:8088:9088:tier2:300m:256Mi:600m:512Mi"
  "realtime-chat-service:8086:9086:tier2:400m:384Mi:800m:768Mi"

  # Tier 3: Supporting Services
  "graph-service:8091:9091:tier3:200m:256Mi:400m:512Mi"
  "analytics-service:8094:9094:tier3:200m:256Mi:400m:512Mi"
  "search-service:8085:9085:tier3:300m:256Mi:600m:512Mi"
  "ranking-service:8092:9092:tier3:200m:256Mi:400m:512Mi"
  "trust-safety-service:8095:9095:tier3:200m:256Mi:400m:512Mi"
  "feature-store:8096:9096:tier3:200m:256Mi:400m:512Mi"

  # Gateway (no gRPC port)
  "graphql-gateway:8000::gateway:500m:512Mi:1000m:1Gi"
)

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
  echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $*"
}

log_success() {
  echo -e "${COLOR_GREEN}✅${COLOR_RESET} $*"
}

log_error() {
  echo -e "${COLOR_RED}❌${COLOR_RESET} $*" >&2
}

log_warning() {
  echo -e "${COLOR_YELLOW}⚠️${COLOR_RESET}  $*"
}

log_dry_run() {
  echo -e "${COLOR_BLUE}[DRY-RUN]${COLOR_RESET} $*"
}

show_version() {
  cat <<EOF
Nova Kubernetes Manifest Generator
Version: ${VERSION}
Generated: $(date +"%Y-%m-%d")
EOF
}

show_help() {
  cat <<'EOF'
Usage: ./generate-manifests.sh [OPTIONS] [ENVIRONMENT]

Arguments:
  ENVIRONMENT    Target environment (dev|staging|prod) [default: dev]

Options:
  -o, --output DIR    Output directory [default: k8s/]
  --dry-run          Show what would be generated without creating files
  --validate         Validate port assignments and manifest completeness
  -h, --help         Show this help message
  -v, --version      Show version information

Examples:
  # Generate manifests for staging environment
  ./generate-manifests.sh staging

  # Dry-run for production
  ./generate-manifests.sh --dry-run prod

  # Validate port assignments
  ./generate-manifests.sh --validate

  # Custom output directory
  ./generate-manifests.sh --output ./custom-k8s staging

Service Port Convention:
  HTTP ports: 8080-8096
  gRPC ports: HTTP_PORT + 1000 (9080-9096)

Resource Tiers:
  Tier 1 (Core):       500m CPU / 512Mi RAM (limits: 1000m / 1Gi)
  Tier 2 (Essential):  300-400m CPU / 256-384Mi RAM
  Tier 3 (Supporting): 200-300m CPU / 256Mi RAM
  Gateway:             500m CPU / 512Mi RAM (limits: 1000m / 1Gi)
EOF
}

validate_environment() {
  local env="$1"
  case "${env}" in
    dev|staging|prod)
      return 0
      ;;
    *)
      log_error "Invalid environment: ${env}. Must be one of: dev, staging, prod"
      return 1
      ;;
  esac
}

validate_ports() {
  log_info "Validating port assignments..."

  local -A http_ports=()
  local -A grpc_ports=()
  local has_conflicts=false

  for service_config in "${SERVICES[@]}"; do
    IFS=':' read -r service http_port grpc_port tier _ <<< "${service_config}"

    # Check HTTP port conflicts
    if [[ -n "${http_ports[$http_port]:-}" ]]; then
      log_error "HTTP port conflict: ${http_port} used by both ${http_ports[$http_port]} and ${service}"
      has_conflicts=true
    else
      http_ports[$http_port]="${service}"
    fi

    # Check gRPC port conflicts (skip gateway which has no gRPC)
    if [[ -n "${grpc_port}" ]]; then
      if [[ -n "${grpc_ports[$grpc_port]:-}" ]]; then
        log_error "gRPC port conflict: ${grpc_port} used by both ${grpc_ports[$grpc_port]} and ${service}"
        has_conflicts=true
      else
        grpc_ports[$grpc_port]="${service}"
      fi

      # Validate port convention (gRPC = HTTP + 1000)
      local expected_grpc=$((http_port + 1000))
      if [[ "${grpc_port}" != "${expected_grpc}" ]]; then
        log_warning "Port convention violated: ${service} has gRPC ${grpc_port}, expected ${expected_grpc}"
      fi
    fi
  done

  if [[ "${has_conflicts}" == "true" ]]; then
    return 1
  fi

  log_success "Port validation passed (${#http_ports[@]} HTTP, ${#grpc_ports[@]} gRPC)"
  return 0
}

generate_deployment_manifest() {
  local service="$1"
  local http_port="$2"
  local grpc_port="$3"
  local tier="$4"
  local cpu_req="$5"
  local mem_req="$6"
  local cpu_lim="$7"
  local mem_lim="$8"

  local has_grpc=false
  [[ -n "${grpc_port}" ]] && has_grpc=true

  cat <<EOF
# Generated: $(date +"%Y-%m-%d %H:%M:%S")
# Environment: ${ENVIRONMENT}
# Service: ${service}
# Tier: ${tier}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${service}
  namespace: nova-backend
  labels:
    app: ${service}
    tier: ${tier}
    environment: ${ENVIRONMENT}
spec:
  replicas: $([[ "${ENVIRONMENT}" == "prod" ]] && echo "3" || echo "2")
  selector:
    matchLabels:
      app: ${service}
  template:
    metadata:
      labels:
        app: ${service}
        tier: ${tier}
        environment: ${ENVIRONMENT}
    spec:
      containers:
      - name: ${service}
        image: ghcr.io/nova-platform/${service}:latest
        imagePullPolicy: Always
        ports:
        - name: http
          containerPort: ${http_port}
          protocol: TCP
EOF

  if [[ "${has_grpc}" == "true" ]]; then
    cat <<EOF
        - name: grpc
          containerPort: ${grpc_port}
          protocol: TCP
EOF
  fi

  cat <<EOF
        env:
        - name: HTTP_PORT
          value: "${http_port}"
EOF

  if [[ "${has_grpc}" == "true" ]]; then
    cat <<EOF
        - name: GRPC_PORT
          value: "${grpc_port}"
EOF
  fi

  cat <<EOF
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: connection-url
        - name: REDIS_URL
          valueFrom:
            configMapKeyRef:
              name: redis-config
              key: url
        - name: KAFKA_BROKERS
          valueFrom:
            configMapKeyRef:
              name: kafka-config
              key: brokers
        - name: RUST_LOG
          value: "info"
        - name: APP_ENV
          value: "${ENVIRONMENT}"
        resources:
          requests:
            cpu: ${cpu_req}
            memory: ${mem_req}
          limits:
            cpu: ${cpu_lim}
            memory: ${mem_lim}
        livenessProbe:
          httpGet:
            path: /api/v1/health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /api/v1/health
            port: http
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
      restartPolicy: Always
EOF
}

generate_service_manifest() {
  local service="$1"
  local http_port="$2"
  local grpc_port="$3"
  local tier="$4"

  local has_grpc=false
  [[ -n "${grpc_port}" ]] && has_grpc=true

  cat <<EOF
# Generated: $(date +"%Y-%m-%d %H:%M:%S")
# Environment: ${ENVIRONMENT}
# Service: ${service}
apiVersion: v1
kind: Service
metadata:
  name: ${service}
  namespace: nova-backend
  labels:
    app: ${service}
    tier: ${tier}
    environment: ${ENVIRONMENT}
spec:
  type: ClusterIP
  selector:
    app: ${service}
  ports:
  - name: http
    port: ${http_port}
    targetPort: http
    protocol: TCP
EOF

  if [[ "${has_grpc}" == "true" ]]; then
    cat <<EOF
  - name: grpc
    port: ${grpc_port}
    targetPort: grpc
    protocol: TCP
EOF
  fi

  cat <<EOF
  sessionAffinity: None
EOF
}

process_service() {
  local service_config="$1"

  IFS=':' read -r service http_port grpc_port tier cpu_req mem_req cpu_lim mem_lim <<< "${service_config}"

  local base_dir="${OUTPUT_DIR}/base"
  local deployment_file="${base_dir}/${service}-deployment.yaml"
  local service_file="${base_dir}/${service}-service.yaml"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry_run "Would generate ${service}-deployment.yaml (HTTP:${http_port}${grpc_port:+, gRPC:${grpc_port}})"
    log_dry_run "Would generate ${service}-service.yaml"
    return 0
  fi

  # Create base directory if not exists
  mkdir -p "${base_dir}"

  # Generate deployment manifest
  if [[ -f "${deployment_file}" ]]; then
    log_warning "Skipping ${service}-deployment.yaml (already exists)"
  else
    generate_deployment_manifest "${service}" "${http_port}" "${grpc_port}" "${tier}" \
      "${cpu_req}" "${mem_req}" "${cpu_lim}" "${mem_lim}" > "${deployment_file}"
    log_success "Created ${service}-deployment.yaml"
  fi

  # Generate service manifest
  if [[ -f "${service_file}" ]]; then
    log_warning "Skipping ${service}-service.yaml (already exists)"
  else
    generate_service_manifest "${service}" "${http_port}" "${grpc_port}" "${tier}" > "${service_file}"
    log_success "Created ${service}-service.yaml"
  fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -v|--version)
        show_version
        exit 0
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --validate)
        VALIDATE_ONLY=true
        shift
        ;;
      -o|--output)
        OUTPUT_DIR="$2"
        shift 2
        ;;
      dev|staging|prod)
        ENVIRONMENT="$1"
        shift
        ;;
      *)
        log_error "Unknown argument: $1"
        echo ""
        show_help
        exit 1
        ;;
    esac
  done

  # Validate environment
  if ! validate_environment "${ENVIRONMENT}"; then
    exit 1
  fi

  # Run validation
  if ! validate_ports; then
    log_error "Port validation failed"
    exit 1
  fi

  # Exit if validate-only mode
  if [[ "${VALIDATE_ONLY}" == "true" ]]; then
    log_success "Validation complete - all checks passed"
    exit 0
  fi

  # Print header
  log_info "Nova Kubernetes Manifest Generator v${VERSION}"
  log_info "Environment: ${ENVIRONMENT}"
  log_info "Output directory: ${OUTPUT_DIR}"
  [[ "${DRY_RUN}" == "true" ]] && log_info "Mode: DRY RUN (no files will be created)"
  echo ""

  # Process all services
  local total_services=${#SERVICES[@]}
  local processed=0

  for service_config in "${SERVICES[@]}"; do
    process_service "${service_config}"
    processed=$((processed + 1))
  done

  echo ""
  log_success "Processed ${processed}/${total_services} services"

  if [[ "${DRY_RUN}" == "false" ]]; then
    log_info "Manifests generated in: ${OUTPUT_DIR}/base/"
    log_info "Next steps:"
    echo "  1. Review generated manifests"
    echo "  2. Update kustomization.yaml to include new resources"
    echo "  3. Apply with: kubectl apply -k ${OUTPUT_DIR}/overlays/${ENVIRONMENT}"
  fi
}

# Trap errors
trap 'log_error "Script failed on line $LINENO"' ERR

# Run main
main "$@"
