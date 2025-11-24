#!/bin/bash
# Create test user for E2E testing

set -euo pipefail

GW_BASE="${GW_BASE:-http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com}"
TIMESTAMP=$(date +%s)

echo "Creating test user..."

RESPONSE=$(curl -s -X POST "$GW_BASE/api/v2/auth/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"e2e-test-${TIMESTAMP}@nova-test.com\",
    \"password\": \"TestPass123\",
    \"username\": \"e2e_test_${TIMESTAMP}\",
    \"first_name\": \"E2E\",
    \"last_name\": \"Test\"
  }")

echo "$RESPONSE" | jq '.'

# Extract token and user_id
TOKEN=$(echo "$RESPONSE" | jq -r '.token // .access_token // empty')
USER_ID=$(echo "$RESPONSE" | jq -r '.user.id // .user_id // empty')

if [[ -n "$TOKEN" && -n "$USER_ID" ]]; then
  echo ""
  echo "✓ User created successfully!"
  echo ""
  echo "Export these variables:"
  echo "export TOKEN=\"$TOKEN\""
  echo "export USER_ID=\"$USER_ID\""
  echo ""
  echo "Then run:"
  echo "./scripts/e2e-api-test.sh"
else
  echo "✗ Failed to create user"
  echo "Response: $RESPONSE"
  exit 1
fi
