#!/usr/bin/env bash
set -euo pipefail

# Apply Neo4j schema (constraints and indexes) using cypher-shell
# Usage: ./scripts/neo4j_init.sh

NEO4J_HOST=${NEO4J_HOST:-localhost}
NEO4J_HTTP_PORT=${NEO4J_HTTP_PORT:-7474}
NEO4J_BOLT_PORT=${NEO4J_BOLT_PORT:-7687}
NEO4J_USER=${NEO4J_USER:-neo4j}
NEO4J_PASSWORD=${NEO4J_PASSWORD:-neo4j}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA_FILE="$SCRIPT_DIR/neo4j_schema.cypher"

if ! command -v cypher-shell >/dev/null 2>&1; then
  echo "cypher-shell not found. If using Docker, try:\n  docker exec -i nova-neo4j cypher-shell -u $NEO4J_USER -p $NEO4J_PASSWORD < $SCHEMA_FILE"
  exit 1
fi

echo "Applying Neo4j schema to bolt://${NEO4J_HOST}:${NEO4J_BOLT_PORT} ..."
cypher-shell -a "bolt://${NEO4J_HOST}:${NEO4J_BOLT_PORT}" -u "$NEO4J_USER" -p "$NEO4J_PASSWORD" < "$SCHEMA_FILE"
echo "Neo4j schema applied."

