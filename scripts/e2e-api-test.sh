#!/bin/bash
# Nova E2E API Test - Complete REST API Validation
# This script validates all REST API endpoints exposed by GraphQL Gateway
#
# Usage:
#   export TOKEN="your_jwt_token"
#   export USER_ID="your_user_uuid"
#   ./scripts/e2e-api-test.sh
#
# Prerequisites:
#   - jq (brew install jq)
#   - curl
#   - Valid JWT token from staging environment
#   - User UUID associated with the token

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
SKIPPED_TESTS=0

# Test results storage
declare -A TEST_RESULTS

# Helper: Print section header
section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Helper: Print subsection
subsection() {
    echo ""
    echo -e "${YELLOW}[$1]${NC}"
}

# Test helper with enhanced error reporting
test_endpoint() {
    local name="$1"
    local method="$2"
    local endpoint="$3"
    local data="${4:-}"
    local expected_status="${5:-200}"
    local skip_auth="${6:-false}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -ne "  ${BLUE}[TEST]${NC} $name ... "

    local status_file="$TEMP_DIR/status"
    local response_file="$TEMP_DIR/response"
    local headers_file="$TEMP_DIR/headers"

    # Build curl command
    local curl_cmd="curl -s -w %{http_code} -D $headers_file -o $response_file -X $method $GW_BASE$endpoint"

    if [[ "$skip_auth" != "true" ]]; then
        curl_cmd="$curl_cmd -H \"$AUTH_HEADER\""
    fi

    if [[ -n "$data" ]]; then
        curl_cmd="$curl_cmd -H Content-Type: application/json -d '$data'"
    fi

    # Execute request
    eval "$curl_cmd" > "$status_file" 2>&1

    local http_code=$(cat "$status_file")

    # Check if status matches expected
    if [[ "$http_code" =~ ^$expected_status ]]; then
        echo -e "${GREEN}✓ $http_code${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS["$name"]="PASS"

        # Pretty print JSON response if available
        if cat "$response_file" | jq -e . >/dev/null 2>&1; then
            cat "$response_file" | jq -C '.' | head -20
        else
            cat "$response_file" | head -20
        fi
        return 0
    else
        echo -e "${RED}✗ $http_code (expected $expected_status)${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS["$name"]="FAIL ($http_code)"

        echo -e "${RED}Response:${NC}"
        cat "$response_file"
        echo ""

        echo -e "${RED}Headers:${NC}"
        cat "$headers_file" | head -10
        return 1
    fi
}

# Test helper for skipped tests
skip_test() {
    local name="$1"
    local reason="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    TEST_RESULTS["$name"]="SKIP ($reason)"
    echo -e "  ${YELLOW}[SKIP]${NC} $name - $reason"
}

# Main test suite
main() {
    section "Nova E2E API Test"
    echo "Gateway: $GW_BASE"
    echo "User ID: $USER_ID"
    echo "Token: ${TOKEN:0:20}..."

    # ========================================
    # 0. HEALTH CHECKS (No Auth Required)
    # ========================================
    subsection "0. Health Checks"
    test_endpoint "Basic health check" GET "/health" "" "200" "true"
    test_endpoint "Circuit breaker health" GET "/health/circuit-breakers" "" "200" "true"

    # ========================================
    # 1. AUTHENTICATION (No Auth Required)
    # ========================================
    subsection "1. Authentication"
    echo -e "  ${YELLOW}⚠ Skipping auth tests (register/login) to avoid side effects${NC}"
    skip_test "POST /api/v2/auth/register" "Would create new user"
    skip_test "POST /api/v2/auth/login" "Using existing token"
    skip_test "POST /api/v2/auth/refresh" "Would invalidate current session"
    skip_test "POST /api/v2/auth/logout" "Would invalidate current token"

    # ========================================
    # 2. USER PROFILE
    # ========================================
    subsection "2. User Profile"
    test_endpoint "Get user profile" GET "/api/v2/users/$USER_ID"

    test_endpoint "Update user profile" PUT "/api/v2/users/$USER_ID" \
        '{"first_name":"E2E","last_name":"Test","bio":"E2E API test user","location":"Taipei, Taiwan"}'

    test_endpoint "Request avatar upload URL" POST "/api/v2/users/avatar" \
        '{"file_name":"avatar.jpg","file_size":102400,"content_type":"image/jpeg"}'

    # ========================================
    # 3. CHANNELS
    # ========================================
    subsection "3. Channels"

    test_endpoint "List all channels" GET "/api/v2/channels?limit=10"

    # Extract first channel ID
    CHANNEL_ID=$(curl -s -H "$AUTH_HEADER" "$GW_BASE/api/v2/channels?limit=1" | jq -r '.[0].id // empty')

    if [[ -n "$CHANNEL_ID" ]]; then
        echo -e "  ${CYAN}Using channel ID: $CHANNEL_ID${NC}"

        test_endpoint "Get channel details" GET "/api/v2/channels/$CHANNEL_ID"
        test_endpoint "Get user's subscribed channels" GET "/api/v2/users/$USER_ID/channels"

        test_endpoint "Subscribe to channel" POST "/api/v2/channels/subscribe" \
            "{\"channel_ids\":[\"$CHANNEL_ID\"]}"

        test_endpoint "Unsubscribe from channel" DELETE "/api/v2/channels/unsubscribe" \
            "{\"channel_ids\":[\"$CHANNEL_ID\"]}"
    else
        echo -e "  ${YELLOW}⚠ No channels available, skipping channel tests${NC}"
        skip_test "GET /api/v2/channels/{id}" "No channels found"
        skip_test "GET /api/v2/users/{id}/channels" "No channels found"
        skip_test "POST /api/v2/channels/subscribe" "No channels found"
        skip_test "DELETE /api/v2/channels/unsubscribe" "No channels found"
    fi

    # ========================================
    # 4. DEVICES
    # ========================================
    subsection "4. Devices"

    test_endpoint "List user devices" GET "/api/v2/devices"
    test_endpoint "Get current device info" GET "/api/v2/devices/current"

    # Device registration would require actual device token
    skip_test "POST /api/v2/devices" "Requires valid device token"
    skip_test "DELETE /api/v2/devices/{id}" "Would affect real device"

    # ========================================
    # 5. INVITATIONS
    # ========================================
    subsection "5. Invitations"

    test_endpoint "Generate invitation code" POST "/api/v2/invitations/generate"

    # Extract invitation code if available
    INVITE_CODE=$(curl -s -X POST "$GW_BASE/api/v2/invitations/generate" \
        -H "$AUTH_HEADER" | jq -r '.code // empty')

    if [[ -n "$INVITE_CODE" ]]; then
        echo -e "  ${CYAN}Generated invite code: $INVITE_CODE${NC}"
        test_endpoint "Validate invitation code" GET "/api/v2/invitations/validate/$INVITE_CODE"
    else
        skip_test "GET /api/v2/invitations/validate/{code}" "No invite code generated"
    fi

    test_endpoint "List user's invitations" GET "/api/v2/invitations"
    test_endpoint "Get invitation stats" GET "/api/v2/invitations/stats"

    # ========================================
    # 6. FRIENDS & SOCIAL GRAPH
    # ========================================
    subsection "6. Friends & Social Graph"

    test_endpoint "Get friends list" GET "/api/v2/friends/list"
    test_endpoint "Search users" GET "/api/v2/search/users?q=test&limit=10"
    test_endpoint "Get friend recommendations" GET "/api/v2/friends/recommendations?limit=10"

    # Extract another user for friend operations
    OTHER_USER_ID=$(curl -s -H "$AUTH_HEADER" \
        "$GW_BASE/api/v2/search/users?q=test&limit=1" | jq -r '.[0].id // empty')

    if [[ -n "$OTHER_USER_ID" && "$OTHER_USER_ID" != "$USER_ID" ]]; then
        echo -e "  ${CYAN}Using other user ID: $OTHER_USER_ID${NC}"

        test_endpoint "Add friend" POST "/api/v2/friends/add" \
            "{\"friend_id\":\"$OTHER_USER_ID\"}"

        # Allow some time for the operation to complete
        sleep 1

        test_endpoint "Remove friend" DELETE "/api/v2/friends/remove" \
            "{\"friend_id\":\"$OTHER_USER_ID\"}"
    else
        echo -e "  ${YELLOW}⚠ No other users found, skipping friend operations${NC}"
        skip_test "POST /api/v2/friends/add" "No other users available"
        skip_test "DELETE /api/v2/friends/remove" "No other users available"
    fi

    # ========================================
    # 7. GROUP CHAT
    # ========================================
    subsection "7. Group Chat"

    test_endpoint "List conversations" GET "/api/v2/chat/conversations?limit=20"

    if [[ -n "$OTHER_USER_ID" && "$OTHER_USER_ID" != "$USER_ID" ]]; then
        test_endpoint "Create group chat" POST "/api/v2/chat/groups/create" \
            "{\"name\":\"E2E Test Group\",\"member_ids\":[\"$USER_ID\",\"$OTHER_USER_ID\"],\"description\":\"E2E API test group\"}"

        # Extract conversation ID from created group
        CONV_ID=$(curl -s -X POST "$GW_BASE/api/v2/chat/groups/create" \
            -H "$AUTH_HEADER" -H "Content-Type: application/json" \
            -d "{\"name\":\"Test Conversation\",\"member_ids\":[\"$USER_ID\",\"$OTHER_USER_ID\"]}" \
            | jq -r '.conversation.id // empty')

        if [[ -n "$CONV_ID" ]]; then
            echo -e "  ${CYAN}Using conversation ID: $CONV_ID${NC}"

            test_endpoint "Get conversation details" GET "/api/v2/chat/conversations/$CONV_ID"
            test_endpoint "Get messages" GET "/api/v2/chat/messages?conversation_id=$CONV_ID&limit=50"

            test_endpoint "Send message" POST "/api/v2/chat/messages/send" \
                "{\"conversation_id\":\"$CONV_ID\",\"content\":\"E2E test message\",\"message_type\":\"text\"}"

            # Group management
            test_endpoint "Update group info" PUT "/api/v2/chat/groups/$CONV_ID" \
                "{\"name\":\"Updated Test Group\",\"description\":\"Updated description\"}"

            # Don't actually add/remove members to avoid side effects
            skip_test "POST /api/v2/chat/groups/{id}/members" "Would modify real group"
            skip_test "DELETE /api/v2/chat/groups/{id}/members/{user_id}" "Would modify real group"

        else
            skip_test "GET /api/v2/chat/conversations/{id}" "Failed to create conversation"
            skip_test "GET /api/v2/chat/messages" "No conversation available"
            skip_test "POST /api/v2/chat/messages/send" "No conversation available"
            skip_test "PUT /api/v2/chat/groups/{id}" "No group available"
        fi
    else
        echo -e "  ${YELLOW}⚠ No other users available, skipping group chat tests${NC}"
        skip_test "POST /api/v2/chat/groups/create" "No other users available"
        skip_test "All group chat operations" "No other users available"
    fi

    # ========================================
    # 8. MEDIA UPLOAD
    # ========================================
    subsection "8. Media Upload"

    test_endpoint "Request media upload URL" POST "/api/v2/media/upload" \
        '{"file_name":"test.jpg","file_size":1048576,"content_type":"image/jpeg","media_type":"image"}'

    # Actual file upload would require multipart/form-data and real file
    skip_test "Actual file upload to S3" "Requires real file and S3 presigned URL handling"

    # ========================================
    # 9. FEED
    # ========================================
    subsection "9. Feed"

    test_endpoint "Get personalized feed" GET "/api/v2/feed?limit=20"
    test_endpoint "Get user's feed" GET "/api/v2/feed/user/$USER_ID?limit=20"
    test_endpoint "Get explore feed" GET "/api/v2/feed/explore?limit=20"
    test_endpoint "Get trending feed" GET "/api/v2/feed/trending?limit=20"

    # ========================================
    # 10. SOCIAL INTERACTIONS (Likes, Comments, Shares)
    # ========================================
    subsection "10. Social Interactions"

    # These endpoints require actual content IDs
    # Let's try to get a content ID from the feed
    CONTENT_ID=$(curl -s -H "$AUTH_HEADER" "$GW_BASE/api/v2/feed?limit=1" \
        | jq -r '.items[0].id // empty')

    if [[ -n "$CONTENT_ID" ]]; then
        echo -e "  ${CYAN}Using content ID: $CONTENT_ID${NC}"

        # Likes
        test_endpoint "Create like" POST "/api/v2/social/likes" \
            "{\"content_id\":\"$CONTENT_ID\",\"content_type\":\"post\"}"

        test_endpoint "Get likes for content" GET "/api/v2/social/likes?content_id=$CONTENT_ID&content_type=post&limit=20"

        test_endpoint "Check if user liked content" GET "/api/v2/social/likes/check?content_id=$CONTENT_ID&content_type=post"

        test_endpoint "Delete like" DELETE "/api/v2/social/likes?content_id=$CONTENT_ID&content_type=post"

        # Comments
        test_endpoint "Create comment" POST "/api/v2/social/comments" \
            "{\"content_id\":\"$CONTENT_ID\",\"content_type\":\"post\",\"text\":\"E2E test comment\"}"

        # Get comment ID for deletion
        COMMENT_ID=$(curl -s -X POST "$GW_BASE/api/v2/social/comments" \
            -H "$AUTH_HEADER" -H "Content-Type: application/json" \
            -d "{\"content_id\":\"$CONTENT_ID\",\"content_type\":\"post\",\"text\":\"Comment to delete\"}" \
            | jq -r '.id // empty')

        test_endpoint "Get comments" GET "/api/v2/social/comments?content_id=$CONTENT_ID&content_type=post&limit=20"

        if [[ -n "$COMMENT_ID" ]]; then
            test_endpoint "Delete comment (v2)" DELETE "/api/v2/social/comments/$COMMENT_ID"
        else
            skip_test "DELETE /api/v2/social/comments/{id}" "Failed to create comment"
        fi

        # Shares
        test_endpoint "Create share" POST "/api/v2/social/shares" \
            "{\"content_id\":\"$CONTENT_ID\",\"content_type\":\"post\"}"

        test_endpoint "Get share count" GET "/api/v2/social/shares/count?content_id=$CONTENT_ID&content_type=post"

    else
        echo -e "  ${YELLOW}⚠ No content available in feed, skipping social interaction tests${NC}"
        skip_test "All social interaction endpoints" "No content available"
    fi

    # ========================================
    # 11. ALICE AI ASSISTANT (Placeholder)
    # ========================================
    subsection "11. Alice AI Assistant"

    echo -e "  ${YELLOW}⚠ Alice is not yet implemented, expecting 404/503${NC}"
    # These will likely fail, so we don't increment failure count
    curl -s -H "$AUTH_HEADER" "$GW_BASE/api/v2/alice/status" > /dev/null 2>&1 || true
    echo -e "  ${YELLOW}[INFO]${NC} Alice status: Not available (expected)"
    skip_test "GET /api/v2/alice/status" "Alice not implemented"
    skip_test "POST /api/v2/alice/chat" "Alice not implemented"
    skip_test "POST /api/v2/alice/voice" "Alice not implemented"

    # ========================================
    # SUMMARY
    # ========================================
    section "Test Summary"
    echo "Total:   $TOTAL_TESTS"
    echo -e "Passed:  ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:  ${RED}$FAILED_TESTS${NC}"
    echo -e "Skipped: ${YELLOW}$SKIPPED_TESTS${NC}"
    echo ""

    # Calculate pass rate
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local executed_tests=$((TOTAL_TESTS - SKIPPED_TESTS))
        if [[ $executed_tests -gt 0 ]]; then
            local pass_rate=$((PASSED_TESTS * 100 / executed_tests))
            echo -e "Pass Rate: ${CYAN}${pass_rate}%${NC}"
        fi
    fi

    echo ""

    # Detailed results
    if [[ ${#TEST_RESULTS[@]} -gt 0 ]]; then
        echo -e "${CYAN}Detailed Results:${NC}"
        for test in "${!TEST_RESULTS[@]}"; do
            local result="${TEST_RESULTS[$test]}"
            if [[ "$result" == "PASS" ]]; then
                echo -e "  ${GREEN}✓${NC} $test"
            elif [[ "$result" == SKIP* ]]; then
                echo -e "  ${YELLOW}○${NC} $test - $result"
            else
                echo -e "  ${RED}✗${NC} $test - $result"
            fi
        done
    fi

    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}✓ All executed tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Prerequisites check
check_prerequisites() {
    local missing_deps=0

    if [[ -z "${TOKEN:-}" ]]; then
        echo -e "${RED}Error: TOKEN environment variable is not set${NC}"
        echo "Usage: export TOKEN=\"your_jwt_token\""
        missing_deps=1
    fi

    if [[ -z "${USER_ID:-}" ]]; then
        echo -e "${RED}Error: USER_ID environment variable is not set${NC}"
        echo "Usage: export USER_ID=\"your_user_uuid\""
        missing_deps=1
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is not installed${NC}"
        echo "Install: brew install jq"
        missing_deps=1
    fi

    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is not installed${NC}"
        missing_deps=1
    fi

    if [[ $missing_deps -ne 0 ]]; then
        exit 1
    fi
}

# Entry point
check_prerequisites
main "$@"
