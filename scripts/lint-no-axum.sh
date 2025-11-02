#!/usr/bin/env bash
#
# CI lint script: Prevent Axum dependencies from entering the codebase
#

set -e

echo "🔍 Checking for banned Axum dependencies..."

# Check all Cargo.toml files for axum dependencies
AXUM_FOUND=$(grep -r "axum\s*=" backend/*/Cargo.toml || true)

if [ -n "$AXUM_FOUND" ]; then
    echo "❌ ERROR: Axum dependencies detected!"
    echo ""
    echo "$AXUM_FOUND"
    echo ""
    echo "ℹ️  Nova has migrated to Actix-Web."
    echo "ℹ️  Please use 'actix-web' instead of 'axum'."
    echo ""
    exit 1
fi

echo "✅ No Axum dependencies found"

# Check for tower dependencies (Axum ecosystem)
TOWER_FOUND=$(grep -r "tower\s*=" backend/*/Cargo.toml | grep -v "tower-service" || true)

if [ -n "$TOWER_FOUND" ]; then
    echo "⚠️  WARNING: Tower dependencies detected (Axum ecosystem)"
    echo ""
    echo "$TOWER_FOUND"
    echo ""
    echo "ℹ️  Consider using Actix middleware instead."
    echo ""
    # Warning only, not failing
fi

echo "🎉 Axum lint check passed!"
