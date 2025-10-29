#!/bin/bash
# Group Video Call API Test Script
#
# Requirements:
# - jq (JSON processor)
# - curl
# - Running messaging-service on localhost:8080
#
# Usage:
#   ./group_call_test.sh
#
# Environment variables:
#   API_BASE_URL (default: http://localhost:8080/api/v1)
#   AUTH_TOKEN_A (User A's JWT token)
#   AUTH_TOKEN_B (User B's JWT token)
#   AUTH_TOKEN_C (User C's JWT token)

set -euo pipefail

# Configuration
API_BASE_URL="${API_BASE_URL:-http://localhost:8080/api/v1}"
AUTH_TOKEN_A="${AUTH_TOKEN_A:-your-user-a-token}"
AUTH_TOKEN_B="${AUTH_TOKEN_B:-your-user-b-token}"
AUTH_TOKEN_C="${AUTH_TOKEN_C:-your-user-c-token}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local message="$3"

    if [[ "$actual" == "$expected" ]]; then
        log_info "✓ $message"
        ((TESTS_PASSED++))
    else
        log_error "✗ $message (expected: $expected, got: $actual)"
        ((TESTS_FAILED++))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if echo "$haystack" | grep -q "$needle"; then
        log_info "✓ $message"
        ((TESTS_PASSED++))
    else
        log_error "✗ $message (not found: $needle)"
        ((TESTS_FAILED++))
    fi
}

# Mock SDP offers (minimal valid format)
SDP_A='v=0\r\no=- 1234567890 1234567890 IN IP4 127.0.0.1\r\ns=User A\r\n'
SDP_B='v=0\r\no=- 9876543210 9876543210 IN IP4 127.0.0.1\r\ns=User B\r\n'
SDP_C='v=0\r\no=- 1111111111 1111111111 IN IP4 127.0.0.1\r\ns=User C\r\n'

# ==============================================================================
# Test Suite: Group Video Calls
# ==============================================================================

log_info "Starting Group Video Call API Tests"
echo "API Base URL: $API_BASE_URL"
echo ""

# ------------------------------------------------------------------------------
# Prerequisite: Create a group conversation
# ------------------------------------------------------------------------------
log_test "Prerequisite: Create group conversation"

CONV_RESPONSE=$(curl -s -X POST "$API_BASE_URL/conversations/groups" \
    -H "Authorization: Bearer $AUTH_TOKEN_A" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Test Group Call",
        "member_ids": ["user-b-id", "user-c-id"]
    }')

CONVERSATION_ID=$(echo "$CONV_RESPONSE" | jq -r '.id')

if [[ "$CONVERSATION_ID" != "null" && -n "$CONVERSATION_ID" ]]; then
    log_info "Created conversation: $CONVERSATION_ID"
else
    log_error "Failed to create conversation"
    log_error "Response: $CONV_RESPONSE"
    exit 1
fi

echo ""

# ==============================================================================
# Test 1: Backward Compatibility - 1:1 Call with Default Parameters
# ==============================================================================
log_test "Test 1: 1:1 Call (Backward Compatibility)"

CALL_RESPONSE=$(curl -s -X POST "$API_BASE_URL/conversations/$CONVERSATION_ID/calls" \
    -H "Authorization: Bearer $AUTH_TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{
        \"initiator_sdp\": \"$SDP_A\"
    }")

CALL_ID=$(echo "$CALL_RESPONSE" | jq -r '.id')
CALL_STATUS=$(echo "$CALL_RESPONSE" | jq -r '.status')
CALL_TYPE=$(echo "$CALL_RESPONSE" | jq -r '.call_type // "direct"')
MAX_PARTICIPANTS=$(echo "$CALL_RESPONSE" | jq -r '.max_participants // 2')

assert_eq "$CALL_STATUS" "ringing" "Call status is ringing"
assert_eq "$CALL_TYPE" "direct" "Default call_type is direct"
assert_eq "$MAX_PARTICIPANTS" "2" "Default max_participants is 2"

echo ""

# ==============================================================================
# Test 2: Initiate Group Call with Explicit Parameters
# ==============================================================================
log_test "Test 2: Initiate Group Call"

GROUP_CALL_RESPONSE=$(curl -s -X POST "$API_BASE_URL/conversations/$CONVERSATION_ID/calls" \
    -H "Authorization: Bearer $AUTH_TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{
        \"initiator_sdp\": \"$SDP_A\",
        \"call_type\": \"group\",
        \"max_participants\": 8
    }")

GROUP_CALL_ID=$(echo "$GROUP_CALL_RESPONSE" | jq -r '.id')
GROUP_CALL_STATUS=$(echo "$GROUP_CALL_RESPONSE" | jq -r '.status')
GROUP_CALL_TYPE=$(echo "$GROUP_CALL_RESPONSE" | jq -r '.call_type')
GROUP_MAX_PARTICIPANTS=$(echo "$GROUP_CALL_RESPONSE" | jq -r '.max_participants')

assert_eq "$GROUP_CALL_STATUS" "ringing" "Group call status is ringing"
assert_eq "$GROUP_CALL_TYPE" "group" "Call type is group"
assert_eq "$GROUP_MAX_PARTICIPANTS" "8" "Max participants is 8"

echo ""

# ==============================================================================
# Test 3: User B Joins Group Call
# ==============================================================================
log_test "Test 3: User B Joins Group Call"

JOIN_RESPONSE_B=$(curl -s -X POST "$API_BASE_URL/calls/$GROUP_CALL_ID/join" \
    -H "Authorization: Bearer $AUTH_TOKEN_B" \
    -H "Content-Type: application/json" \
    -d "{
        \"sdp\": \"$SDP_B\"
    }")

PARTICIPANT_ID_B=$(echo "$JOIN_RESPONSE_B" | jq -r '.participant_id')
PARTICIPANT_COUNT=$(echo "$JOIN_RESPONSE_B" | jq -r '.current_participant_count')
EXISTING_PARTICIPANTS=$(echo "$JOIN_RESPONSE_B" | jq -r '.participants | length')

assert_eq "$PARTICIPANT_COUNT" "2" "Participant count is 2 after B joins"
assert_eq "$EXISTING_PARTICIPANTS" "1" "User B receives 1 existing participant SDP (User A)"

# Check if User A's SDP is included
USER_A_SDP_PRESENT=$(echo "$JOIN_RESPONSE_B" | jq -r '.participants[0].sdp' | grep -c "User A" || echo "0")
assert_eq "$USER_A_SDP_PRESENT" "1" "User A's SDP is present in response"

echo ""

# ==============================================================================
# Test 4: User C Joins Group Call
# ==============================================================================
log_test "Test 4: User C Joins Group Call"

JOIN_RESPONSE_C=$(curl -s -X POST "$API_BASE_URL/calls/$GROUP_CALL_ID/join" \
    -H "Authorization: Bearer $AUTH_TOKEN_C" \
    -H "Content-Type: application/json" \
    -d "{
        \"sdp\": \"$SDP_C\"
    }")

PARTICIPANT_ID_C=$(echo "$JOIN_RESPONSE_C" | jq -r '.participant_id')
PARTICIPANT_COUNT_C=$(echo "$JOIN_RESPONSE_C" | jq -r '.current_participant_count')
EXISTING_PARTICIPANTS_C=$(echo "$JOIN_RESPONSE_C" | jq -r '.participants | length')

assert_eq "$PARTICIPANT_COUNT_C" "3" "Participant count is 3 after C joins"
assert_eq "$EXISTING_PARTICIPANTS_C" "2" "User C receives 2 existing participant SDPs (A and B)"

echo ""

# ==============================================================================
# Test 5: Get Participants List
# ==============================================================================
log_test "Test 5: Get Participants List"

PARTICIPANTS_RESPONSE=$(curl -s -X GET "$API_BASE_URL/calls/$GROUP_CALL_ID/participants" \
    -H "Authorization: Bearer $AUTH_TOKEN_A")

PARTICIPANTS_COUNT=$(echo "$PARTICIPANTS_RESPONSE" | jq -r '.participants | length')
assert_eq "$PARTICIPANTS_COUNT" "3" "Participants list contains 3 users"

echo ""

# ==============================================================================
# Test 6: User B Leaves Group Call
# ==============================================================================
log_test "Test 6: User B Leaves Group Call"

LEAVE_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_BASE_URL/calls/$GROUP_CALL_ID/leave" \
    -H "Authorization: Bearer $AUTH_TOKEN_B")

assert_eq "$LEAVE_HTTP_CODE" "204" "Leave call returns 204 No Content"

# Verify participant count decreased
PARTICIPANTS_AFTER_LEAVE=$(curl -s -X GET "$API_BASE_URL/calls/$GROUP_CALL_ID/participants" \
    -H "Authorization: Bearer $AUTH_TOKEN_A")

ACTIVE_PARTICIPANTS=$(echo "$PARTICIPANTS_AFTER_LEAVE" | jq -r '[.participants[] | select(.left_at == null)] | length')
assert_eq "$ACTIVE_PARTICIPANTS" "2" "Active participants count is 2 after B leaves"

echo ""

# ==============================================================================
# Test 7: Error Handling - Duplicate Join
# ==============================================================================
log_test "Test 7: Error Handling - Duplicate Join"

DUPLICATE_JOIN=$(curl -s -X POST "$API_BASE_URL/calls/$GROUP_CALL_ID/join" \
    -H "Authorization: Bearer $AUTH_TOKEN_C" \
    -H "Content-Type: application/json" \
    -d "{
        \"sdp\": \"$SDP_C\"
    }")

DUPLICATE_ERROR=$(echo "$DUPLICATE_JOIN" | jq -r '.error // .message' | grep -i "already" || echo "")
assert_contains "$DUPLICATE_ERROR" "already" "Duplicate join returns error containing 'already'"

echo ""

# ==============================================================================
# Test 8: Error Handling - Invalid Call Type
# ==============================================================================
log_test "Test 8: Error Handling - Invalid Call Type"

INVALID_TYPE_RESPONSE=$(curl -s -X POST "$API_BASE_URL/conversations/$CONVERSATION_ID/calls" \
    -H "Authorization: Bearer $AUTH_TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{
        \"initiator_sdp\": \"$SDP_A\",
        \"call_type\": \"invalid\"
    }")

INVALID_TYPE_ERROR=$(echo "$INVALID_TYPE_RESPONSE" | jq -r '.error // .message')
assert_contains "$INVALID_TYPE_ERROR" "direct\|group" "Invalid call_type returns validation error"

echo ""

# ==============================================================================
# Test 9: Error Handling - Exceeds Max Participants
# ==============================================================================
log_test "Test 9: Error Handling - Exceeds Max Participants"

EXCEEDS_MAX_RESPONSE=$(curl -s -X POST "$API_BASE_URL/conversations/$CONVERSATION_ID/calls" \
    -H "Authorization: Bearer $AUTH_TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{
        \"initiator_sdp\": \"$SDP_A\",
        \"call_type\": \"group\",
        \"max_participants\": 100
    }")

EXCEEDS_MAX_ERROR=$(echo "$EXCEEDS_MAX_RESPONSE" | jq -r '.error // .message')
assert_contains "$EXCEEDS_MAX_ERROR" "exceed\|50" "Max participants > 50 returns validation error"

echo ""

# ==============================================================================
# Test 10: End Call
# ==============================================================================
log_test "Test 10: End Group Call"

END_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_BASE_URL/calls/$GROUP_CALL_ID/end" \
    -H "Authorization: Bearer $AUTH_TOKEN_A")

assert_eq "$END_HTTP_CODE" "204" "End call returns 204 No Content"

echo ""

# ==============================================================================
# Test Summary
# ==============================================================================
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    exit 1
fi
