#!/bin/bash
# ============================================
# ClickHouse SQL syntax validator
# Validates all SQL files without executing them
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERROR_COUNT=0

echo "=== ClickHouse SQL Syntax Validation ==="
echo ""

# Function to validate SQL file syntax
validate_file() {
    local file="$1"
    local name=$(basename "$file")

    echo -n "Validating $name... "

    # Basic syntax checks
    # 1. Check for balanced parentheses
    if ! python3 -c "
import sys
content = open('$file').read()
if content.count('(') != content.count(')'):
    sys.exit(1)
" 2>/dev/null; then
        echo "❌ FAILED - Unbalanced parentheses"
        ((ERROR_COUNT++))
        return 1
    fi

    # 2. Check for SQL keywords (basic validation)
    if ! grep -qE "(CREATE|SELECT|INSERT|ALTER|DROP)" "$file"; then
        echo "❌ FAILED - No SQL statements found"
        ((ERROR_COUNT++))
        return 1
    fi

    # 3. Check for ClickHouse-specific syntax
    if grep -qE "CREATE TABLE" "$file"; then
        if ! grep -qE "ENGINE\s*=" "$file"; then
            echo "❌ FAILED - CREATE TABLE without ENGINE"
            ((ERROR_COUNT++))
            return 1
        fi
    fi

    # 4. Check for semicolon at end of statements (optional but recommended)
    if ! grep -qE ";(\s*--.*)?$" "$file"; then
        echo "⚠️  WARNING - No semicolon at end of file"
    fi

    echo "✅ PASSED"
    return 0
}

# Validate table DDL files
echo "=== 1. Validating Table DDL Files ==="
for file in "$SCRIPT_DIR"/tables/*.sql; do
    if [ -f "$file" ]; then
        validate_file "$file"
    fi
done
echo ""

# Validate materialized view files
echo "=== 2. Validating Materialized View Files ==="
for file in "$SCRIPT_DIR"/views/*.sql; do
    if [ -f "$file" ]; then
        validate_file "$file"
    fi
done
echo ""

# Validate Kafka engine files
echo "=== 3. Validating Kafka Engine Files ==="
for file in "$SCRIPT_DIR"/engines/*.sql; do
    if [ -f "$file" ]; then
        validate_file "$file"
    fi
done
echo ""

# Validate query files
echo "=== 4. Validating Query Files ==="
for file in "$SCRIPT_DIR"/queries/*.sql; do
    if [ -f "$file" ]; then
        validate_file "$file"
    fi
done
echo ""

# Validate initialization scripts
echo "=== 5. Validating Initialization Scripts ==="
for file in "$SCRIPT_DIR"/init*.sql "$SCRIPT_DIR"/verify*.sql; do
    if [ -f "$file" ]; then
        validate_file "$file"
    fi
done
echo ""

# Summary
echo "=== Validation Summary ==="
if [ $ERROR_COUNT -eq 0 ]; then
    echo "✅ All SQL files passed validation!"
    echo ""
    echo "Next steps:"
    echo "1. Start ClickHouse server (docker-compose up clickhouse)"
    echo "2. Run initialization: clickhouse-client --multiquery < init_all.sql"
    echo "3. Verify setup: clickhouse-client --multiquery < verify_setup.sql"
    exit 0
else
    echo "❌ $ERROR_COUNT file(s) failed validation"
    echo "Please fix the errors and run again."
    exit 1
fi
