#!/bin/bash
# ============================================
# ClickHouse Initialization Script
# Version: 1.0.0
# Date: 2025-10-18
# Purpose: Idempotent setup for ClickHouse database
# ============================================

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# ============================================
# Configuration
# ============================================
CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-localhost}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-9000}"
CLICKHOUSE_USER="${CLICKHOUSE_USER:-default}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-}"
CLICKHOUSE_DB="${CLICKHOUSE_DB:-nova_analytics}"

# Script directory (absolute path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================
# Helper Functions
# ============================================
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Execute ClickHouse query
execute_query() {
  local query="$1"
  local description="${2:-Executing query}"

  log_info "$description"

  if [ -z "$CLICKHOUSE_PASSWORD" ]; then
    clickhouse-client \
      --host="$CLICKHOUSE_HOST" \
      --port="$CLICKHOUSE_PORT" \
      --user="$CLICKHOUSE_USER" \
      --query="$query" 2>&1 || {
        log_error "Query failed: $description"
        return 1
      }
  else
    clickhouse-client \
      --host="$CLICKHOUSE_HOST" \
      --port="$CLICKHOUSE_PORT" \
      --user="$CLICKHOUSE_USER" \
      --password="$CLICKHOUSE_PASSWORD" \
      --query="$query" 2>&1 || {
        log_error "Query failed: $description"
        return 1
      }
  fi
}

# Execute SQL file with variable substitution
execute_sql_file() {
  local file_path="$1"
  local description="${2:-Executing SQL file: $file_path}"

  if [ ! -f "$file_path" ]; then
    log_error "File not found: $file_path"
    return 1
  fi

  log_info "$description"

  # Replace environment variables in SQL file
  local processed_sql
  processed_sql=$(envsubst < "$file_path")

  if [ -z "$CLICKHOUSE_PASSWORD" ]; then
    echo "$processed_sql" | clickhouse-client \
      --host="$CLICKHOUSE_HOST" \
      --port="$CLICKHOUSE_PORT" \
      --user="$CLICKHOUSE_USER" \
      --multiquery 2>&1 || {
        log_error "Failed to execute: $file_path"
        return 1
      }
  else
    echo "$processed_sql" | clickhouse-client \
      --host="$CLICKHOUSE_HOST" \
      --port="$CLICKHOUSE_PORT" \
      --user="$CLICKHOUSE_USER" \
      --password="$CLICKHOUSE_PASSWORD" \
      --multiquery 2>&1 || {
        log_error "Failed to execute: $file_path"
        return 1
      }
  fi
}

# Wait for ClickHouse to be ready
wait_for_clickhouse() {
  local max_attempts=30
  local attempt=1

  log_info "Waiting for ClickHouse at $CLICKHOUSE_HOST:$CLICKHOUSE_PORT..."

  while [ $attempt -le $max_attempts ]; do
    if execute_query "SELECT 1" "Health check (attempt $attempt/$max_attempts)" > /dev/null 2>&1; then
      log_info "ClickHouse is ready!"
      return 0
    fi

    log_warn "ClickHouse not ready yet, retrying in 2 seconds..."
    sleep 2
    attempt=$((attempt + 1))
  done

  log_error "ClickHouse failed to start after $max_attempts attempts"
  return 1
}

# Check if database exists
database_exists() {
  local db_name="$1"
  local result
  result=$(execute_query "SELECT count() FROM system.databases WHERE name = '$db_name'" 2>&1)
  [ "$result" -eq 1 ]
}

# Check if table exists
table_exists() {
  local table_name="$1"
  local result
  result=$(execute_query "SELECT count() FROM system.tables WHERE database = '$CLICKHOUSE_DB' AND name = '$table_name'" 2>&1)
  [ "$result" -eq 1 ]
}

# ============================================
# Main Initialization
# ============================================
main() {
  log_info "=========================================="
  log_info "ClickHouse Initialization"
  log_info "=========================================="
  log_info "Host: $CLICKHOUSE_HOST:$CLICKHOUSE_PORT"
  log_info "User: $CLICKHOUSE_USER"
  log_info "Database: $CLICKHOUSE_DB"
  log_info "=========================================="

  # Step 1: Wait for ClickHouse
  wait_for_clickhouse || exit 1

  # Step 2: Create database
  if database_exists "$CLICKHOUSE_DB"; then
    log_info "Database '$CLICKHOUSE_DB' already exists (skipping creation)"
  else
    execute_query "CREATE DATABASE $CLICKHOUSE_DB" "Creating database '$CLICKHOUSE_DB'"
  fi

  # Step 3: Create schema (tables)
  if table_exists "events"; then
    log_info "Core tables already exist (skipping schema.sql)"
  else
    execute_sql_file "$SCRIPT_DIR/schema.sql" "Creating tables (schema.sql)"
  fi

  # Step 4: Create Kafka engines
  if table_exists "events_kafka"; then
    log_info "Kafka engines already exist (skipping kafka-engines.sql)"
  else
    execute_sql_file "$SCRIPT_DIR/kafka-engines.sql" "Creating Kafka engines (kafka-engines.sql)"
  fi

  # Step 5: Create materialized views
  if execute_query "SELECT count() FROM system.tables WHERE database = '$CLICKHOUSE_DB' AND name LIKE 'mv_%'" 2>&1 | grep -q "^[1-9]"; then
    log_info "Materialized views already exist (skipping materialized-views.sql)"
  else
    execute_sql_file "$SCRIPT_DIR/materialized-views.sql" "Creating materialized views (materialized-views.sql)"
  fi

  # Step 6: Verify setup
  log_info "=========================================="
  log_info "Verification"
  log_info "=========================================="

  local table_count
  table_count=$(execute_query "SELECT count() FROM system.tables WHERE database = '$CLICKHOUSE_DB'" 2>&1)
  log_info "Total tables created: $table_count"

  local mv_count
  mv_count=$(execute_query "SELECT count() FROM system.tables WHERE database = '$CLICKHOUSE_DB' AND name LIKE 'mv_%'" 2>&1)
  log_info "Materialized views created: $mv_count"

  local kafka_count
  kafka_count=$(execute_query "SELECT count() FROM system.tables WHERE database = '$CLICKHOUSE_DB' AND engine = 'Kafka'" 2>&1)
  log_info "Kafka engines created: $kafka_count"

  # Step 7: Show table list
  log_info "=========================================="
  log_info "Table List"
  log_info "=========================================="
  execute_query "SELECT name, engine, total_rows, formatReadableSize(total_bytes) as size FROM system.tables WHERE database = '$CLICKHOUSE_DB' ORDER BY name FORMAT PrettyCompact" || true

  # Step 8: Optional - Load test data
  if [ "${LOAD_TEST_DATA:-false}" = "true" ]; then
    log_info "=========================================="
    log_info "Loading Test Data"
    log_info "=========================================="
    if [ -f "$SCRIPT_DIR/queries/test-data.sql" ]; then
      execute_sql_file "$SCRIPT_DIR/queries/test-data.sql" "Loading test data"
    else
      log_warn "Test data file not found: $SCRIPT_DIR/queries/test-data.sql"
    fi
  fi

  log_info "=========================================="
  log_info "Initialization Complete!"
  log_info "=========================================="
  log_info "Database: $CLICKHOUSE_DB"
  log_info "Tables: $table_count"
  log_info "Materialized Views: $mv_count"
  log_info "Kafka Engines: $kafka_count"
  log_info "=========================================="
  log_info "Next Steps:"
  log_info "1. Start Kafka producers to send events"
  log_info "2. Monitor ingestion: SELECT count(*) FROM events"
  log_info "3. Run test queries in queries/feed-ranking.sql"
  log_info "=========================================="
}

# ============================================
# Error Handling
# ============================================
trap 'log_error "Script failed at line $LINENO"' ERR

# ============================================
# Execute
# ============================================
main "$@"
