#!/bin/bash
# Check Debezium Connector Status
# Usage: ./check-connector.sh [debezium_host]

DEBEZIUM_HOST="${1:-localhost:8083}"
CONNECTOR_NAME="nova-postgres-cdc"

echo "=== Debezium Connector Status ==="
echo "Host: ${DEBEZIUM_HOST}"
echo ""

# Check Debezium Connect health
echo "1. Debezium Connect:"
if curl -sf "http://${DEBEZIUM_HOST}/" > /dev/null 2>&1; then
    echo "   Status: HEALTHY"
else
    echo "   Status: UNREACHABLE"
    exit 1
fi

# List all connectors
echo ""
echo "2. Active Connectors:"
CONNECTORS=$(curl -sf "http://${DEBEZIUM_HOST}/connectors" || echo "[]")
echo "   ${CONNECTORS}"

# Check specific connector status
echo ""
echo "3. Connector '${CONNECTOR_NAME}' Status:"
STATUS=$(curl -sf "http://${DEBEZIUM_HOST}/connectors/${CONNECTOR_NAME}/status" 2>/dev/null)
if [ -z "${STATUS}" ]; then
    echo "   Not found"
else
    echo "${STATUS}" | jq '.' 2>/dev/null || echo "${STATUS}"
fi

# Check Kafka topics
echo ""
echo "4. CDC Topics (check via kafka-topics):"
echo "   Run: docker exec nova-kafka kafka-topics --list --bootstrap-server localhost:9092 | grep cdc"
