#!/bin/bash

##############################################################################
# PgBouncer Load Testing Runner
#
# Purpose: Simplify running k6 load tests with pre-configured scenarios
#
# Usage:
#   ./run-tests.sh baseline    # Baseline test (50 VUs, 5 min)
#   ./run-tests.sh validate    # PgBouncer validation (50 VUs, 5 min)
#   ./run-tests.sh stress      # Stress test (200 VUs, 10 min)
#   ./run-tests.sh spike       # Spike test (50→500 VUs)
#   ./run-tests.sh endurance   # Endurance test (100 VUs, 1 hour)
#   ./run-tests.sh custom      # Custom parameters
##############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${BASE_URL:-http://localhost:4000}"
JWT_TOKEN="${JWT_TOKEN:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="${SCRIPT_DIR}/pgbouncer-load-test.js"

##############################################################################
# Helper Functions
##############################################################################

print_banner() {
  echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC}        PgBouncer Load Testing Suite                    ${GREEN}║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_error() {
  echo -e "${RED}❌ Error: $1${NC}" >&2
}

print_warning() {
  echo -e "${YELLOW}⚠️  Warning: $1${NC}"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
  echo -e "${GREEN}ℹ️  $1${NC}"
}

check_prerequisites() {
  print_info "Checking prerequisites..."

  # Check k6 installed
  if ! command -v k6 &> /dev/null; then
    print_error "k6 is not installed"
    echo ""
    echo "Install k6:"
    echo "  macOS:  brew install k6"
    echo "  Ubuntu: See https://k6.io/docs/getting-started/installation/"
    exit 1
  fi
  print_success "k6 installed: $(k6 version)"

  # Check kubectl installed
  if ! command -v kubectl &> /dev/null; then
    print_warning "kubectl is not installed (needed for port-forwarding)"
  else
    print_success "kubectl installed"
  fi

  # Check if test script exists
  if [[ ! -f "$TEST_SCRIPT" ]]; then
    print_error "Test script not found: $TEST_SCRIPT"
    exit 1
  fi
  print_success "Test script found"

  # Check JWT token
  if [[ -z "$JWT_TOKEN" ]]; then
    print_warning "JWT_TOKEN environment variable not set"
    echo ""
    echo "To set JWT token:"
    echo "  export JWT_TOKEN=\"your-jwt-token-here\""
    echo ""
    echo "Tests will run without authentication (may fail on protected endpoints)"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  else
    print_success "JWT token configured"
  fi

  # Check if GraphQL endpoint is accessible
  print_info "Checking GraphQL endpoint: $BASE_URL"
  if curl -s -f "$BASE_URL/health" > /dev/null 2>&1; then
    print_success "GraphQL endpoint is accessible"
  else
    print_warning "Cannot reach GraphQL endpoint at $BASE_URL"
    echo ""
    echo "Make sure port-forwarding is active:"
    echo "  kubectl port-forward -n nova svc/graphql-gateway 4000:4000"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi

  echo ""
}

print_test_info() {
  local test_name=$1
  local vus=$2
  local duration=$3

  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}Test Configuration:${NC}"
  echo -e "  Name:     ${YELLOW}${test_name}${NC}"
  echo -e "  VUs:      ${YELLOW}${vus}${NC}"
  echo -e "  Duration: ${YELLOW}${duration}${NC}"
  echo -e "  Base URL: ${YELLOW}${BASE_URL}${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

start_monitoring() {
  print_info "Monitoring URLs (open in browser):"
  echo ""
  echo "  Grafana Dashboards:"
  echo "    - PgBouncer:  http://localhost:3000/d/nova-pgbouncer"
  echo "    - Outbox:     http://localhost:3000/d/nova-outbox-pattern"
  echo "    - mTLS:       http://localhost:3000/d/nova-mtls-security"
  echo ""
  echo "  Prometheus Metrics:"
  echo "    - pgbouncer_pools_sv_active"
  echo "    - pgbouncer_pools_cl_active"
  echo "    - postgresql_connections"
  echo ""
  echo "  Port-forwarding commands:"
  echo "    kubectl port-forward -n nova svc/graphql-gateway 4000:4000"
  echo "    kubectl port-forward -n monitoring svc/grafana 3000:3000"
  echo "    kubectl port-forward -n monitoring svc/prometheus 9090:9090"
  echo ""
}

##############################################################################
# Test Scenarios
##############################################################################

run_baseline_test() {
  print_test_info "Baseline Test (Before PgBouncer)" "50" "5 minutes"
  print_info "This test establishes performance baseline with direct PostgreSQL connection"
  echo ""

  start_monitoring

  k6 run \
    --vus 50 \
    --duration 5m \
    --env BASE_URL="$BASE_URL" \
    --env JWT_TOKEN="$JWT_TOKEN" \
    "$TEST_SCRIPT"

  print_success "Baseline test completed!"
  echo ""
  echo "Save these results for comparison with PgBouncer-enabled tests."
}

run_validation_test() {
  print_test_info "PgBouncer Validation Test" "50" "5 minutes"
  print_info "This test validates PgBouncer performance improvements"
  echo ""

  start_monitoring

  k6 run \
    --vus 50 \
    --duration 5m \
    --env BASE_URL="$BASE_URL" \
    --env JWT_TOKEN="$JWT_TOKEN" \
    "$TEST_SCRIPT"

  print_success "Validation test completed!"
  echo ""
  echo "Compare these results with baseline:"
  echo "  - Backend connections should be 80% lower"
  echo "  - P95 latency should be 40% better"
  echo "  - Throughput should be 150% higher"
}

run_stress_test() {
  print_test_info "Stress Test (High Load)" "200" "10 minutes"
  print_info "This test validates PgBouncer under heavy load"
  echo ""

  start_monitoring

  k6 run \
    --vus 200 \
    --duration 10m \
    --env BASE_URL="$BASE_URL" \
    --env JWT_TOKEN="$JWT_TOKEN" \
    "$TEST_SCRIPT"

  print_success "Stress test completed!"
  echo ""
  echo "Check for:"
  echo "  - pgbouncer_pools_cl_waiting = 0 (no queueing)"
  echo "  - pgbouncer_pools_sv_active < 50 (stable pool)"
  echo "  - Error rate < 1%"
}

run_spike_test() {
  print_test_info "Spike Test (Traffic Surge)" "50→500 VUs" "7 minutes"
  print_info "This test simulates sudden traffic spikes"
  echo ""

  start_monitoring

  k6 run \
    --stage 1m:50,5m:500,1m:50 \
    --env BASE_URL="$BASE_URL" \
    --env JWT_TOKEN="$JWT_TOKEN" \
    "$TEST_SCRIPT"

  print_success "Spike test completed!"
  echo ""
  echo "Check for:"
  echo "  - Connection queueing during spike"
  echo "  - Backend connection count (should not exceed 50)"
  echo "  - Recovery time after spike"
}

run_endurance_test() {
  print_test_info "Endurance Test (Long-Running)" "100" "1 hour"
  print_info "This test validates stability over extended periods"
  echo ""

  print_warning "This test will run for 1 hour!"
  read -p "Continue? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
  fi

  start_monitoring

  k6 run \
    --vus 100 \
    --duration 1h \
    --env BASE_URL="$BASE_URL" \
    --env JWT_TOKEN="$JWT_TOKEN" \
    "$TEST_SCRIPT"

  print_success "Endurance test completed!"
  echo ""
  echo "Check for:"
  echo "  - Memory leaks"
  echo "  - Connection leaks"
  echo "  - Gradual latency increases"
}

run_custom_test() {
  echo ""
  read -p "Enter number of VUs: " vus
  read -p "Enter duration (e.g., 5m, 1h): " duration

  print_test_info "Custom Test" "$vus" "$duration"

  start_monitoring

  k6 run \
    --vus "$vus" \
    --duration "$duration" \
    --env BASE_URL="$BASE_URL" \
    --env JWT_TOKEN="$JWT_TOKEN" \
    "$TEST_SCRIPT"

  print_success "Custom test completed!"
}

##############################################################################
# Main Script
##############################################################################

print_banner

# Check prerequisites
check_prerequisites

# Parse command
TEST_TYPE="${1:-}"

case "$TEST_TYPE" in
  baseline)
    run_baseline_test
    ;;
  validate)
    run_validation_test
    ;;
  stress)
    run_stress_test
    ;;
  spike)
    run_spike_test
    ;;
  endurance)
    run_endurance_test
    ;;
  custom)
    run_custom_test
    ;;
  *)
    echo "Usage: $0 {baseline|validate|stress|spike|endurance|custom}"
    echo ""
    echo "Test Scenarios:"
    echo "  baseline   - Baseline test (50 VUs, 5 min)"
    echo "  validate   - PgBouncer validation (50 VUs, 5 min)"
    echo "  stress     - Stress test (200 VUs, 10 min)"
    echo "  spike      - Spike test (50→500 VUs)"
    echo "  endurance  - Endurance test (100 VUs, 1 hour)"
    echo "  custom     - Custom parameters"
    echo ""
    exit 1
    ;;
esac

echo ""
print_success "All tests completed successfully!"
echo ""
echo "Next steps:"
echo "  1. Review Grafana dashboards for detailed metrics"
echo "  2. Check Prometheus for raw metrics"
echo "  3. Compare results with baseline"
echo "  4. Adjust PgBouncer configuration if needed"
echo ""
