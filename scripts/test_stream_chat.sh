#!/bin/bash
# Nova Stream Chat WebSocket Testing Script
#
# Usage: ./test_stream_chat.sh [stream_id] [jwt_token]
#
# Requirements:
# - websocat (install: cargo install websocat)
# - jq (install: brew install jq)

set -e

STREAM_ID="${1:-00000000-0000-0000-0000-000000000001}"
JWT_TOKEN="${2}"
WS_URL="ws://localhost:8080/ws/streams/${STREAM_ID}/chat"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Nova Stream Chat WebSocket Test${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Check if websocat is installed
if ! command -v websocat &> /dev/null; then
    echo -e "${RED}❌ websocat not found${NC}"
    echo "Install it with: cargo install websocat"
    exit 1
fi

# Check if JWT token is provided
if [ -z "$JWT_TOKEN" ]; then
    echo -e "${YELLOW}⚠️  No JWT token provided${NC}"
    echo "Usage: $0 [stream_id] [jwt_token]"
    echo
    echo "To get a JWT token:"
    echo "1. Login via API: POST http://localhost:8080/api/v1/auth/login"
    echo "2. Copy the 'access_token' from response"
    echo
    read -p "Enter JWT token (or press Ctrl+C to exit): " JWT_TOKEN
fi

echo -e "${GREEN}✓ Configuration${NC}"
echo "  Stream ID: ${STREAM_ID}"
echo "  WebSocket URL: ${WS_URL}"
echo "  JWT Token: ${JWT_TOKEN:0:20}..."
echo

# Test 1: Connect to WebSocket
echo -e "${BLUE}Test 1: WebSocket Connection${NC}"
echo "Connecting to stream chat..."

# Create a named pipe for bidirectional communication
PIPE="/tmp/nova_ws_test_$$"
mkfifo "$PIPE"

# Cleanup function
cleanup() {
    echo
    echo -e "${YELLOW}Cleaning up...${NC}"
    rm -f "$PIPE"
    exit 0
}
trap cleanup INT TERM

# Start websocat in background
(
    echo '{"type":"ping"}'
    sleep 1
    echo '{"type":"message","text":"Hello from test script!"}'
    sleep 1
    echo '{"type":"message","text":"Testing broadcast functionality"}'
    sleep 2
) | websocat -H "Authorization: Bearer ${JWT_TOKEN}" "${WS_URL}" 2>&1 | while IFS= read -r line; do
    # Parse JSON response
    if echo "$line" | jq -e . >/dev/null 2>&1; then
        TYPE=$(echo "$line" | jq -r '.type // "broadcast"')

        case "$TYPE" in
            error)
                MESSAGE=$(echo "$line" | jq -r '.message')
                echo -e "${RED}❌ Error: ${MESSAGE}${NC}"
                ;;
            broadcast)
                COMMENT=$(echo "$line" | jq -r '.comment')
                USERNAME=$(echo "$COMMENT" | jq -r '.username // "unknown"')
                MESSAGE=$(echo "$COMMENT" | jq -r '.message')
                TIMESTAMP=$(echo "$COMMENT" | jq -r '.created_at')
                echo -e "${GREEN}✓ Message received${NC}"
                echo "  From: ${USERNAME}"
                echo "  Text: ${MESSAGE}"
                echo "  Time: ${TIMESTAMP}"
                ;;
            *)
                echo -e "${YELLOW}ℹ Other: ${line}${NC}"
                ;;
        esac
    else
        echo -e "${YELLOW}ℹ Raw: ${line}${NC}"
    fi
done

cleanup
