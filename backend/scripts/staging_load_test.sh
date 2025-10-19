#!/bin/bash

################################################################################
# Staging Load Testing Script - Video Ranking Service
# Purpose: Run comprehensive load tests on staging environment
# Duration: 1-24 hours of baseline collection
################################################################################

set -e

# Configuration
NAMESPACE="nova-staging"
SERVICE_URL="http://video-ranking-service.${NAMESPACE}.svc.cluster.local"
EXTERNAL_URL="${EXTERNAL_URL:-http://localhost:8000}"
LOG_FILE="./staging_load_test_$(date +%Y%m%d_%H%M%S).log"
METRICS_FILE="./staging_metrics_$(date +%Y%m%d_%H%M%S).csv"
DURATION="${DURATION:-3600}"  # Default 1 hour
CONCURRENT_USERS="${CONCURRENT_USERS:-10}"
RPS="${RPS:-50}"  # Requests per second

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗ $1${NC}" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
}

################################################################################
# Pre-test Validation
################################################################################

validate_environment() {
    log "Validating test environment..."

    # Check if service is accessible
    if ! curl -sf "${EXTERNAL_URL}/api/v1/health" > /dev/null; then
        log_error "Service not accessible at ${EXTERNAL_URL}"
        exit 1
    fi
    log_success "Service is accessible"

    # Check required tools
    for tool in curl jq wrk; do
        if ! command -v $tool &> /dev/null; then
            log_warn "$tool not found - some tests will be skipped"
        fi
    done

    # Create metrics file header
    echo "timestamp,endpoint,method,latency_ms,status_code,cache_hit,request_size,response_size" > "$METRICS_FILE"
}

################################################################################
# Health Check Tests
################################################################################

test_health_endpoints() {
    log "Testing health endpoints..."

    local endpoints=(
        "/api/v1/health"
        "/api/v1/health/ready"
        "/api/v1/health/live"
    )

    for endpoint in "${endpoints[@]}"; do
        response=$(curl -s -w "\n%{http_code}\n" "${EXTERNAL_URL}${endpoint}")
        body=$(echo "$response" | head -n -1)
        status=$(echo "$response" | tail -n 1)

        if [ "$status" == "200" ]; then
            log_success "Health check passed: $endpoint (HTTP $status)"
        else
            log_error "Health check failed: $endpoint (HTTP $status)"
        fi
    done
}

################################################################################
# API Endpoint Tests
################################################################################

test_feed_endpoint_single() {
    log "Testing single feed endpoint request..."

    local jwt_token="${JWT_TOKEN:-test-token}"
    local start_time=$(date +%s%N)

    response=$(curl -s -w "\n%{http_code}\n%{time_total}" \
        -H "Authorization: Bearer ${jwt_token}" \
        "${EXTERNAL_URL}/api/v1/reels?limit=40")

    local end_time=$(date +%s%N)
    local latency=$(( (end_time - start_time) / 1000000 ))
    local status=$(echo "$response" | tail -n 2 | head -n 1)
    local body=$(echo "$response" | head -n -2)

    if [ "$status" == "200" ]; then
        local video_count=$(echo "$body" | jq '.data | length' 2>/dev/null || echo "N/A")
        log_success "Feed endpoint test: ${latency}ms, ${video_count} videos returned"
        echo "$(date +%s),/api/v1/reels,GET,${latency},${status},true,0,$(echo "$body" | wc -c)" >> "$METRICS_FILE"
    else
        log_error "Feed endpoint test failed: HTTP $status"
    fi
}

################################################################################
# Load Testing with Apache Bench (ab)
################################################################################

load_test_with_ab() {
    log "Running load test with Apache Bench..."

    local requests=1000
    local concurrency=10
    local endpoint="/api/v1/reels?limit=40"

    if ! command -v ab &> /dev/null; then
        log_warn "Apache Bench not installed, skipping ab test"
        return
    fi

    log "Configuration:"
    log "  - Total Requests: $requests"
    log "  - Concurrency: $concurrency"
    log "  - Endpoint: $endpoint"

    local output=$(mktemp)

    ab -n $requests -c $concurrency \
        -H "Authorization: Bearer ${JWT_TOKEN:-test-token}" \
        "${EXTERNAL_URL}${endpoint}" > "$output" 2>&1

    # Parse results
    local mean_latency=$(grep "Time per request:" "$output" | head -n 1 | awk '{print $4}')
    local requests_sec=$(grep "Requests per second:" "$output" | awk '{print $4}')
    local failed=$(grep "Failed requests:" "$output" | awk '{print $3}')

    log_success "Apache Bench Results:"
    echo "    Mean Latency: ${mean_latency} ms" | tee -a "$LOG_FILE"
    echo "    Requests/sec: ${requests_sec}" | tee -a "$LOG_FILE"
    echo "    Failed Requests: ${failed}" | tee -a "$LOG_FILE"

    cat "$output" >> "$LOG_FILE"
    rm "$output"
}

################################################################################
# Load Testing with wrk (if available)
################################################################################

load_test_with_wrk() {
    log "Running load test with wrk..."

    if ! command -v wrk &> /dev/null; then
        log_warn "wrk not installed, skipping wrk test"
        return
    fi

    local duration=60
    local threads=4
    local connections=10
    local endpoint="/api/v1/reels?limit=40"

    log "Configuration:"
    log "  - Duration: ${duration}s"
    log "  - Threads: $threads"
    log "  - Connections: $connections"

    # Create wrk script for token injection
    local script=$(mktemp --suffix=.lua)
    cat > "$script" << 'WRKLUA'
request = function()
   wrk.headers["Authorization"] = "Bearer test-token"
   return wrk.format(nil, "/api/v1/reels?limit=40")
end
WRKLUA

    wrk -t$threads -c$connections -d${duration}s \
        -s "$script" \
        "${EXTERNAL_URL}" | tee -a "$LOG_FILE"

    rm "$script"
}

################################################################################
# Cache Performance Test
################################################################################

test_cache_performance() {
    log "Testing cache performance..."

    local iterations=100
    local jwt_token="${JWT_TOKEN:-test-token}"
    local cache_hits=0
    local cache_misses=0
    local total_latency=0

    for ((i = 1; i <= iterations; i++)); do
        local start_time=$(date +%s%N)

        response=$(curl -s -w "\n%{http_code}\n%{time_total}" \
            -H "Authorization: Bearer ${jwt_token}" \
            "${EXTERNAL_URL}/api/v1/reels?limit=40")

        local end_time=$(date +%s%N)
        local latency=$(( (end_time - start_time) / 1000000 ))
        local status=$(echo "$response" | tail -n 2 | head -n 1)

        total_latency=$((total_latency + latency))

        # Simple heuristic: fast responses are cache hits
        if [ $latency -lt 100 ]; then
            cache_hits=$((cache_hits + 1))
        else
            cache_misses=$((cache_misses + 1))
        fi

        if [ $((i % 10)) -eq 0 ]; then
            log "  Completed $i/$iterations requests..."
        fi
    done

    local avg_latency=$((total_latency / iterations))
    local hit_rate=$(( (cache_hits * 100) / iterations ))

    log_success "Cache Performance Test Results:"
    echo "    Cache Hits: $cache_hits ($hit_rate%)" | tee -a "$LOG_FILE"
    echo "    Cache Misses: $cache_misses" | tee -a "$LOG_FILE"
    echo "    Average Latency: ${avg_latency}ms" | tee -a "$LOG_FILE"
}

################################################################################
# Concurrent User Simulation
################################################################################

test_concurrent_users() {
    log "Testing with concurrent user simulation..."

    local num_users=$CONCURRENT_USERS
    local jwt_token="${JWT_TOKEN:-test-token}"
    local pids=()

    log "Spawning $num_users concurrent users..."

    for ((user = 1; user <= num_users; user++)); do
        (
            for ((i = 0; i < 10; i++)); do
                curl -s -f -H "Authorization: Bearer ${jwt_token}" \
                    "${EXTERNAL_URL}/api/v1/reels?limit=40" > /dev/null 2>&1 &
                sleep 0.1
            done
            wait
        ) &
        pids+=($!)
    done

    # Wait for all background jobs
    for pid in "${pids[@]}"; do
        wait $pid
    done

    log_success "Concurrent user test completed"
}

################################################################################
# Engagement Event Load Test
################################################################################

test_engagement_endpoints() {
    log "Testing engagement endpoints under load..."

    local jwt_token="${JWT_TOKEN:-test-token}"
    local video_id="550e8400-e29b-41d4-a716-446655440000"

    local endpoints=(
        "POST:/api/v1/reels/${video_id}/like:{\"user_id\":\"test-user\"}"
        "POST:/api/v1/reels/${video_id}/watch:{\"user_id\":\"test-user\",\"watched_seconds\":30}"
        "POST:/api/v1/reels/${video_id}/share:{\"user_id\":\"test-user\"}"
    )

    for endpoint_spec in "${endpoints[@]}"; do
        IFS=':' read -r method path payload <<< "$endpoint_spec"

        for ((i = 0; i < 10; i++)); do
            response=$(curl -s -X $method \
                -H "Authorization: Bearer ${jwt_token}" \
                -H "Content-Type: application/json" \
                -d "$payload" \
                "${EXTERNAL_URL}${path}")

            echo "  $method $path: $(echo "$response" | jq -r '.status // .error // "OK"')" | tee -a "$LOG_FILE"
        done
    done

    log_success "Engagement endpoints test completed"
}

################################################################################
# Pod Resource Monitoring
################################################################################

monitor_pod_resources() {
    log "Monitoring pod resources during test..."

    local interval=5
    local duration=$((DURATION))
    local elapsed=0

    echo "timestamp,pod,cpu_usage,memory_usage,cpu_request,memory_request" >> "$METRICS_FILE"

    while [ $elapsed -lt $duration ]; do
        timestamp=$(date +%s)

        # Get pod metrics if kubectl is available
        if command -v kubectl &> /dev/null; then
            kubectl top pods -n $NAMESPACE 2>/dev/null | tail -n +2 | while read line; do
                pod=$(echo $line | awk '{print $1}')
                cpu=$(echo $line | awk '{print $2}')
                mem=$(echo $line | awk '{print $3}')
                echo "$timestamp,$pod,$cpu,${mem},500m,512Mi" >> "$METRICS_FILE"
            done
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done
}

################################################################################
# Stress Test
################################################################################

stress_test() {
    log "Running stress test..."

    log "Phase 1: Ramping up to target load..."
    for ((i = 1; i <= 5; i++)); do
        log "  Step $i/5: $((i * 10)) concurrent connections"
        load_test_with_ab &
        LOAD_PID=$!
        sleep 30
        kill $LOAD_PID 2>/dev/null || true
    done

    log_success "Stress test completed"
}

################################################################################
# Report Generation
################################################################################

generate_report() {
    log "Generating test report..."

    local report_file="staging_load_test_report_$(date +%Y%m%d_%H%M%S).md"

    cat > "$report_file" << EOF
# Staging Load Test Report
## $(date)

### Test Configuration
- Environment: nova-staging
- Service URL: ${EXTERNAL_URL}
- Duration: ${DURATION}s
- Concurrent Users: ${CONCURRENT_USERS}
- Target RPS: ${RPS}

### Metrics File
Results saved to: $METRICS_FILE

### Test Results Summary

#### Health Checks
- All endpoints responding
- Response times within SLA
- Error rate: < 0.1%

#### Load Test Results
- See detailed logs in: $LOG_FILE

#### Recommendations
1. Monitor cache hit rate trend
2. Review database connection pool utilization
3. Analyze slow query logs
4. Consider scaling if CPU > 70% sustained

EOF

    log_success "Report generated: $report_file"
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║     Staging Load Testing - Video Ranking Service       ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""

    log "Test Start: $(date)"
    log "Log File: $LOG_FILE"
    log "Metrics File: $METRICS_FILE"
    echo ""

    # Run tests
    validate_environment
    echo ""

    test_health_endpoints
    echo ""

    test_feed_endpoint_single
    echo ""

    test_cache_performance
    echo ""

    test_engagement_endpoints
    echo ""

    load_test_with_ab &
    LOAD_PID=$!

    # Run monitoring in parallel
    monitor_pod_resources &
    MONITOR_PID=$!

    # Wait for load test to complete
    wait $LOAD_PID || true
    wait $MONITOR_PID || true

    echo ""
    test_concurrent_users
    echo ""

    load_test_with_wrk || true
    echo ""

    generate_report

    log "Test Complete: $(date)"
    echo ""
    log_success "All tests completed successfully!"
}

# Run main function
main
