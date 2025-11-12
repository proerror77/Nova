#!/bin/bash
##############################################################################
# PgBouncer Performance Benchmark
# 
# Compares performance of:
# 1. Direct PostgreSQL connection (baseline)
# 2. Through PgBouncer (optimized)
# 
# Measures:
# - Transactions per second (TPS)
# - Latency (avg, min, max)
# - Performance overhead
#
# Usage:
#   ./benchmark.sh
#   PGBENCH_SCALE=100 ./benchmark.sh  # Larger dataset
#   PGBENCH_DURATION=120 ./benchmark.sh  # Longer test
##############################################################################

set -e

# Configuration
PGBENCH_SCALE=${PGBENCH_SCALE:-10}        # Dataset scale
PGBENCH_DURATION=${PGBENCH_DURATION:-60}  # Test duration (seconds)
PGBENCH_JOBS=${PGBENCH_JOBS:-4}          # Parallel jobs
PGBENCH_CLIENTS=${PGBENCH_CLIENTS:-50}   # Client connections

# PostgreSQL connection details
POSTGRES_HOST=${POSTGRES_HOST:-localhost}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
PGBOUNCER_HOST=${PGBOUNCER_HOST:-localhost}
PGBOUNCER_PORT=${PGBOUNCER_PORT:-6432}
DB_NAME=${DB_NAME:-nova}
DB_USER=${DB_USER:-nova_user}
DB_PASSWORD=${DB_PASSWORD:-password}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v psql &> /dev/null; then
        log_error "psql not found. Install PostgreSQL client tools."
        exit 1
    fi
    
    if ! command -v pgbench &> /dev/null; then
        log_error "pgbench not found. Install PostgreSQL tools."
        exit 1
    fi
    
    log_success "All tools available"
}

# Test connectivity
test_connectivity() {
    log_info "Testing database connectivity..."
    
    # Test PostgreSQL
    if psql "postgresql://${DB_USER}:${DB_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${DB_NAME}" \
        -c "SELECT version()" > /dev/null 2>&1; then
        log_success "PostgreSQL connection OK"
    else
        log_error "Cannot connect to PostgreSQL (${POSTGRES_HOST}:${POSTGRES_PORT})"
        return 1
    fi
    
    # Test PgBouncer
    if psql "postgresql://${DB_USER}:${DB_PASSWORD}@${PGBOUNCER_HOST}:${PGBOUNCER_PORT}/${DB_NAME}" \
        -c "SELECT version()" > /dev/null 2>&1; then
        log_success "PgBouncer connection OK"
    else
        log_error "Cannot connect to PgBouncer (${PGBOUNCER_HOST}:${PGBOUNCER_PORT})"
        return 1
    fi
}

# Initialize pgbench database
initialize_pgbench() {
    log_info "Initializing pgbench database (scale=$PGBENCH_SCALE)..."
    
    # Connect directly to PostgreSQL for initialization
    pgbench -i \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        -s "${PGBENCH_SCALE}" \
        > /dev/null 2>&1
    
    log_success "pgbench database initialized"
}

# Run benchmark
run_benchmark() {
    local host=$1
    local port=$2
    local label=$3
    local output_file=$4
    
    log_info "Running benchmark: ${label} (${host}:${port})"
    log_info "  - Duration: ${PGBENCH_DURATION} seconds"
    log_info "  - Clients: ${PGBENCH_CLIENTS}"
    log_info "  - Jobs: ${PGBENCH_JOBS}"
    
    pgbench \
        -h "${host}" \
        -p "${port}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        -c "${PGBENCH_CLIENTS}" \
        -j "${PGBENCH_JOBS}" \
        -T "${PGBENCH_DURATION}" \
        -r \
        > "${output_file}" 2>&1
    
    log_success "Benchmark completed: ${label}"
}

# Parse and display results
parse_results() {
    local file=$1
    local label=$2
    
    echo ""
    echo "=========================================="
    echo "Results: $label"
    echo "=========================================="
    
    # Extract key metrics
    local tps=$(grep "tps =" "${file}" | tail -1 | awk '{print $NF}' | head -c -3)
    local avg_latency=$(grep "average latency" "${file}" | awk '{print $NF}')
    local max_latency=$(grep "max latency" "${file}" | awk '{print $NF}')
    
    echo "Transactions per second (TPS): ${tps}"
    echo "Average latency: ${avg_latency} ms"
    echo "Max latency: ${max_latency} ms"
    echo ""
}

# Compare results
compare_results() {
    local postgres_file=$1
    local pgbouncer_file=$2
    
    # Extract TPS from both
    local postgres_tps=$(grep "tps =" "${postgres_file}" | tail -1 | awk '{print $NF}' | head -c -3 | xargs)
    local pgbouncer_tps=$(grep "tps =" "${pgbouncer_file}" | tail -1 | awk '{print $NF}' | head -c -3 | xargs)
    
    # Calculate difference
    local improvement=$(echo "scale=2; (${pgbouncer_tps} - ${postgres_tps}) / ${postgres_tps} * 100" | bc)
    
    echo ""
    echo "=========================================="
    echo "Comparison: PostgreSQL vs PgBouncer"
    echo "=========================================="
    echo "PostgreSQL TPS: ${postgres_tps}"
    echo "PgBouncer TPS: ${pgbouncer_tps}"
    echo "Improvement: ${improvement}%"
    echo ""
    
    if (( $(echo "${pgbouncer_tps} > ${postgres_tps}" | bc -l) )); then
        log_success "PgBouncer is ${improvement}% faster"
    else
        log_warn "PgBouncer is ${improvement}% slower (overhead)"
    fi
}

# Main execution
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  PgBouncer Performance Benchmark       ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    test_connectivity
    initialize_pgbench
    
    # Create temporary files for results
    local postgres_results="/tmp/pgbench_postgres_$$.txt"
    local pgbouncer_results="/tmp/pgbench_pgbouncer_$$.txt"
    
    # Test 1: Direct PostgreSQL
    echo ""
    run_benchmark "${POSTGRES_HOST}" "${POSTGRES_PORT}" "Direct PostgreSQL" "${postgres_results}"
    parse_results "${postgres_results}" "Direct PostgreSQL"
    
    # Sleep between tests
    log_info "Waiting 10 seconds before next test..."
    sleep 10
    
    # Test 2: Through PgBouncer
    echo ""
    run_benchmark "${PGBOUNCER_HOST}" "${PGBOUNCER_PORT}" "Through PgBouncer" "${pgbouncer_results}"
    parse_results "${pgbouncer_results}" "Through PgBouncer"
    
    # Compare
    compare_results "${postgres_results}" "${pgbouncer_results}"
    
    # Cleanup
    rm -f "${postgres_results}" "${pgbouncer_results}"
    
    echo "=========================================="
    echo "Benchmark completed successfully!"
    echo "=========================================="
}

# Run main
main "$@"
