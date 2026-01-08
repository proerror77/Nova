#!/bin/bash
# Test Phone OTP in Kubernetes Environment
# This script tests the phone OTP flow from within the Kubernetes cluster

set -e

# Configuration
NAMESPACE="${NAMESPACE:-nova-staging}"
TEST_PHONE="${TEST_PHONE:-+818012345678}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}🧪 Testing Phone OTP in Kubernetes${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Namespace: $NAMESPACE"
echo "Phone: $TEST_PHONE"
echo ""

# Find identity-service pod
echo -e "${YELLOW}Finding identity-service pod...${NC}"
POD=$(kubectl get pod -n "$NAMESPACE" -l app=identity-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD" ]; then
    echo -e "${RED}❌ No identity-service pod found in namespace $NAMESPACE${NC}"
    echo "Available pods:"
    kubectl get pods -n "$NAMESPACE"
    exit 1
fi

echo -e "${GREEN}✅ Found pod: $POD${NC}"
echo ""

# Step 1: Send OTP Code
echo -e "${YELLOW}Step 1: Sending OTP code via pod $POD...${NC}"
SEND_RESPONSE=$(kubectl exec -n "$NAMESPACE" "$POD" -- \
    curl -s -w "\n%{http_code}" -X POST \
    http://localhost:8081/api/v2/auth/phone/send-code \
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
    echo "Code expires in: ${EXPIRES_IN}s"
else
    echo -e "${RED}❌ OTP sending failed${NC}"
    ERROR_MSG=$(echo "$SEND_BODY" | jq -r '.message // "Unknown error"')
    echo "Error: $ERROR_MSG"
    exit 1
fi
echo ""

# Step 2: Check logs for OTP (if in development mode)
echo -e "${YELLOW}Step 2: Checking logs for OTP code...${NC}"
echo "If SMS is configured, check your phone."
echo "If in development mode, OTP will be in the logs:"
echo ""

# Get recent logs
LOGS=$(kubectl logs -n "$NAMESPACE" "$POD" --tail=50 | grep -i "OTP\|verification code" || true)

if [ -n "$LOGS" ]; then
    echo -e "${GREEN}Recent OTP-related logs:${NC}"
    echo "$LOGS"
else
    echo -e "${YELLOW}No OTP found in recent logs. SMS might be configured.${NC}"
fi
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
VERIFY_RESPONSE=$(kubectl exec -n "$NAMESPACE" "$POD" -- \
    curl -s -w "\n%{http_code}" -X POST \
    http://localhost:8081/api/v2/auth/phone/verify-code \
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
    EXPIRES_IN=$(echo "$VERIFY_BODY" | jq -r '.expires_in // "600"')
    echo "Token expires in: ${EXPIRES_IN}s"
    echo ""
else
    echo -e "${RED}❌ OTP verification failed${NC}"
    ERROR_MSG=$(echo "$VERIFY_BODY" | jq -r '.message // "Unknown error"')
    echo "Error: $ERROR_MSG"
    exit 1
fi

# Additional debugging info
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}📊 Additional Information${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check pod environment variables
echo -e "${YELLOW}Checking AWS configuration...${NC}"
AWS_REGION=$(kubectl exec -n "$NAMESPACE" "$POD" -- printenv AWS_REGION || echo "not set")
echo "AWS_REGION: $AWS_REGION"

if [ "$AWS_REGION" = "not set" ]; then
    echo -e "${YELLOW}⚠️  AWS_REGION not set - SMS will not be sent (development mode)${NC}"
else
    echo -e "${GREEN}✅ AWS_REGION is configured - SMS should be sent${NC}"
fi
echo ""

# Check recent logs for AWS/SNS errors
echo -e "${YELLOW}Checking for AWS/SNS errors in logs...${NC}"
ERROR_LOGS=$(kubectl logs -n "$NAMESPACE" "$POD" --tail=100 | grep -i "aws\|sns\|error" | tail -20 || true)

if [ -n "$ERROR_LOGS" ]; then
    echo -e "${YELLOW}Recent AWS/SNS related logs:${NC}"
    echo "$ERROR_LOGS"
else
    echo -e "${GREEN}No errors found${NC}"
fi
echo ""

# Summary
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ Kubernetes Phone OTP Test Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Test Summary:"
echo "  Pod: $POD"
echo "  Namespace: $NAMESPACE"
echo "  Phone: $TEST_PHONE"
echo "  ✅ Send OTP - Success"
echo "  ✅ Verify OTP - Success"
echo ""
echo "Useful Commands:"
echo "  # View full logs"
echo "  kubectl logs -n $NAMESPACE $POD --tail=100"
echo ""
echo "  # Follow logs in real-time"
echo "  kubectl logs -n $NAMESPACE -f $POD"
echo ""
echo "  # Check pod environment variables"
echo "  kubectl exec -n $NAMESPACE $POD -- printenv | grep AWS"
echo ""
echo "  # Port forward for direct testing"
echo "  kubectl port-forward -n $NAMESPACE svc/identity-service 8081:8081"
echo "  # Then run: ./test-phone-otp.sh"
echo ""
