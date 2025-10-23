#!/bin/bash

# Test script for full-text search and Redis cache functionality
# Usage: ./test-fulltext-cache.sh

set -e

BASE_URL="http://localhost:8081"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "====================================="
echo "Full-Text Search & Cache Test Suite"
echo "====================================="
echo ""

# Function to test endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local description=$3
    local expected_status=$4

    echo -n "Testing: $description... "

    response=$(curl -s -w "\n%{http_code}" -X "$method" "$BASE_URL$endpoint")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)

    if [ "$http_code" -eq "$expected_status" ]; then
        echo -e "${GREEN}✓ PASS${NC} (HTTP $http_code)"
        if [ -n "$body" ] && [ "$body" != "{}" ]; then
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
        fi
    else
        echo -e "${RED}✗ FAIL${NC} (Expected $expected_status, got $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        return 1
    fi
    echo ""
}

# Function to measure response time
measure_time() {
    local method=$1
    local endpoint=$2
    local description=$3

    echo "Measuring: $description"
    start=$(date +%s%N)
    curl -s -X "$method" "$BASE_URL$endpoint" > /dev/null
    end=$(date +%s%N)
    duration=$(( (end - start) / 1000000 ))
    echo -e "${YELLOW}Response time: ${duration}ms${NC}"
    echo ""
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
test_endpoint GET "/health" "Service health check" 200

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Clear Cache (Baseline)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
test_endpoint POST "/api/v1/search/clear-cache" "Clear all search cache" 200

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Full-Text Search Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test 1: Empty query
test_endpoint GET "/api/v1/search/posts?q=" "Search with empty query" 200

# Test 2: Single word search
test_endpoint GET "/api/v1/search/posts?q=photo" "Search for 'photo'" 200

# Test 3: Multi-word search
test_endpoint GET "/api/v1/search/posts?q=awesome+photo" "Search for 'awesome photo'" 200

# Test 4: With limit parameter
test_endpoint GET "/api/v1/search/posts?q=test&limit=5" "Search with limit=5" 200

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Cache Performance Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Clear cache for accurate testing
curl -s -X POST "$BASE_URL/api/v1/search/clear-cache" > /dev/null

echo "First request (cache miss):"
measure_time GET "/api/v1/search/posts?q=beach" "Cache miss - database query"

echo "Second request (cache hit):"
measure_time GET "/api/v1/search/posts?q=beach" "Cache hit - Redis lookup"

echo "Third request (cache hit):"
measure_time GET "/api/v1/search/posts?q=beach" "Cache hit - Redis lookup"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. Cache Invalidation Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Populate cache with multiple queries
echo "Populating cache with test queries..."
curl -s "$BASE_URL/api/v1/search/posts?q=query1" > /dev/null
curl -s "$BASE_URL/api/v1/search/posts?q=query2" > /dev/null
curl -s "$BASE_URL/api/v1/search/posts?q=query3" > /dev/null
echo "Cache populated."
echo ""

# Clear cache
test_endpoint POST "/api/v1/search/clear-cache" "Clear cache after population" 200

# Verify cache was cleared (next request should be slow)
echo "Verifying cache was cleared (should see cache miss in logs):"
measure_time GET "/api/v1/search/posts?q=query1" "First request after cache clear"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. Other Search Endpoints"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
test_endpoint GET "/api/v1/search/users?q=john" "Search users" 200
test_endpoint GET "/api/v1/search/hashtags?q=travel" "Search hashtags" 200

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}All tests completed!${NC}"
echo ""
echo "Check service logs for cache hit/miss information:"
echo "  grep -E 'Cache (hit|miss)' <log-file>"
echo ""
echo "Redis monitoring:"
echo "  redis-cli --stat"
echo "  redis-cli INFO stats"
echo ""
