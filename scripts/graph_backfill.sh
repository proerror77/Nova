#!/usr/bin/env bash
set -euo pipefail

# Simple helper to run the follows -> Neo4j backfill
# Usage:
#   ./scripts/graph_backfill.sh
# Env (optional):
#   DATABASE_URL, NEO4J_ENABLED=true, NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD
#   BACKFILL_BATCH_SIZE=5000 BACKFILL_CONCURRENCY=8

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR/backend/user-service"

echo "[backfill] Starting graph backfill..."
echo "[backfill] DATABASE_URL=${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/nova_auth}"
echo "[backfill] NEO4J_URI=${NEO4J_URI:-bolt://localhost:7687}"

NEO4J_ENABLED=${NEO4J_ENABLED:-true} \
cargo run --bin graph_backfill

echo "[backfill] Done."

