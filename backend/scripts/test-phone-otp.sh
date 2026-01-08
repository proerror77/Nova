#!/bin/bash
# Test Phone OTP Flow End-to-End
# This script tests the complete phone authentication flow

set -e

# Configuration
IDENTITY_SERVICE_URL="${IDENTITY_SERVICE_URL:-http://localhost:8081}"
TEST_PHONE="${TEST_PHONE:-+818012345678}"  # Japan test number format

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}🧪 Testing Phone OTP Flow${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Service: $IDENTITY_SERVICE_URL"
echo "Phone: $TEST_PHONE"
echo ""

# Step 1: Send OTP Code
echo -e "${YELLOW}Step 1: Sending OTP code...${NC}"
SEND_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$IDENTITY_SERVICE_URL/api/v2/auth/phone/send-code" \
  -H "Content-Type: application/json" \
  -d "{\"phone_number\":\"$TEST_PHONE\"}")

# Extract HTTP status code (last line)
HTTP_STATUS=$(echo "$SEND_RESPONSE" | tail -n 1)
# Extract response body (all but last line)
SEND_BODY=$(echo "$SEND_RESPONSE" | sed '$d')

echo "HTTP Status: $HTTP_STATUS"
echo "Response: $SEND_BODY"

if [ "$HTTP_STATUS" != "200" ]; then
    echo -e "${RED}❌ Failed to send OTP code${NC}"
    echo "Response: $SEND_BODY"
    exit 1
fi

# Check if response indicates success
if echo "$SEND_BODY" | jq -e '.success == true' > /dev/null 2>&1; then
    echo -e "${GREEN}✅ OTP code sent successfully${NC}"

    # Extract expiry time
    EXPIRES_IN=$(echo "$SEND_BODY" | jq -r '.expires_in // "300"')
    echo "Code expires in: ${EXPIRES_IN}s ($(($EXPIRES_IN / 60)) minutes)"

    # Extract message
    MESSAGE=$(echo "$SEND_BODY" | jq -r '.message // "OTP sent"')
    echo "Message: $MESSAGE"
else
    echo -e "${RED}❌ OTP sending failed${NC}"
    ERROR_MSG=$(echo "$SEND_BODY" | jq -r '.message // "Unknown error"')
    echo "Error: $ERROR_MSG"
    exit 1
fi
echo ""

# Step 2: Manual OTP input
echo -e "${YELLOW}Step 2: Please check your phone for the OTP code${NC}"
echo ""
echo "If SMS is not configured (development mode), check the logs:"
echo "  kubectl logs -l app=identity-service -n nova-staging --tail=100 | grep OTP"
echo "  OR docker-compose logs identity-service | grep OTP"
echo ""
read -p "Enter the 6-digit code: " OTP_CODE

# Validate OTP code format
if ! [[ "$OTP_CODE" =~ ^[0-9]{6}$ ]]; then
    echo -e "${RED}❌ Invalid OTP code format. Must be 6 digits.${NC}"
    exit 1
fi
echo ""

# Step 3: Verify OTP
echo -e "${YELLOW}Step 3: Verifying OTP code...${NC}"
VERIFY_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$IDENTITY_SERVICE_URL/api/v2/auth/phone/verify-code" \
  -H "Content-Type: application/json" \
  -d "{\"phone_number\":\"$TEST_PHONE\",\"code\":\"$OTP_CODE\"}")

# Extract HTTP status code (last line)
HTTP_STATUS=$(echo "$VERIFY_RESPONSE" | tail -n 1)
# Extract response body (all but last line)
VERIFY_BODY=$(echo "$VERIFY_RESPONSE" | sed '$d')

echo "HTTP Status: $HTTP_STATUS"
echo "Response: $VERIFY_BODY"

if [ "$HTTP_STATUS" != "200" ]; then
    echo -e "${RED}❌ Failed to verify OTP code${NC}"
    echo "Response: $VERIFY_BODY"
    exit 1
fi

# Extract verification token
VERIFICATION_TOKEN=$(echo "$VERIFY_BODY" | jq -r '.verification_token // empty')

if [ -n "$VERIFICATION_TOKEN" ] && [ "$VERIFICATION_TOKEN" != "null" ]; then
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}✅ OTP Verification Successful!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo "Verification Token: $VERIFICATION_TOKEN"
    echo ""
    echo -e "${BLUE}You can now use this token for registration or login:${NC}"
    echo ""
    echo -e "${YELLOW}Registration:${NC}"
    echo "  curl -X POST $IDENTITY_SERVICE_URL/api/v2/auth/phone/register \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{"
    echo "      \"phone_number\": \"$TEST_PHONE\","
    echo "      \"verification_token\": \"$VERIFICATION_TOKEN\","
    echo "      \"username\": \"testuser\","
    echo "      \"password\": \"Test123456\","
    echo "      \"invite_code\": \"ICERED\""
    echo "    }'"
    echo ""
    echo -e "${YELLOW}Login (if already registered):${NC}"
    echo "  curl -X POST $IDENTITY_SERVICE_URL/api/v2/auth/phone/login \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{"
    echo "      \"phone_number\": \"$TEST_PHONE\","
    echo "      \"verification_token\": \"$VERIFICATION_TOKEN\""
    echo "    }'"
    echo ""
    echo -e "${BLUE}Token Details:${NC}"
    EXPIRES_IN=$(echo "$VERIFY_BODY" | jq -r '.expires_in // "600"')
    echo "  Token expires in: ${EXPIRES_IN}s ($(($EXPIRES_IN / 60)) minutes)"
    echo ""
else
    echo -e "${RED}❌ OTP verification failed${NC}"
    ERROR_MSG=$(echo "$VERIFY_BODY" | jq -r '.message // "Unknown error"')
    echo "Error: $ERROR_MSG"
    exit 1
fi

# Summary
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ Phone OTP Test Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Test Summary:"
echo "  ✅ Send OTP code - Success"
echo "  ✅ Receive OTP (SMS or logs) - Success"
echo "  ✅ Verify OTP code - Success"
echo "  ✅ Receive verification token - Success"
echo ""
echo "Next steps:"
echo "  1. Test registration with the verification token"
echo "  2. Test login with phone number"
echo "  3. Check CloudWatch metrics for SMS delivery"
echo ""
