#!/bin/bash
# Setup Matrix Admin Token for realtime-chat-service
# This script creates a Synapse admin user and configures the admin token

set -e

NAMESPACE="nova-backend"
HOMESERVER_URL="https://matrix.staging.gcp.icered.com"
SERVER_NAME="staging.gcp.icered.com"
ADMIN_USERNAME="nova-admin-service"

echo "=== Matrix Admin Token Setup ==="
echo ""

# Step 1: Get registration shared secret
echo "Step 1: Getting registration shared secret..."
REGISTRATION_SECRET=$(kubectl get secret synapse-oidc-secrets -n $NAMESPACE -o jsonpath='{.data.registration_shared_secret}' | base64 -d)
if [ -z "$REGISTRATION_SECRET" ]; then
    echo "ERROR: Could not get registration_shared_secret from synapse-oidc-secrets"
    exit 1
fi
echo "  Registration secret found"

# Step 2: Generate admin password
ADMIN_PASSWORD=$(openssl rand -base64 24)
echo "Step 2: Generated admin password"

# Step 3: Create admin user using Synapse Admin API
echo "Step 3: Creating admin user..."

# Generate nonce
NONCE=$(openssl rand -hex 16)

# Generate HMAC
MAC=$(echo -n "${NONCE}"$'\x00'"${ADMIN_USERNAME}"$'\x00'"${ADMIN_PASSWORD}"$'\x00'"admin" | openssl dgst -sha1 -hmac "$REGISTRATION_SECRET" | awk '{print $2}')

# Register admin user
REGISTER_RESPONSE=$(curl -s -X POST "${HOMESERVER_URL}/_synapse/admin/v1/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"nonce\": \"${NONCE}\",
    \"username\": \"${ADMIN_USERNAME}\",
    \"password\": \"${ADMIN_PASSWORD}\",
    \"admin\": true,
    \"mac\": \"${MAC}\"
  }")

# Check if user already exists or was created
if echo "$REGISTER_RESPONSE" | grep -q "User ID already taken"; then
    echo "  Admin user already exists, will login to get token"
elif echo "$REGISTER_RESPONSE" | grep -q "error"; then
    echo "  Warning: Registration response: $REGISTER_RESPONSE"
    echo "  Attempting login anyway..."
else
    echo "  Admin user created successfully"
fi

# Step 4: Login to get access token
echo "Step 4: Getting access token..."

# For existing user, we need to use the password login
# But if we don't know the password, we need to use the Synapse Admin API directly
# Since we're the admin, we can use the registration shared secret approach

# Try to get an admin token using the login API
LOGIN_RESPONSE=$(curl -s -X POST "${HOMESERVER_URL}/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"m.login.password\",
    \"identifier\": {
      \"type\": \"m.id.user\",
      \"user\": \"${ADMIN_USERNAME}\"
    },
    \"password\": \"${ADMIN_PASSWORD}\",
    \"device_id\": \"NOVA_ADMIN_SERVICE\",
    \"initial_device_display_name\": \"Nova Admin Service\"
  }")

ADMIN_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"access_token":"[^"]*"' | sed 's/"access_token":"//;s/"$//')

if [ -z "$ADMIN_TOKEN" ]; then
    echo "  ERROR: Could not get access token"
    echo "  Response: $LOGIN_RESPONSE"
    echo ""
    echo "  Trying alternative: Using existing service token with admin privileges..."

    # Check if we can use the existing service token
    SERVICE_TOKEN=$(kubectl get secret nova-matrix-service-token -n $NAMESPACE -o jsonpath='{.data.MATRIX_ACCESS_TOKEN}' | base64 -d)

    # Test if service token has admin access
    TEST_RESPONSE=$(curl -s -X GET "${HOMESERVER_URL}/_synapse/admin/v1/server_version" \
      -H "Authorization: Bearer $SERVICE_TOKEN")

    if echo "$TEST_RESPONSE" | grep -q "server_version"; then
        echo "  Service token has admin access!"
        ADMIN_TOKEN=$SERVICE_TOKEN
    else
        echo "  Service token does not have admin access"
        echo "  Please manually create an admin user and run this script again"
        exit 1
    fi
fi

echo "  Got admin token: ${ADMIN_TOKEN:0:20}..."

# Step 5: Verify admin access
echo "Step 5: Verifying admin access..."
VERIFY_RESPONSE=$(curl -s -X GET "${HOMESERVER_URL}/_synapse/admin/v1/server_version" \
  -H "Authorization: Bearer $ADMIN_TOKEN")

if echo "$VERIFY_RESPONSE" | grep -q "server_version"; then
    echo "  Admin access verified!"
    SERVER_VERSION=$(echo "$VERIFY_RESPONSE" | grep -o '"server_version":"[^"]*"' | sed 's/"server_version":"//;s/"$//')
    echo "  Synapse version: $SERVER_VERSION"
else
    echo "  ERROR: Admin access verification failed"
    echo "  Response: $VERIFY_RESPONSE"
    exit 1
fi

# Step 6: Update Kubernetes secret
echo "Step 6: Updating Kubernetes secret..."

# Get existing secret and add MATRIX_ADMIN_TOKEN
kubectl get secret nova-matrix-service-token -n $NAMESPACE -o json | \
  jq --arg token "$(echo -n "$ADMIN_TOKEN" | base64)" \
  '.data.MATRIX_ADMIN_TOKEN = $token' | \
  kubectl apply -f -

echo "  Secret updated with MATRIX_ADMIN_TOKEN"

# Step 7: Restart realtime-chat-service to pick up new token
echo "Step 7: Restarting realtime-chat-service..."
kubectl rollout restart deployment/realtime-chat-service -n $NAMESPACE
kubectl rollout status deployment/realtime-chat-service -n $NAMESPACE --timeout=120s

echo ""
echo "=== Setup Complete ==="
echo ""
echo "The realtime-chat-service now has MATRIX_ADMIN_TOKEN configured."
echo "Users will receive user-specific Matrix tokens instead of service account tokens."
echo ""
echo "To verify, check the logs:"
echo "  kubectl logs -f deployment/realtime-chat-service -n nova-backend | grep -i matrix"
