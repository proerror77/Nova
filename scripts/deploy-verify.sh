#!/usr/bin/env bash
# Deployment verification script for graphql-gateway
# Verifies that the health check fix is deployed and working

set -euo pipefail

NAMESPACE="nova-staging"
DEPLOYMENT="graphql-gateway"
GW_BASE="${GW_BASE:-http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com}"

echo "=== GraphQL Gateway Deployment Verification ==="
echo

# 1. Check deployment status
echo "[1/5] Checking deployment status..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=60s
echo "✓ Deployment is ready"
echo

# 2. Get pod information
echo "[2/5] Getting pod information..."
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT -o jsonpath='{.items[0].metadata.name}')
POD_IMAGE=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[0].image}')
echo "Pod: $POD_NAME"
echo "Image: $POD_IMAGE"
echo

# 3. Check binary timestamp inside pod
echo "[3/5] Checking binary timestamp inside pod..."
BINARY_INFO=$(kubectl exec $POD_NAME -n $NAMESPACE -- stat -c '%y %s' /app/graphql-gateway 2>/dev/null || echo "N/A")
echo "Binary info: $BINARY_INFO"
echo

# 4. Test /health endpoint (should work without auth)
echo "[4/5] Testing /health endpoint..."
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "$GW_BASE/health" 2>&1 | tail -1)
if [ "$HEALTH_RESPONSE" = "200" ]; then
    echo "✓ /health endpoint works (200 OK)"
else
    echo "✗ /health endpoint failed (HTTP $HEALTH_RESPONSE)"
    exit 1
fi
echo

# 5. Test /health/circuit-breakers endpoint (should work without auth after fix)
echo "[5/5] Testing /health/circuit-breakers endpoint..."
CB_RESPONSE=$(curl -s -w "\n%{http_code}" "$GW_BASE/health/circuit-breakers" 2>&1)
HTTP_CODE=$(echo "$CB_RESPONSE" | tail -1)
BODY=$(echo "$CB_RESPONSE" | head -n -1)

echo "HTTP Status: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ /health/circuit-breakers works without auth!"
    echo
    echo "Response body:"
    echo "$BODY" | jq '.' || echo "$BODY"
    echo
    echo "=== DEPLOYMENT VERIFIED SUCCESSFULLY ==="
elif [ "$HTTP_CODE" = "401" ]; then
    echo "✗ /health/circuit-breakers still requires auth"
    echo "This means the code fix was NOT deployed"
    exit 1
else
    echo "✗ Unexpected HTTP status: $HTTP_CODE"
    echo "Response: $BODY"
    exit 1
fi
