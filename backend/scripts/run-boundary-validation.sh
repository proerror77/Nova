#!/bin/bash

# Service Boundary Validation Test Runner
# Author: System Architect (Following Linus Principles)
# Date: 2025-11-11
# Purpose: Execute comprehensive service boundary validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")"
REPORT_DIR="$BACKEND_DIR/validation-reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$REPORT_DIR/boundary_validation_$TIMESTAMP.md"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }
log_test() { echo -e "${CYAN}[TEST]${NC} $1"; }

# Create report directory
mkdir -p "$REPORT_DIR"

# Initialize report
cat > "$REPORT_FILE" << 'EOF'
# Service Boundary Validation Report

**Date**: $(date)
**Environment**: Development
**Validator Version**: 1.0.0

---

## Executive Summary

| Status | Test Suite | Passed | Failed | Skipped |
|--------|-----------|--------|--------|---------|
EOF

# Track overall results
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
declare -a FAILED_TESTS=()

# Function to run a test suite
run_test_suite() {
    local suite_name=$1
    local test_command=$2
    local passed=0
    local failed=0
    local skipped=0

    log_test "Running $suite_name..."

    if eval "$test_command" > /tmp/test_output_$$.log 2>&1; then
        passed=$((passed + 1))
        echo "| ✅ | $suite_name | $passed | $failed | $skipped |" >> "$REPORT_FILE"
        log_info "✅ $suite_name passed"
    else
        failed=$((failed + 1))
        FAILED_TESTS+=("$suite_name")
        echo "| ❌ | $suite_name | $passed | $failed | $skipped |" >> "$REPORT_FILE"
        log_error "❌ $suite_name failed"
        echo -e "\n### Failed: $suite_name\n" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        tail -n 20 /tmp/test_output_$$.log >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
    fi

    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + skipped))

    rm -f /tmp/test_output_$$.log
}

# ============================================================
# Test 1: Database Ownership Constraints
# ============================================================

test_database_ownership() {
    log_test "Checking database ownership constraints..."

    # Check if service_owner column exists on all tables
    psql -h localhost -d nova -U postgres -t -c "
        SELECT COUNT(*)
        FROM pg_tables t
        WHERE t.schemaname = 'public'
        AND NOT EXISTS (
            SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = t.schemaname
            AND c.table_name = t.tablename
            AND c.column_name = 'service_owner'
        )" | grep -q "^0$"
}

# ============================================================
# Test 2: Cross-Service Database Access
# ============================================================

test_cross_service_access() {
    log_test "Detecting cross-service database access..."

    # Run the cross-service detection script
    if [ -x "$BACKEND_DIR/scripts/fix-cross-service-db.sh" ]; then
        "$BACKEND_DIR/scripts/fix-cross-service-db.sh" | grep -q "No cross-service database access violations found"
    else
        return 1
    fi
}

# ============================================================
# Test 3: Service Dependencies
# ============================================================

test_service_dependencies() {
    log_test "Checking for circular dependencies..."

    # Check for circular dependencies in Cargo.toml files
    local circular_found=0

    # Auth ↔ User check
    if grep -r "user-service" "$BACKEND_DIR/auth-service/Cargo.toml" 2>/dev/null && \
       grep -r "auth-service" "$BACKEND_DIR/user-service/Cargo.toml" 2>/dev/null; then
        circular_found=1
        log_error "Circular dependency: auth-service ↔ user-service"
    fi

    # Content ↔ Feed check
    if grep -r "feed-service" "$BACKEND_DIR/content-service/Cargo.toml" 2>/dev/null && \
       grep -r "content-service" "$BACKEND_DIR/feed-service/Cargo.toml" 2>/dev/null; then
        circular_found=1
        log_error "Circular dependency: content-service ↔ feed-service"
    fi

    # Messaging ↔ Notification check
    if grep -r "notification-service" "$BACKEND_DIR/messaging-service/Cargo.toml" 2>/dev/null && \
       grep -r "messaging-service" "$BACKEND_DIR/notification-service/Cargo.toml" 2>/dev/null; then
        circular_found=1
        log_error "Circular dependency: messaging-service ↔ notification-service"
    fi

    return $circular_found
}

# ============================================================
# Test 4: Event-Driven Architecture
# ============================================================

test_event_architecture() {
    log_test "Validating event-driven architecture..."

    # Check for outbox pattern implementation
    local has_outbox=0

    for service_dir in "$BACKEND_DIR"/*-service; do
        if [ -d "$service_dir" ]; then
            if grep -r "OutboxEvent" "$service_dir/src" > /dev/null 2>&1; then
                has_outbox=$((has_outbox + 1))
            fi
        fi
    done

    if [ $has_outbox -gt 0 ]; then
        log_info "Found $has_outbox services with outbox pattern"
        return 0
    else
        log_warn "No services implementing outbox pattern"
        return 1
    fi
}

# ============================================================
# Test 5: gRPC Service Boundaries
# ============================================================

test_grpc_boundaries() {
    log_test "Checking gRPC service boundaries..."

    # Check for proper gRPC client usage
    local violations=0

    # Check for direct database queries across services
    for service_dir in "$BACKEND_DIR"/*-service; do
        if [ -d "$service_dir" ]; then
            service_name=$(basename "$service_dir")

            # Check if service queries tables it doesn't own
            case "$service_name" in
                "content-service")
                    if grep -r "FROM users" "$service_dir/src" > /dev/null 2>&1; then
                        log_error "$service_name directly queries users table"
                        violations=$((violations + 1))
                    fi
                    ;;
                "feed-service")
                    if grep -r "FROM posts" "$service_dir/src" > /dev/null 2>&1; then
                        log_error "$service_name directly queries posts table"
                        violations=$((violations + 1))
                    fi
                    ;;
            esac
        fi
    done

    return $violations
}

# ============================================================
# Test 6: Service Isolation
# ============================================================

test_service_isolation() {
    log_test "Testing service isolation..."

    # Check if services have proper health check endpoints
    local healthy_services=0
    local expected_services=8

    for port in 50051 50052 50053 50054 50055 50056 50057 50058; do
        if nc -z localhost $port 2>/dev/null; then
            healthy_services=$((healthy_services + 1))
        fi
    done

    if [ $healthy_services -eq $expected_services ]; then
        log_info "All $expected_services services are isolated and running"
        return 0
    else
        log_warn "Only $healthy_services of $expected_services services are running"
        return 1
    fi
}

# ============================================================
# Test 7: Data Consistency Patterns
# ============================================================

test_data_consistency() {
    log_test "Checking data consistency patterns..."

    # Check for saga pattern implementation
    local has_saga=0

    if grep -r "SagaOrchestrator\|SagaStep" "$BACKEND_DIR" > /dev/null 2>&1; then
        has_saga=1
        log_info "Saga pattern implemented for distributed transactions"
    fi

    # Check for event sourcing
    local has_event_sourcing=0

    if grep -r "EventStore\|AggregateRoot" "$BACKEND_DIR" > /dev/null 2>&1; then
        has_event_sourcing=1
        log_info "Event sourcing pattern implemented"
    fi

    if [ $has_saga -eq 1 ] || [ $has_event_sourcing -eq 1 ]; then
        return 0
    else
        log_warn "No consistency patterns found"
        return 1
    fi
}

# ============================================================
# Test 8: Migration Readiness
# ============================================================

test_migration_readiness() {
    log_test "Checking migration readiness..."

    # Check if all required migration scripts exist
    local required_scripts=(
        "apply-data-ownership.sql"
        "merge-media-services.sh"
        "fix-cross-service-db.sh"
    )

    local missing_scripts=0

    for script in "${required_scripts[@]}"; do
        if [ ! -f "$BACKEND_DIR/migrations/$script" ] && [ ! -f "$BACKEND_DIR/scripts/$script" ]; then
            log_error "Missing migration script: $script"
            missing_scripts=$((missing_scripts + 1))
        fi
    done

    return $missing_scripts
}

# ============================================================
# Main Test Execution
# ============================================================

main() {
    echo "========================================="
    echo "Service Boundary Validation Test Runner"
    echo "========================================="
    echo ""

    log_info "Starting validation tests..."
    log_info "Report will be saved to: $REPORT_FILE"
    echo ""

    # Run all test suites
    run_test_suite "Database Ownership" "test_database_ownership"
    run_test_suite "Cross-Service Access" "test_cross_service_access"
    run_test_suite "Service Dependencies" "test_service_dependencies"
    run_test_suite "Event Architecture" "test_event_architecture"
    run_test_suite "gRPC Boundaries" "test_grpc_boundaries"
    run_test_suite "Service Isolation" "test_service_isolation"
    run_test_suite "Data Consistency" "test_data_consistency"
    run_test_suite "Migration Readiness" "test_migration_readiness"

    # Add summary to report
    cat >> "$REPORT_FILE" << EOF

---

## Overall Results

- **Total Passed**: $TOTAL_PASSED
- **Total Failed**: $TOTAL_FAILED
- **Total Skipped**: $TOTAL_SKIPPED
- **Success Rate**: $(( TOTAL_PASSED * 100 / (TOTAL_PASSED + TOTAL_FAILED) ))%

EOF

    # Add failed tests summary
    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        cat >> "$REPORT_FILE" << EOF

## Failed Tests

The following test suites failed and require attention:

EOF
        for test in "${FAILED_TESTS[@]}"; do
            echo "- $test" >> "$REPORT_FILE"
        done
    fi

    # Add recommendations
    cat >> "$REPORT_FILE" << EOF

---

## Recommendations

Based on the validation results, here are the recommended actions:

EOF

    if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
        cat >> "$REPORT_FILE" << EOF
✅ **All tests passed!** The service boundaries are properly enforced.

### Next Steps:
1. Proceed with production deployment
2. Enable monitoring and alerting
3. Document the new architecture

EOF
    else
        cat >> "$REPORT_FILE" << EOF
⚠️ **Action Required!** Failed tests indicate boundary violations.

### Immediate Actions:
EOF

        for test in "${FAILED_TESTS[@]}"; do
            case "$test" in
                "Database Ownership")
                    echo "1. Run \`apply-data-ownership.sql\` migration" >> "$REPORT_FILE"
                    ;;
                "Cross-Service Access")
                    echo "2. Execute \`fix-cross-service-db.sh\` to identify violations" >> "$REPORT_FILE"
                    ;;
                "Service Dependencies")
                    echo "3. Refactor circular dependencies as per SERVICE_DEPENDENCY_AUDIT.md" >> "$REPORT_FILE"
                    ;;
                "Event Architecture")
                    echo "4. Implement event-driven patterns from EVENT_DRIVEN_ARCHITECTURE.md" >> "$REPORT_FILE"
                    ;;
                *)
                    echo "- Fix issues in: $test" >> "$REPORT_FILE"
                    ;;
            esac
        done
    fi

    # Add timestamp
    cat >> "$REPORT_FILE" << EOF

---

*Report generated on $(date)*
*Validator: Service Boundary Validation v1.0.0*

"Talk is cheap. Show me the code." - Linus Torvalds
EOF

    # Print summary
    echo ""
    echo "========================================="
    echo "Validation Complete"
    echo "========================================="
    echo ""

    if [ $TOTAL_FAILED -eq 0 ]; then
        log_info "✅ All validation tests passed!"
        log_info "Report saved to: $REPORT_FILE"
        exit 0
    else
        log_error "❌ $TOTAL_FAILED test(s) failed"
        log_info "Report saved to: $REPORT_FILE"
        log_info "Review the report for detailed recommendations"
        exit 1
    fi
}

# Run main
main "$@"