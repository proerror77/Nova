#!/bin/bash

# Performance Testing Script for Message Search
# This script tests search latency, throughput, and memory usage
# Requirements: curl, jq, bc

set -e

# Configuration
API_BASE="${API_BASE:-http://localhost:8080}"
TOKEN="${TOKEN:-your-jwt-token}"
CONVERSATION_ID="${CONVERSATION_ID:-550e8400-e29b-41d4-a716-446655440000}"
NUM_TESTS="${NUM_TESTS:-100}"
QUERIES=("message" "hello" "test" "important" "update" "project" "meeting" "deadline")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize metrics
total_time=0
min_time=99999
max_time=0
success_count=0
error_count=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Message Search Performance Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Configuration:"
echo "  API Base: $API_BASE"
echo "  Conversation ID: $CONVERSATION_ID"
echo "  Number of Tests: $NUM_TESTS"
echo "  Test Queries: ${QUERIES[@]}"
echo ""

# Test function
test_search() {
    local query=$1
    local limit=${2:-20}
    local offset=${3:-0}
    local sort_by=${4:-recent}

    # Measure request time
    local start=$(date +%s%N)

    local response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "${API_BASE}/conversations/${CONVERSATION_ID}/messages/search?q=${query}&limit=${limit}&offset=${offset}&sort_by=${sort_by}")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)

    local end=$(date +%s%N)
    local elapsed=$(( (end - start) / 1000000 )) # Convert to ms

    if [ "$http_code" = "200" ]; then
        ((success_count++))
        return "$elapsed"
    else
        ((error_count++))
        echo -e "${RED}Error: HTTP $http_code${NC}"
        return 0
    fi
}

# Run search tests
echo -e "${YELLOW}Running search latency tests...${NC}"
echo ""

declare -a latencies

for i in $(seq 1 $NUM_TESTS); do
    # Pick random query
    query_index=$(( RANDOM % ${#QUERIES[@]} ))
    query="${QUERIES[$query_index]}"

    # Run test
    test_search "$query"
    latency=$?

    latencies+=($latency)

    # Update statistics
    total_time=$((total_time + latency))

    if [ $latency -lt $min_time ]; then
        min_time=$latency
    fi

    if [ $latency -gt $max_time ]; then
        max_time=$latency
    fi

    # Print progress
    if [ $((i % 10)) -eq 0 ]; then
        echo -ne "Completed: $i/$NUM_TESTS\r"
    fi
done

echo -ne "\n"

# Calculate statistics
if [ $success_count -gt 0 ]; then
    avg_time=$(echo "scale=2; $total_time / $success_count" | bc)
else
    avg_time=0
fi

# Calculate percentiles
IFS=$'\n' sorted=($(sort -n <<<"${latencies[*]}"))
unset IFS

p50_index=$(( (50 * NUM_TESTS) / 100 ))
p95_index=$(( (95 * NUM_TESTS) / 100 ))
p99_index=$(( (99 * NUM_TESTS) / 100 ))

p50=${sorted[$p50_index]:-0}
p95=${sorted[$p95_index]:-0}
p99=${sorted[$p99_index]:-0}

# Print results
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Search Performance Results${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo "Requests Summary:"
echo "  Total Requests: $NUM_TESTS"
echo "  Successful: $success_count"
echo "  Failed: $error_count"
echo "  Success Rate: $(echo "scale=1; $success_count * 100 / $NUM_TESTS" | bc)%"
echo ""

echo "Latency Statistics (ms):"
printf "  Min:        %6d ms\n" $min_time
printf "  Max:        %6d ms\n" $max_time
printf "  Average:    %6.2f ms\n" $avg_time
printf "  P50:        %6d ms\n" $p50
printf "  P95:        %6d ms\n" $p95
printf "  P99:        %6d ms\n" $p99
echo ""

# Performance assessment
echo "Performance Assessment:"

if [ $(echo "$p95 < 200" | bc) -eq 1 ]; then
    echo -e "  P95 Latency: ${GREEN}PASS${NC} (< 200ms)"
else
    echo -e "  P95 Latency: ${RED}FAIL${NC} (>= 200ms)"
fi

if [ $(echo "$avg_time < 100" | bc) -eq 1 ]; then
    echo -e "  Average Latency: ${GREEN}PASS${NC} (< 100ms)"
else
    echo -e "  Average Latency: ${YELLOW}WARN${NC} (>= 100ms)"
fi

if [ $error_count -eq 0 ]; then
    echo -e "  Error Rate: ${GREEN}PASS${NC} (0 errors)"
else
    echo -e "  Error Rate: ${RED}FAIL${NC} ($error_count errors)"
fi

echo ""

# Test pagination performance
echo -e "${YELLOW}Testing pagination performance...${NC}"
echo ""

pagination_times=()

for offset in 0 20 40 60 80 100; do
    start=$(date +%s%N)

    curl -s \
        -H "Authorization: Bearer $TOKEN" \
        "${API_BASE}/conversations/${CONVERSATION_ID}/messages/search?q=message&limit=20&offset=${offset}" > /dev/null

    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))

    pagination_times+=($elapsed)
    printf "  Offset %3d: %d ms\n" $offset $elapsed
done

# Test with different limits
echo ""
echo -e "${YELLOW}Testing with different page sizes...${NC}"
echo ""

for limit in 10 20 50 100; do
    start=$(date +%s%N)

    curl -s \
        -H "Authorization: Bearer $TOKEN" \
        "${API_BASE}/conversations/${CONVERSATION_ID}/messages/search?q=message&limit=${limit}&offset=0" > /dev/null

    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))

    printf "  Limit %3d: %d ms\n" $limit $elapsed
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Performance Test Complete${NC}"
echo -e "${BLUE}========================================${NC}"

# Exit with status based on P95 latency
if [ $(echo "$p95 < 200" | bc) -eq 1 ]; then
    exit 0
else
    exit 1
fi
