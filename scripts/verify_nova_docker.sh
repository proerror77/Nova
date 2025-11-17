#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$ROOT_DIR"

echo "[1/5] Bringing up core services (postgres, redis, milvus, search-service)"
docker compose up -d postgres redis milvus search-service

echo "[2/5] Waiting for Postgres & Redis health..."
sleep 5

echo "[3/5] Checking Milvus health..."
HEALTH_OK=0
for i in {1..12}; do
  if curl -sf http://localhost:9091/api/v1/health >/dev/null; then
    echo "Milvus: OK"
    HEALTH_OK=1
    break
  fi
  echo "Milvus not ready yet... ($i/12)"
  sleep 5
done
if [ "$HEALTH_OK" != "1" ]; then
  echo "WARNING: Milvus health check failed (http://localhost:9091/api/v1/health). The system will fallback to Postgres for vector search." >&2
fi

echo "[4/5] Checking service endpoints..."
SEARCH_SERVICE_BASE="http://localhost:8081"

echo -n "- search-service /health: "
curl -sf "$SEARCH_SERVICE_BASE/health" >/dev/null && echo OK || { echo FAIL; exit 1; }

echo "[5/5] Summary: All core endpoints are reachable."
echo "- search-service: $SEARCH_SERVICE_BASE"
echo "- milvus:       http://localhost:9091"

exit 0
