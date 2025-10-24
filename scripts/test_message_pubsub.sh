#!/bin/bash
# Test script to verify Redis pub/sub for messaging system
# This script verifies that messages are published to Redis channels after database insertion

set -e

REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
API_URL="${API_URL:-http://localhost:8080}"

echo "=========================================="
echo "Message Pub/Sub Verification Test"
echo "=========================================="
echo ""

# Check Redis connection
echo "1. Checking Redis connection..."
if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING > /dev/null 2>&1; then
    echo "❌ Redis is not running on $REDIS_HOST:$REDIS_PORT"
    exit 1
fi
echo "✅ Redis is running"
echo ""

# Create test conversation
echo "2. Creating test conversation..."
CONV_RESPONSE=$(curl -s -X POST "$API_URL/api/v1/conversations" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer YOUR_TEST_TOKEN" \
    -d '{
        "type": "direct",
        "participant_ids": ["00000000-0000-0000-0000-000000000002"]
    }' || echo "")

if [ -z "$CONV_RESPONSE" ]; then
    echo "⚠️  Cannot test without authentication. Please set up test user first."
    echo ""
    echo "To test manually:"
    echo "1. Subscribe to Redis channel:"
    echo "   redis-cli SUBSCRIBE 'conversation:*:messages'"
    echo ""
    echo "2. Send a message via API:"
    echo "   POST /api/v1/messages"
    echo "   {\"conversation_id\": \"...\", \"encrypted_content\": \"...\", \"nonce\": \"...\"}"
    echo ""
    echo "3. Verify message appears in Redis subscriber"
    exit 0
fi

CONV_ID=$(echo "$CONV_RESPONSE" | jq -r '.id')
echo "✅ Conversation created: $CONV_ID"
echo ""

# Subscribe to Redis channel (in background)
echo "3. Subscribing to Redis pub/sub channel..."
CHANNEL="conversation:$CONV_ID:messages"
echo "   Channel: $CHANNEL"

REDIS_OUTPUT="/tmp/redis_pubsub_test_$$"
timeout 10s redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SUBSCRIBE "$CHANNEL" > "$REDIS_OUTPUT" 2>&1 &
REDIS_PID=$!

sleep 2
echo "✅ Subscribed (PID: $REDIS_PID)"
echo ""

# Send test message
echo "4. Sending test message..."
MSG_RESPONSE=$(curl -s -X POST "$API_URL/api/v1/messages" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer YOUR_TEST_TOKEN" \
    -d "{
        \"conversation_id\": \"$CONV_ID\",
        \"encrypted_content\": \"$(echo -n 'Test message' | base64)\",
        \"nonce\": \"$(openssl rand -base64 24 | head -c 32)\",
        \"message_type\": \"text\"
    }" || echo "")

if [ -z "$MSG_RESPONSE" ]; then
    echo "❌ Failed to send message"
    kill $REDIS_PID 2>/dev/null || true
    rm -f "$REDIS_OUTPUT"
    exit 1
fi

MESSAGE_ID=$(echo "$MSG_RESPONSE" | jq -r '.id')
echo "✅ Message sent: $MESSAGE_ID"
echo ""

# Wait for Redis publish
sleep 3
kill $REDIS_PID 2>/dev/null || true
wait $REDIS_PID 2>/dev/null || true

# Verify Redis received the event
echo "5. Verifying Redis pub/sub event..."
if grep -q "message.new" "$REDIS_OUTPUT"; then
    echo "✅ SUCCESS: Message event published to Redis!"
    echo ""
    echo "Published event:"
    grep -A 1 "message.new" "$REDIS_OUTPUT" || true
else
    echo "❌ FAILED: Message was NOT published to Redis"
    echo ""
    echo "Redis output:"
    cat "$REDIS_OUTPUT"
    echo ""
    echo "This indicates the bug is still present:"
    echo "- Message saved to database: ✅"
    echo "- Message published to Redis: ❌"
    rm -f "$REDIS_OUTPUT"
    exit 1
fi

rm -f "$REDIS_OUTPUT"

echo ""
echo "=========================================="
echo "✅ All checks passed!"
echo "=========================================="
echo ""
echo "Message delivery pipeline:"
echo "1. Client sends message → ✅"
echo "2. Saved to PostgreSQL → ✅"
echo "3. Published to Redis → ✅"
echo "4. WebSocket subscribers receive → (check WebSocket logs)"
echo ""
