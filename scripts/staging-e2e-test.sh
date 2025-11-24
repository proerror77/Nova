#!/bin/bash
# Simplified E2E API Test for Staging Environment
# Compatible with bash 3.2+

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Config
GW_BASE="${GW_BASE:-http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com}"
AUTH_HEADER="Authorization: Bearer $TOKEN"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Helper: Print section header
section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Test helper
test_endpoint() {
    local name="$1"
    local method="$2"
    local endpoint="$3"
    local data="${4:-}"
    local expected_status="${5:-200}"
    local skip_auth="${6:-false}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -ne "  ${BLUE}[TEST]${NC} $name ... "

    local curl_cmd="curl -s -w %{http_code} -o $TEMP_DIR/response -X $method $GW_BASE$endpoint"

    if [[ "$skip_auth" != "true" ]]; then
        curl_cmd="$curl_cmd -H \"$AUTH_HEADER\""
    fi

    if [[ -n "$data" ]]; then
        curl_cmd="$curl_cmd -H 'Content-Type: application/json' -d '$data'"
    fi

    # Execute request
    local http_code=$(eval "$curl_cmd" 2>&1)

    # Check status
    if [[ "$http_code" == "$expected_status" ]]; then
        echo -e "${GREEN}✓ $http_code${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))

        # Show response
        if cat "$TEMP_DIR/response" | jq -e . >/dev/null 2>&1; then
            cat "$TEMP_DIR/response" | jq -C '.' | head -10
        else
            cat "$TEMP_DIR/response" | head -5
        fi
        return 0
    else
        echo -e "${RED}✗ $http_code (expected $expected_status)${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))

        echo -e "${RED}Response:${NC}"
        cat "$TEMP_DIR/response"
        echo ""
        return 1
    fi
}

# Main test suite
main() {
    section "Nova Staging E2E Test"
    echo "Gateway: $GW_BASE"
    echo "User ID: $USER_ID"
    echo "Token: ${TOKEN:0:30}..."
    echo ""

    # Health Checks (No Auth)
    section "1. Health Checks (No Auth)"
    test_endpoint "Basic health" GET "/health" "" "200" "true"
    test_endpoint "Circuit breakers" GET "/health/circuit-breakers" "" "200" "true"

    # User Profile
    section "2. User Profile (Auth Required)"
    test_endpoint "Get user profile" GET "/api/v2/users/$USER_ID"
    test_endpoint "Update profile" PUT "/api/v2/users/$USER_ID" '{"bio":"E2E Test User","location":"Taipei"}'

    # Channels
    section "3. Channels"
    test_endpoint "List channels" GET "/api/v2/channels?limit=5"

    # Invitations
    section "4. Invitations"
    test_endpoint "Generate invite" POST "/api/v2/invitations/generate"
    test_endpoint "List invitations" GET "/api/v2/invitations"
    test_endpoint "Get invite stats" GET "/api/v2/invitations/stats"

    # Friends & Social
    section "5. Friends & Social Graph"
    test_endpoint "Get friends list" GET "/api/v2/friends/list"
    test_endpoint "Search users" GET "/api/v2/search/users?q=test&limit=5"
    test_endpoint "Friend recommendations" GET "/api/v2/friends/recommendations?limit=5"

    # Group Chat
    section "6. Group Chat"
    test_endpoint "List conversations" GET "/api/v2/chat/conversations?limit=10"

    # Feed
    section "7. Feed"
    test_endpoint "Personalized feed" GET "/api/v2/feed?limit=10"
    test_endpoint "User feed" GET "/api/v2/feed/user/$USER_ID?limit=10"
    test_endpoint "Explore feed" GET "/api/v2/feed/explore?limit=10"
    test_endpoint "Trending feed" GET "/api/v2/feed/trending?limit=10"

    # Summary
    section "Test Summary"
    echo "Total:  $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo ""

    # Pass rate
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        echo -e "Pass Rate: ${CYAN}${pass_rate}%${NC}"
    fi

    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Prerequisites check
if [[ -z "${TOKEN:-}" ]]; then
    echo -e "${RED}Error: TOKEN not set${NC}"
    echo "Usage: export TOKEN=\"your_jwt_token\""
    exit 1
fi

if [[ -z "${USER_ID:-}" ]]; then
    echo -e "${RED}Error: USER_ID not set${NC}"
    echo "Usage: export USER_ID=\"your_user_uuid\""
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq not installed${NC}"
    echo "Install: brew install jq"
    exit 1
fi

# Run tests
main "$@"
