#!/bin/bash
# Nova Staging Smoke Test - Complete API Validation
# Usage:
#   export TOKEN="your_jwt_token"
#   export USER_ID="your_user_uuid"
#   ./scripts/staging-smoke-test.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Test helper
test_endpoint() {
    local name="$1"
    local method="$2"
    local endpoint="$3"
    local data="${4:-}"
    local expected_status="${5:-200}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -ne "  ${BLUE}[TEST]${NC} $name ... "

    local status_file="$TEMP_DIR/status"
    local response_file="$TEMP_DIR/response"

    if [[ -n "$data" ]]; then
        curl -s -w "%{http_code}" -o "$response_file" \
            -X "$method" "$GW_BASE$endpoint" \
            -H "$AUTH_HEADER" \
            -H "Content-Type: application/json" \
            -d "$data" > "$status_file" 2>&1
    else
        curl -s -w "%{http_code}" -o "$response_file" \
            -X "$method" "$GW_BASE$endpoint" \
            -H "$AUTH_HEADER" > "$status_file" 2>&1
    fi

    local http_code=$(cat "$status_file")

    if [[ "$http_code" =~ ^$expected_status ]]; then
        echo -e "${GREEN}✓ $http_code${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        cat "$response_file" | jq -C '.' 2>/dev/null || cat "$response_file"
        return 0
    else
        echo -e "${RED}✗ $http_code (expected $expected_status)${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        cat "$response_file"
        return 1
    fi
}

# Main test suite
main() {
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Nova Staging Smoke Test${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "Gateway: $GW_BASE"
    echo "User ID: $USER_ID"
    echo ""

    # 0. Health checks
    echo -e "\n${YELLOW}[0] Health Checks${NC}"
    curl -s "$GW_BASE/health" && echo -e "${GREEN}✓ Basic health${NC}" || echo -e "${RED}✗ Health check failed${NC}"

    # 1. Profile Settings
    echo -e "\n${YELLOW}[1] Profile Settings${NC}"
    test_endpoint "Get user profile" GET "/api/v2/users/$USER_ID" "" "200"
    test_endpoint "Update profile" PUT "/api/v2/users/$USER_ID" \
        '{"first_name":"Test","last_name":"User","bio":"Staging test","location":"Taipei"}' "200"
    test_endpoint "Request avatar upload URL" POST "/api/v2/users/avatar" \
        '{"file_name":"avatar.jpg","file_size":123456,"content_type":"image/jpeg"}' "200"

    # 2. Channels
    echo -e "\n${YELLOW}[2] Channels${NC}"
    test_endpoint "List channels" GET "/api/v2/channels?limit=5" "" "200"

    # Extract first channel ID for subsequent tests
    CHANNEL_ID=$(curl -s -H "$AUTH_HEADER" "$GW_BASE/api/v2/channels?limit=1" | jq -r '.[0].id // empty')
    if [[ -n "$CHANNEL_ID" ]]; then
        echo -e "  Using channel ID: ${BLUE}$CHANNEL_ID${NC}"
        test_endpoint "Get channel details" GET "/api/v2/channels/$CHANNEL_ID" "" "200"
        test_endpoint "Get user channels" GET "/api/v2/users/$USER_ID/channels" "" "200"
        test_endpoint "Subscribe to channel" POST "/api/v2/channels/subscribe" \
            "{\"channel_ids\":[\"$CHANNEL_ID\"]}" "200"
        test_endpoint "Unsubscribe from channel" DELETE "/api/v2/channels/unsubscribe" \
            "{\"channel_ids\":[\"$CHANNEL_ID\"]}" "200"
    else
        echo -e "  ${YELLOW}⚠ No channels found, skipping channel tests${NC}"
    fi

    # 3. Devices
    echo -e "\n${YELLOW}[3] Devices${NC}"
    test_endpoint "List devices" GET "/api/v2/devices" "" "200"
    test_endpoint "Get current device" GET "/api/v2/devices/current" "" "200"

    # 4. Invitations
    echo -e "\n${YELLOW}[4] Invitations${NC}"
    test_endpoint "Generate invitation code" POST "/api/v2/invitations/generate" "" "200"

    # 5. Friends & Search
    echo -e "\n${YELLOW}[5] Friends & Search${NC}"
    test_endpoint "Get friends list" GET "/api/v2/friends" "" "200"
    test_endpoint "Search users" GET "/api/v2/search/users?q=test&limit=5" "" "200"
    test_endpoint "Get friend recommendations" GET "/api/v2/friends/recommendations?limit=5" "" "200"

    # 6. Group Chat
    echo -e "\n${YELLOW}[6] Group Chat${NC}"

    # Get another user ID from search results for group creation
    OTHER_USER_ID=$(curl -s -H "$AUTH_HEADER" "$GW_BASE/api/v2/search/users?q=test&limit=1" | jq -r '.[0].id // empty')
    if [[ -n "$OTHER_USER_ID" && "$OTHER_USER_ID" != "$USER_ID" ]]; then
        echo -e "  Using other user ID: ${BLUE}$OTHER_USER_ID${NC}"
        test_endpoint "Create group chat" POST "/api/v2/chat/groups/create" \
            "{\"name\":\"Test Group\",\"member_ids\":[\"$USER_ID\",\"$OTHER_USER_ID\"],\"description\":\"Staging test group\"}" "200"

        # Extract conversation ID
        CONV_ID=$(curl -s -X POST "$GW_BASE/api/v2/chat/groups/create" \
            -H "$AUTH_HEADER" -H "Content-Type: application/json" \
            -d "{\"name\":\"Test Group 2\",\"member_ids\":[\"$USER_ID\",\"$OTHER_USER_ID\"]}" | jq -r '.conversation.id // empty')

        if [[ -n "$CONV_ID" ]]; then
            echo -e "  Using conversation ID: ${BLUE}$CONV_ID${NC}"
            test_endpoint "Get conversation details" GET "/api/v2/chat/conversations/$CONV_ID" "" "200"
            test_endpoint "Get messages" GET "/api/v2/chat/messages?conversation_id=$CONV_ID&limit=20" "" "200"
        fi
    else
        echo -e "  ${YELLOW}⚠ No other users found, skipping group chat tests${NC}"
    fi

    # 7. Media Upload (placeholder - needs actual file)
    echo -e "\n${YELLOW}[7] Media Upload${NC}"
    echo -e "  ${YELLOW}⚠ Media upload requires actual file, skipping for now${NC}"

    # 8. Alice (placeholder)
    echo -e "\n${YELLOW}[8] Alice AI Assistant${NC}"
    echo -e "  ${YELLOW}⚠ Alice is not yet implemented, expecting 404/503${NC}"
    test_endpoint "Alice status" GET "/api/v2/alice/status" "" "404|503" || true

    # Summary
    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Test Summary${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo -e "Total:  $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
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
    echo -e "${RED}Error: TOKEN environment variable is not set${NC}"
    echo "Usage: export TOKEN=\"your_jwt_token\" && $0"
    exit 1
fi

if [[ -z "${USER_ID:-}" ]]; then
    echo -e "${RED}Error: USER_ID environment variable is not set${NC}"
    echo "Usage: export USER_ID=\"your_user_uuid\" && $0"
    exit 1
fi

# Verify jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    echo "Install: brew install jq"
    exit 1
fi

main "$@"
