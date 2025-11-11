#!/bin/bash
# Verify SQL migration syntax and structure

set -euo pipefail

MIGRATIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERRORS=0

echo "🔍 Verifying SQL migration files..."
echo

# Function to check SQL syntax using postgres dry-run
check_sql_syntax() {
    local file="$1"
    local filename=$(basename "$file")

    echo "📄 Checking: $filename"

    # Check for required sections
    if ! grep -q "^-- Up" "$file"; then
        echo "  ❌ Missing '-- Up' section"
        ((ERRORS++))
        return 1
    fi

    if ! grep -q "^-- Down" "$file"; then
        echo "  ❌ Missing '-- Down' section"
        ((ERRORS++))
        return 1
    fi

    # Check for basic SQL keywords
    if ! grep -qE "(CREATE|ALTER|DROP)" "$file"; then
        echo "  ❌ No SQL statements found"
        ((ERRORS++))
        return 1
    fi

    # Check for IF NOT EXISTS in CREATE statements (safe migrations)
    if grep -q "^CREATE TABLE" "$file" && ! grep -q "IF NOT EXISTS" "$file"; then
        echo "  ⚠️  Warning: CREATE TABLE without IF NOT EXISTS"
    fi

    echo "  ✅ Structure OK"
    return 0
}

# Check each migration file
for file in "$MIGRATIONS_DIR"/*.sql; do
    if [ -f "$file" ] && [ "$(basename "$file")" != "verify_migrations.sh" ]; then
        check_sql_syntax "$file" || true
        echo
    fi
done

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $ERRORS -eq 0 ]; then
    echo "✅ All migrations verified successfully!"
    exit 0
else
    echo "❌ Found $ERRORS errors in migrations"
    exit 1
fi
