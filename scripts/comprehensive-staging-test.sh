#!/bin/bash
# Comprehensive Staging E2E Test & Review
# Tests all critical endpoints and generates detailed report

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Config
GW_BASE="${GW_BASE:-http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com}"
HOST_HEADER="Host: api.nova.local"
AUTH_HEADER="Authorization: Bearer $TOKEN"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Results storage
FAILED_ENDPOINTS=()
SLOW_ENDPOINTS=()

# Helper: Print section header
section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Test helper with timing
test_endpoint() {
    local name="$1"
    local method="$2"
    local endpoint="$3"
    local data="${4:-}"
    local expected_status="${5:-200}"
    local skip_auth="${6:-false}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -ne "  ${BLUE}[TEST]${NC} $name ... "

    local start_time=$(date +%s%3N)

    # Build curl command
    local curl_cmd="curl -s -w '%{http_code}|%{time_total}' -o $TEMP_DIR/response -X $method"
    curl_cmd="$curl_cmd -H '$HOST_HEADER'"

    if [[ "$skip_auth" != "true" ]]; then
        curl_cmd="$curl_cmd -H '$AUTH_HEADER'"
    fi

    if [[ -n "$data" ]]; then
        curl_cmd="$curl_cmd -H 'Content-Type: application/json' -d '$data'"
    fi

    curl_cmd="$curl_cmd '$GW_BASE$endpoint'"

    # Execute request
    local result=$(eval "$curl_cmd" 2>&1)
    local http_code=$(echo "$result" | cut -d'|' -f1)
    local response_time=$(echo "$result" | cut -d'|' -f2)
    local response_time_ms=$(echo "$response_time * 1000" | bc | cut -d'.' -f1)

    # Check status
    if [[ "$http_code" == "$expected_status" ]]; then
        if [[ $response_time_ms -gt 2000 ]]; then
            echo -e "${YELLOW}✓ $http_code (${response_time_ms}ms - SLOW)${NC}"
            SLOW_ENDPOINTS+=("$name: ${response_time_ms}ms")
            WARNINGS=$((WARNINGS + 1))
        elif [[ $response_time_ms -gt 1000 ]]; then
            echo -e "${GREEN}✓ $http_code (${response_time_ms}ms)${NC}"
        else
            echo -e "${GREEN}✓ $http_code (${response_time_ms}ms)${NC}"
        fi
        PASSED_TESTS=$((PASSED_TESTS + 1))

        # Show response (first 5 lines)
        if cat "$TEMP_DIR/response" | jq -e . >/dev/null 2>&1; then
            cat "$TEMP_DIR/response" | jq -C '.' | head -5
        else
            cat "$TEMP_DIR/response" | head -3
        fi
        return 0
    else
        echo -e "${RED}✗ $http_code (expected $expected_status, ${response_time_ms}ms)${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_ENDPOINTS+=("$name: HTTP $http_code")

        echo -e "${RED}Response:${NC}"
        cat "$TEMP_DIR/response" | head -10
        echo ""
        return 1
    fi
}

# Main test suite
main() {
    section "Nova Staging Comprehensive E2E Test & Review"
    echo "Gateway: $GW_BASE"
    echo "Host Header: $HOST_HEADER"
    echo "User ID: $USER_ID"
    echo "Token: ${TOKEN:0:30}..."
    echo "Test Start: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    #===============================================
    # 1. Infrastructure Health (No Auth)
    #===============================================
    section "1. Infrastructure Health Checks (No Auth)"

    test_endpoint "Basic health check" GET "/health" "" "200" "true"
    test_endpoint "Circuit breaker status" GET "/health/circuit-breakers" "" "200" "true"

    #===============================================
    # 2. Authentication & User Profile
    #===============================================
    section "2. Authentication & User Management"

    test_endpoint "Get user profile" GET "/api/v2/users/$USER_ID"
    test_endpoint "Update user profile" PUT "/api/v2/users/$USER_ID" \
        '{"bio":"E2E Test User - Automated Testing","location":"Taipei, Taiwan"}'

    #===============================================
    # 3. Channels
    #===============================================
    section "3. Channel Management"

    test_endpoint "List all channels" GET "/api/v2/channels?limit=10"
    test_endpoint "Get user subscribed channels" GET "/api/v2/users/$USER_ID/channels"

    #===============================================
    # 4. Invitations
    #===============================================
    section "4. Invitation System"

    test_endpoint "Generate invitation code" POST "/api/v2/invitations/generate"
    test_endpoint "List user invitations" GET "/api/v2/invitations"
    test_endpoint "Get invitation statistics" GET "/api/v2/invitations/stats"

    #===============================================
    # 5. Social Graph
    #===============================================
    section "5. Social Graph & Friends"

    test_endpoint "Get friends list" GET "/api/v2/friends/list"
    test_endpoint "Search users" GET "/api/v2/search/users?q=test&limit=10"
    test_endpoint "Friend recommendations" GET "/api/v2/friends/recommendations?limit=10"

    #===============================================
    # 6. Messaging & Chat
    #===============================================
    section "6. Messaging & Group Chat"

    test_endpoint "List conversations" GET "/api/v2/chat/conversations?limit=20"

    #===============================================
    # 7. Content Feed
    #===============================================
    section "7. Content Feed System"

    test_endpoint "Personalized feed" GET "/api/v2/feed?limit=20"
    test_endpoint "User-specific feed" GET "/api/v2/feed/user/$USER_ID?limit=20"
    test_endpoint "Explore feed" GET "/api/v2/feed/explore?limit=20"
    test_endpoint "Trending content feed" GET "/api/v2/feed/trending?limit=20"

    #===============================================
    # 8. Pod & Service Health
    #===============================================
    section "8. Backend Services Health Check"

    echo -e "${MAGENTA}[INFO]${NC} Checking Kubernetes pod status..."
    kubectl get pods -n nova-staging --no-headers 2>/dev/null | while read pod rest; do
        status=$(echo $rest | awk '{print $2}')
        if [[ "$status" == "Running" ]]; then
            echo -e "  ${GREEN}✓${NC} $pod: $status"
        else
            echo -e "  ${RED}✗${NC} $pod: $status"
            WARNINGS=$((WARNINGS + 1))
        fi
    done

    #===============================================
    # Summary & Report
    #===============================================
    section "Test Execution Summary"
    echo -e "Test End: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo -e "Total Tests:  ${CYAN}$TOTAL_TESTS${NC}"
    echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
    echo -e "Warnings:     ${YELLOW}$WARNINGS${NC}"
    echo ""

    # Calculate pass rate
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        if [[ $pass_rate -ge 90 ]]; then
            echo -e "Pass Rate: ${GREEN}${pass_rate}%${NC}"
        elif [[ $pass_rate -ge 70 ]]; then
            echo -e "Pass Rate: ${YELLOW}${pass_rate}%${NC}"
        else
            echo -e "Pass Rate: ${RED}${pass_rate}%${NC}"
        fi
    fi
    echo ""

    # Failed endpoints report
    if [[ ${#FAILED_ENDPOINTS[@]} -gt 0 ]]; then
        echo -e "${RED}Failed Endpoints:${NC}"
        for endpoint in "${FAILED_ENDPOINTS[@]}"; do
            echo -e "  ${RED}✗${NC} $endpoint"
        done
        echo ""
    fi

    # Slow endpoints report
    if [[ ${#SLOW_ENDPOINTS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Slow Endpoints (>2s):${NC}"
        for endpoint in "${SLOW_ENDPOINTS[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} $endpoint"
        done
        echo ""
    fi

    # Final verdict
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
        echo -e "${GREEN}========================================${NC}"
        return 0
    else
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}✗ SOME TESTS FAILED${NC}"
        echo -e "${RED}========================================${NC}"
        return 1
    fi
}

# Prerequisites check
if [[ -z "${TOKEN:-}" ]]; then
    echo -e "${RED}Error: TOKEN not set${NC}"
    exit 1
fi

if [[ -z "${USER_ID:-}" ]]; then
    echo -e "${RED}Error: USER_ID not set${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq not installed${NC}"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}Warning: bc not installed (response times will not be shown)${NC}"
fi

# Run tests
main "$@"
