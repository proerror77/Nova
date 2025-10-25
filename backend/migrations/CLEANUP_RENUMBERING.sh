#!/bin/bash
# Database Migration Cleanup Script
# This script removes conflicting migration files and keeps the renumbered versions
#
# Files to remove:
# - 031_experiments_schema.sql → kept as 033_experiments_schema.sql
# - 031_resumable_uploads.sql → kept as 034_resumable_uploads.sql
# - 031_trending_system.sql → kept as 035_trending_system.sql
# - 040_resumable_uploads.sql → duplicate, delete

set -e

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Migration directory: $MIGRATION_DIR"
echo ""

# Verify new files exist before deleting old ones
echo "✓ Checking for new renumbered migration files..."

for file in "033_experiments_schema.sql" "034_resumable_uploads.sql" "035_trending_system.sql"; do
    if [ ! -f "$MIGRATION_DIR/$file" ]; then
        echo "✗ ERROR: Missing $file"
        exit 1
    fi
    echo "  ✓ Found $file"
done

echo ""
echo "✓ All new migration files present"
echo ""

# Remove old conflicting files
echo "Removing old migration files..."

files_to_remove=(
    "031_experiments_schema.sql"
    "031_resumable_uploads.sql"
    "031_trending_system.sql"
    "040_resumable_uploads.sql"
)

for file in "${files_to_remove[@]}"; do
    if [ -f "$MIGRATION_DIR/$file" ]; then
        rm -v "$MIGRATION_DIR/$file"
        echo "  ✓ Removed $file"
    else
        echo "  ⚠ Not found: $file (already removed?)"
    fi
done

echo ""
echo "✓ Cleanup complete!"
echo ""
echo "Migration numbering status:"
ls -1 "$MIGRATION_DIR"/03*.sql | sort | sed 's/.*\//  /'
ls -1 "$MIGRATION_DIR"/04*.sql | sort | sed 's/.*\//  /'
echo ""
echo "✓ No more numbering conflicts!"
