#!/bin/bash
# Seed Data Initialization Script
# Populates staging/development databases with test data for E2E testing
#
# Usage:
#   ./run_seed_data.sh [environment]
#
# Arguments:
#   environment: staging (default) | local
#
# Environment Variables Required:
#   DB_HOST: PostgreSQL host
#   DB_USER: Database user
#   DB_PASSWORD: Database password
#   DB_PORT: PostgreSQL port (default: 5432)

set -euo pipefail

ENVIRONMENT="${1:-staging}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate environment
if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "local" ]]; then
    log_error "Invalid environment: $ENVIRONMENT. Must be 'staging' or 'local'"
    exit 1
fi

if [[ "$ENVIRONMENT" == "production" ]]; then
    log_error "NEVER run seed data in production!"
    exit 1
fi

# Check required environment variables
if [[ -z "${DB_HOST:-}" ]]; then
    log_error "DB_HOST is not set"
    exit 1
fi

if [[ -z "${DB_PASSWORD:-}" ]]; then
    log_error "DB_PASSWORD is not set"
    exit 1
fi

DB_USER="${DB_USER:-nova}"
DB_PORT="${DB_PORT:-5432}"

log_info "Starting seed data initialization for environment: $ENVIRONMENT"
log_info "Database host: $DB_HOST:$DB_PORT"

# Function to execute SQL file on a specific database
execute_sql() {
    local database=$1
    local sql_file=$2

    log_info "Executing $sql_file on database: $database"

    PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$database" \
        -f "$sql_file" \
        --set ON_ERROR_STOP=on \
        --quiet

    if [[ $? -eq 0 ]]; then
        log_info "✓ Successfully executed $sql_file"
    else
        log_error "✗ Failed to execute $sql_file"
        return 1
    fi
}

# Execute seed data scripts in order
log_info "=== Seeding auth-service data ==="
execute_sql "nova_auth" "$SCRIPT_DIR/01_seed_auth_users.sql"

log_info "=== Seeding user-service data ==="
execute_sql "nova_user" "$SCRIPT_DIR/02_seed_user_profiles.sql"

log_info "=== Seeding content-service data ==="
execute_sql "nova_content" "$SCRIPT_DIR/03_seed_content_posts.sql"

log_info "=== Seeding messaging-service data ==="
execute_sql "nova_messaging" "$SCRIPT_DIR/04_seed_messaging_conversations.sql"

log_info "=== Seed data initialization complete ==="
log_info ""
log_info "Test user credentials (all users):"
log_info "  Email: alice@test.nova.com, bob@test.nova.com, charlie@test.nova.com, etc."
log_info "  Password: TestPass123!"
log_info ""
log_info "You can now run E2E tests with real data!"
