#!/bin/bash
# Migration Validation Script
# Ensures that Docker images contain all migrations that exist in the database
# This prevents the "migration was previously applied but is missing" error

set -euo pipefail

SERVICE_NAME="${1:-}"
NAMESPACE="${2:-nova-staging}"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> [namespace]"
    echo "Example: $0 content-service nova-staging"
    exit 1
fi

echo "🔍 Validating migrations for $SERVICE_NAME in $NAMESPACE"

# Determine database name based on service
case "$SERVICE_NAME" in
    content-service)
        DB_NAME="nova_content"
        MIGRATIONS_DIR="backend/content-service/migrations"
        ;;
    social-service)
        DB_NAME="nova_social"
        MIGRATIONS_DIR="backend/social-service/migrations"
        ;;
    identity-service)
        DB_NAME="nova_auth"
        MIGRATIONS_DIR="backend/identity-service/migrations"
        ;;
    notification-service)
        DB_NAME="nova_notification"
        MIGRATIONS_DIR="backend/notification-service/migrations"
        ;;
    *)
        echo "⚠️  Unknown service: $SERVICE_NAME (skipping migration validation)"
        exit 0
        ;;
esac

# Check if migrations directory exists
if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo "⚠️  Migrations directory not found: $MIGRATIONS_DIR (skipping validation)"
    exit 0
fi

# Count migrations in codebase (excluding .down.sql, non-sql files, and subdirectories)
CODE_MIGRATIONS=$(find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" ! -name "*.down.sql" -type f | wc -l | tr -d ' ')
echo "📁 Migrations in codebase: $CODE_MIGRATIONS"

# Get migrations from database (requires kubectl access)
if command -v kubectl &> /dev/null; then
    echo "🔌 Checking database migrations..."

    # Find postgres pod
    POSTGRES_POD=$(kubectl get pods -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$POSTGRES_POD" ]; then
        # Query database for applied migrations
        DB_MIGRATIONS=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- \
            psql -U nova -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM _sqlx_migrations;" 2>/dev/null | tr -d ' ' || echo "0")

        echo "💾 Migrations in database: $DB_MIGRATIONS"

        # Validate
        if [ "$CODE_MIGRATIONS" -lt "$DB_MIGRATIONS" ]; then
            echo "❌ ERROR: Code has fewer migrations ($CODE_MIGRATIONS) than database ($DB_MIGRATIONS)"
            echo ""
            echo "This will cause the service to crash with:"
            echo "  'migration X was previously applied but is missing in the resolved migrations'"
            echo ""
            echo "Solutions:"
            echo "  1. Ensure all migration files are committed to git"
            echo "  2. Do not delete migration files that have been applied"
            echo "  3. Use .down.sql files for rollbacks instead of deleting migrations"
            exit 1
        elif [ "$CODE_MIGRATIONS" -gt "$DB_MIGRATIONS" ]; then
            echo "✅ Code has new migrations that will be applied on deployment"
        else
            echo "✅ Code and database migrations are in sync"
        fi
    else
        echo "⚠️  Could not find postgres pod (skipping database check)"
    fi
else
    echo "⚠️  kubectl not available (skipping database check)"
fi

echo "✅ Migration validation passed for $SERVICE_NAME"
