#!/bin/bash

# ============================================================================
# Quick Win #4: Automated Testing & Validation Script
# ============================================================================
#
# Purpose: Automate testing of database index migration
# Usage: ./test_quick_win_4.sh [pre|post|rollback]
#
# ============================================================================

set -e

# Configuration
DB_NAME="${DB_NAME:-nova}"
DB_USER="${DB_USER:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
PSQL_CMD="psql -U $DB_USER -d $DB_NAME -h $DB_HOST -p $DB_PORT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ============================================================================
# PRE-MIGRATION TESTS
# ============================================================================

test_pre_migration() {
    print_header "Pre-Migration Tests"

    # Test 1: Verify indexes don't exist yet
    print_info "Checking if new indexes already exist..."
    EXISTING_INDEXES=$($PSQL_CMD -tc "
        SELECT COUNT(*) FROM pg_indexes
        WHERE indexname IN (
            'idx_messages_sender_created',
            'idx_posts_user_created'
        );
    " | tr -d ' ')

    if [ "$EXISTING_INDEXES" -eq 0 ]; then
        print_success "New indexes don't exist yet (expected)"
    else
        print_warning "New indexes already exist! May need to drop first"
    fi

    # Test 2: Check table sizes
    print_info "Checking table sizes..."
    MESSAGES_SIZE=$($PSQL_CMD -tc "
        SELECT pg_size_pretty(pg_total_relation_size('messages'));
    " | tr -d ' ')

    POSTS_SIZE=$($PSQL_CMD -tc "
        SELECT pg_size_pretty(pg_total_relation_size('posts'));
    " | tr -d ' ')

    print_success "messages table size: $MESSAGES_SIZE"
    print_success "posts table size: $POSTS_SIZE"

    # Test 3: Check disk space
    print_info "Checking available disk space..."
    DISK_USAGE=$($PSQL_CMD -tc "
        SELECT pg_size_pretty(pg_tablespace_size('pg_default'));
    " | tr -d ' ')

    print_success "Available disk space: $DISK_USAGE"

    # Test 4: Check for NULL values in key columns
    print_info "Checking for NULL values in indexed columns..."
    NULL_SENDERS=$($PSQL_CMD -tc "
        SELECT COUNT(*) FROM messages WHERE sender_id IS NULL;
    " | tr -d ' ')

    NULL_USERS=$($PSQL_CMD -tc "
        SELECT COUNT(*) FROM posts WHERE user_id IS NULL;
    " | tr -d ' ')

    if [ "$NULL_SENDERS" -eq 0 ] && [ "$NULL_USERS" -eq 0 ]; then
        print_success "No NULL values in indexed columns"
    else
        print_error "Found NULL values - may affect index selectivity"
    fi

    # Test 5: Verify WHERE filter effectiveness
    print_info "Checking WHERE filter selectivity..."
    ACTIVE_MESSAGES=$($PSQL_CMD -tc "
        SELECT ROUND(100.0 * COUNT(*) FILTER(WHERE deleted_at IS NULL) / COUNT(*), 2)
        FROM messages;
    " | tr -d ' ')

    ACTIVE_POSTS=$($PSQL_CMD -tc "
        SELECT ROUND(100.0 * COUNT(*) FILTER(WHERE deleted_at IS NULL) / COUNT(*), 2)
        FROM posts;
    " | tr -d ' ')

    print_success "Active messages: $ACTIVE_MESSAGES%"
    print_success "Active posts: $ACTIVE_POSTS%"

    print_success "Pre-migration tests complete!"
}

# ============================================================================
# POST-MIGRATION TESTS
# ============================================================================

test_post_migration() {
    print_header "Post-Migration Tests"

    # Test 1: Verify indexes exist
    print_info "Verifying indexes were created..."
    INDEX_COUNT=$($PSQL_CMD -tc "
        SELECT COUNT(*) FROM pg_indexes
        WHERE indexname IN (
            'idx_messages_sender_created',
            'idx_posts_user_created'
        );
    " | tr -d ' ')

    if [ "$INDEX_COUNT" -eq 2 ]; then
        print_success "Both indexes created successfully"
    else
        print_error "Expected 2 indexes, found $INDEX_COUNT"
        return 1
    fi

    # Test 2: Check index sizes
    print_info "Checking index sizes..."
    MESSAGES_INDEX_SIZE=$($PSQL_CMD -tc "
        SELECT pg_size_pretty(pg_relation_size(indexrelid))
        FROM pg_stat_user_indexes
        WHERE indexname = 'idx_messages_sender_created';
    " | tr -d ' ')

    POSTS_INDEX_SIZE=$($PSQL_CMD -tc "
        SELECT pg_size_pretty(pg_relation_size(indexrelid))
        FROM pg_stat_user_indexes
        WHERE indexname = 'idx_posts_user_created';
    " | tr -d ' ')

    print_success "messages index size: $MESSAGES_INDEX_SIZE"
    print_success "posts index size: $POSTS_INDEX_SIZE"

    # Test 3: Verify index validity
    print_info "Verifying index validity..."

    MESSAGES_VALID=$($PSQL_CMD -tc "
        SELECT indisvalid FROM pg_index
        WHERE indexrelid::regclass::text = 'idx_messages_sender_created';
    " | tr -d ' ')

    POSTS_VALID=$($PSQL_CMD -tc "
        SELECT indisvalid FROM pg_index
        WHERE indexrelid::regclass::text = 'idx_posts_user_created';
    " | tr -d ' ')

    if [ "$MESSAGES_VALID" = "t" ] && [ "$POSTS_VALID" = "t" ]; then
        print_success "Both indexes are valid"
    else
        print_error "One or more indexes are invalid"
    fi

    print_success "Post-migration tests complete!"
}

# ============================================================================
# HEALTH CHECK
# ============================================================================

test_health() {
    print_header "Health Check"

    # Test 1: Database connection
    print_info "Testing database connection..."
    if $PSQL_CMD -tc "SELECT 1;" > /dev/null 2>&1; then
        print_success "Database connection OK"
    else
        print_error "Database connection failed"
        return 1
    fi

    # Test 2: Required tables exist
    print_info "Checking required tables..."
    TABLES=$($PSQL_CMD -tc "
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_name IN ('messages', 'posts', 'users');
    " | tr -d ' ')

    if [ "$TABLES" -eq 3 ]; then
        print_success "All required tables exist"
    else
        print_error "Missing required tables"
        return 1
    fi

    # Test 3: Row counts
    print_info "Checking row counts..."
    MSG_COUNT=$($PSQL_CMD -tc "SELECT COUNT(*) FROM messages;" | tr -d ' ')
    POSTS_COUNT=$($PSQL_CMD -tc "SELECT COUNT(*) FROM posts;" | tr -d ' ')

    print_success "messages: $MSG_COUNT rows"
    print_success "posts: $POSTS_COUNT rows"

    print_success "Health check complete!"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_header "Quick Win #4: Test Suite"

    if [ -z "$1" ]; then
        print_error "Usage: $0 [pre|post|health]"
        echo ""
        echo "Options:"
        echo "  pre      - Run pre-migration baseline tests"
        echo "  post     - Run post-migration verification tests"
        echo "  health   - Run health checks"
        exit 1
    fi

    case "$1" in
        pre)
            test_pre_migration
            ;;
        post)
            test_post_migration
            ;;
        health)
            test_health
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
}

main "$@"
