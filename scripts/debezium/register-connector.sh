#!/usr/bin/env bash
set -euo pipefail

CONNECT_URL=${DEBEZIUM_CONNECT_URL:-http://localhost:8083}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONNECTOR_FILE="${ROOT_DIR}/infra/debezium/connectors/postgres-feed.json"

if [[ ! -f "${CONNECTOR_FILE}" ]]; then
  echo "Connector definition not found: ${CONNECTOR_FILE}" >&2
  exit 1
fi

echo "Registering Debezium connector from ${CONNECTOR_FILE}"
curl -s -X DELETE "${CONNECT_URL}/connectors/postgres-feed-connector" >/dev/null || true
curl -s -X POST \
  -H "Content-Type: application/json" \
  --data @"${CONNECTOR_FILE}" \
  "${CONNECT_URL}/connectors" | jq .

echo "Active connectors:"
curl -s "${CONNECT_URL}/connectors" | jq .
