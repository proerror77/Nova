#!/bin/bash
# Deploy Debezium PostgreSQL CDC Connector
# Usage: ./deploy-connector.sh [debezium_host]

set -euo pipefail

DEBEZIUM_HOST="${1:-localhost:8083}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECTOR_CONFIG="${SCRIPT_DIR}/../postgres-cdc-connector.json"

echo "=== Debezium CDC Connector Deployment ==="
echo "Host: ${DEBEZIUM_HOST}"
echo "Config: ${CONNECTOR_CONFIG}"

# Wait for Debezium Connect to be ready
echo ""
echo "1. Checking Debezium Connect status..."
for i in {1..30}; do
    if curl -sf "http://${DEBEZIUM_HOST}/" > /dev/null 2>&1; then
        echo "   ✓ Debezium Connect is ready"
        break
    fi
    echo "   Waiting for Debezium Connect... (${i}/30)"
    sleep 2
done

# Verify Debezium is responding
if ! curl -sf "http://${DEBEZIUM_HOST}/" > /dev/null 2>&1; then
    echo "   ✗ ERROR: Debezium Connect not responding at ${DEBEZIUM_HOST}"
    exit 1
fi

# Check existing connectors
echo ""
echo "2. Checking existing connectors..."
EXISTING=$(curl -sf "http://${DEBEZIUM_HOST}/connectors" || echo "[]")
echo "   Existing connectors: ${EXISTING}"

# Check if our connector already exists
CONNECTOR_NAME="nova-postgres-cdc"
if echo "${EXISTING}" | grep -q "${CONNECTOR_NAME}"; then
    echo ""
    echo "3. Connector '${CONNECTOR_NAME}' already exists. Updating..."

    # Get current status
    STATUS=$(curl -sf "http://${DEBEZIUM_HOST}/connectors/${CONNECTOR_NAME}/status" || echo "{}")
    echo "   Current status: $(echo ${STATUS} | jq -r '.connector.state' 2>/dev/null || echo 'unknown')"

    # Delete and recreate (cleanest approach for config updates)
    echo "   Deleting existing connector..."
    curl -sf -X DELETE "http://${DEBEZIUM_HOST}/connectors/${CONNECTOR_NAME}" || true
    sleep 2
fi

# Deploy connector
echo ""
echo "4. Deploying CDC connector..."
RESPONSE=$(curl -sf -X POST "http://${DEBEZIUM_HOST}/connectors" \
    -H "Content-Type: application/json" \
    -d @"${CONNECTOR_CONFIG}" 2>&1) || {
    echo "   ✗ ERROR: Failed to deploy connector"
    echo "   Response: ${RESPONSE}"
    exit 1
}

echo "   ✓ Connector deployed successfully"

# Wait for connector to start
echo ""
echo "5. Waiting for connector to start..."
sleep 5

# Check connector status
STATUS=$(curl -sf "http://${DEBEZIUM_HOST}/connectors/${CONNECTOR_NAME}/status" || echo "{}")
CONNECTOR_STATE=$(echo ${STATUS} | jq -r '.connector.state' 2>/dev/null || echo 'unknown')
TASK_STATE=$(echo ${STATUS} | jq -r '.tasks[0].state' 2>/dev/null || echo 'unknown')

echo ""
echo "=== Deployment Result ==="
echo "Connector: ${CONNECTOR_STATE}"
echo "Task:      ${TASK_STATE}"

if [ "${CONNECTOR_STATE}" = "RUNNING" ] && [ "${TASK_STATE}" = "RUNNING" ]; then
    echo ""
    echo "✓ CDC connector is now RUNNING"
    echo ""
    echo "Captured tables:"
    echo "  - public.posts     → cdc.posts"
    echo "  - public.follows   → cdc.follows"
    echo "  - public.comments  → cdc.comments"
    echo "  - public.likes     → cdc.likes"
    exit 0
else
    echo ""
    echo "⚠ Connector may still be starting or has issues"
    echo "Full status:"
    echo "${STATUS}" | jq . 2>/dev/null || echo "${STATUS}"

    # Check for errors
    if echo "${STATUS}" | jq -e '.tasks[0].trace' > /dev/null 2>&1; then
        echo ""
        echo "Task error trace:"
        echo "${STATUS}" | jq -r '.tasks[0].trace'
    fi
    exit 1
fi
