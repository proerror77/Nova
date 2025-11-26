#!/bin/bash
# Framework Compliance Scanner for Nova Social
# Detects common violations of best practices across all components
# Usage: ./framework-compliance-scanner.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="${REPO_ROOT}/backend"
IOS="${REPO_ROOT}/ios"
K8S="${REPO_ROOT}/k8s"

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CRITICAL_ISSUES=0
HIGH_ISSUES=0
MEDIUM_ISSUES=0
LOW_ISSUES=0

# Utility functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

report_critical() {
    echo -e "${RED}[CRITICAL]${NC} $1"
    ((CRITICAL_ISSUES++))
}

report_high() {
    echo -e "${RED}[HIGH]${NC} $1"
    ((HIGH_ISSUES++))
}

report_medium() {
    echo -e "${YELLOW}[MEDIUM]${NC} $1"
    ((MEDIUM_ISSUES++))
}

report_low() {
    echo -e "${YELLOW}[LOW]${NC} $1"
    ((LOW_ISSUES++))
}

report_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

# ============================================================================
# RUST CHECKS
# ============================================================================

check_rust_unwrap() {
    print_header "Rust: Unwrap() Usage"

    local count=$(find "$BACKEND" -name "*.rs" -not -path "*/target/*" -exec grep -l "\.unwrap()" {} \; | wc -l)
    if [ "$count" -gt 5 ]; then
        report_critical "Found $count files with .unwrap() calls (limit: 5)"
    elif [ "$count" -gt 0 ]; then
        report_high "Found $count files with .unwrap() calls"
    else
        report_pass "No .unwrap() calls in critical paths"
    fi

    # Check specific dangerous patterns
    if grep -r "connect()\.unwrap()" "$BACKEND" --include="*.rs" --exclude-dir=target >/dev/null 2>&1; then
        report_critical ".unwrap() on database connection (PANIC on timeout)"
    fi

    if grep -r "from_shared.*\.unwrap()" "$BACKEND" --include="*.rs" --exclude-dir=target >/dev/null 2>&1; then
        report_critical ".unwrap() on gRPC endpoint URL parsing"
    fi
}

check_rust_timeouts() {
    print_header "Rust: gRPC Call Timeouts"

    local timeout_missing=$(grep -r "client\." "$BACKEND/graphql-gateway/src" --include="*.rs" | grep -v "tokio::time::timeout" | wc -l)

    if [ "$timeout_missing" -gt 10 ]; then
        report_high "Found ~$timeout_missing gRPC calls without timeout wrapper"
    fi

    if grep -r "tokio::time::timeout" "$BACKEND/graphql-gateway/src" --include="*.rs" | grep -q "Duration::from_secs(30)"; then
        report_pass "Proper timeout configuration found"
    fi
}

check_rust_edition() {
    print_header "Rust: Edition 2021 Compliance"

    local non_2021=$(find "$BACKEND" -name "Cargo.toml" -exec grep -L 'edition = "2021"' {} \;)

    if [ -z "$non_2021" ]; then
        report_pass "All Cargo.toml files use Edition 2021"
    else
        report_medium "Found Cargo.toml files not using Edition 2021"
        echo "$non_2021" | while read -r file; do
            echo "  - $file"
        done
    fi
}

check_rust_async_patterns() {
    print_header "Rust: Async/Await Patterns"

    if grep -r "block_on\|run\|Runtime::new" "$BACKEND" --include="*.rs" --exclude-dir=target >/dev/null 2>&1; then
        report_high "Found blocking runtime calls in async code"
    else
        report_pass "No blocking runtime calls detected"
    fi

    if grep -r "#\[tokio::test\]" "$BACKEND" --include="*.rs" >/dev/null 2>&1; then
        report_pass "Using tokio::test for async tests"
    else
        report_medium "Some test files may not use tokio::test"
    fi
}

# ============================================================================
# iOS CHECKS
# ============================================================================

check_ios_memory_safety() {
    print_header "iOS: Memory Safety"

    local weak_count=$(find "$IOS" -name "*.swift" -exec grep -l "\[weak self\]" {} \; | wc -l)

    if [ "$weak_count" -eq 0 ]; then
        report_critical "No weak self references found - potential memory leaks"
    else
        report_pass "Found $weak_count files using weak self captures"
    fi

    # Check for synchronous URLSession
    if grep -r "URLSession\.shared" "$IOS/NovaSocial" --include="*.swift" >/dev/null 2>&1; then
        report_medium "Found hardcoded URLSession.shared usage"
    fi
}

check_ios_error_handling() {
    print_header "iOS: Error Handling"

    # Check for force unwrap
    local force_unwraps=$(find "$IOS" -name "*.swift" -exec grep -c "!" {} \; | awk '{sum+=$1} END {print sum}')

    if [ "$force_unwraps" -gt 50 ]; then
        report_high "Found $force_unwraps force unwraps (goal: <20)"
    else
        report_pass "Force unwrap usage under control"
    fi

    # Check for error boundary patterns
    if grep -r "enum.*LoadingState\|enum.*State" "$IOS" --include="*.swift" >/dev/null 2>&1; then
        report_pass "State machine pattern detected"
    else
        report_high "Missing state machine pattern for error/loading states"
    fi
}

check_ios_protocols() {
    print_header "iOS: Protocol-Oriented Design"

    if grep -r "protocol.*Service" "$IOS" --include="*.swift" >/dev/null 2>&1; then
        report_pass "Service protocols defined"
    else
        report_medium "Consider defining protocols for service classes"
    fi
}

# ============================================================================
# gRPC CHECKS
# ============================================================================

check_grpc_health_checks() {
    print_header "gRPC: Health Checks"

    local services=$(find "$BACKEND" -type d -name "*-service" -not -path "*/target/*")
    local health_count=0

    for service in $services; do
        if grep -r "tonic_health\|HealthCheck" "$service/src" --include="*.rs" >/dev/null 2>&1; then
            ((health_count++))
        fi
    done

    local total=$(echo "$services" | wc -w)

    if [ "$health_count" -eq "$total" ]; then
        report_pass "All services have health checks"
    else
        report_high "$((total - health_count)) services missing health checks"
    fi
}

check_grpc_interceptors() {
    print_header "gRPC: Interceptors & Middleware"

    if grep -r "layer\|interceptor\|middleware" "$BACKEND/graphql-gateway/src" --include="*.rs" >/dev/null 2>&1; then
        report_pass "gRPC middleware/interceptors configured"
    else
        report_high "Missing gRPC middleware configuration"
    fi
}

# ============================================================================
# GraphQL CHECKS
# ============================================================================

check_graphql_security() {
    print_header "GraphQL: Security Configuration"

    if grep -q "GRAPHQL_INTROSPECTION.*false" "$K8s/graphql-gateway/deployment.yaml" 2>/dev/null; then
        report_pass "Introspection disabled in production"
    else
        report_critical "GraphQL introspection enabled in production config"
    fi

    if grep -q "GRAPHQL_PLAYGROUND.*false" "$K8s/graphql-gateway/deployment.yaml" 2>/dev/null; then
        report_pass "GraphQL playground disabled in production"
    else
        report_high "GraphQL playground enabled in production config"
    fi
}

check_graphql_complexity() {
    print_header "GraphQL: Complexity & Performance"

    if grep -q "GRAPHQL_MAX_COMPLEXITY\|GRAPHQL_MAX_DEPTH" "$K8s/graphql-gateway/deployment.yaml" 2>/dev/null; then
        report_pass "Query complexity limits configured"
    else
        report_medium "Consider adding query complexity limits"
    fi

    # Check for DataLoader implementations
    if grep -r "todo\|TODO\|stub\|STUB" "$BACKEND/graphql-gateway/src/schema/loaders" --include="*.rs" 2>/dev/null | grep -q "DataLoader\|batch"; then
        report_high "DataLoader implementations have stub/TODO comments"
    fi
}

# ============================================================================
# KUBERNETES CHECKS
# ============================================================================

check_k8s_security_context() {
    print_header "Kubernetes: Security Context"

    local deployments=$(find "$K8s" -name "deployment.yaml" -o -name "*deployment*.yaml")
    local with_security=0
    local total=0

    for deploy in $deployments; do
        ((total++))
        if grep -q "securityContext" "$deploy"; then
            ((with_security++))
        fi
    done

    if [ "$with_security" -eq "$total" ]; then
        report_pass "All deployments have security context"
    else
        report_critical "$((total - with_security)) deployments missing securityContext"
    fi
}

check_k8s_resource_limits() {
    print_header "Kubernetes: Resource Limits"

    local deployments=$(find "$K8s" -name "deployment.yaml" -o -name "*deployment*.yaml")
    local with_limits=0
    local total=0

    for deploy in $deployments; do
        ((total++))
        if grep -q "limits:" "$deploy"; then
            ((with_limits++))
        fi
    done

    if [ "$with_limits" -eq "$total" ]; then
        report_pass "All deployments have resource limits"
    else
        report_high "$((total - with_limits)) deployments missing resource limits"
    fi
}

check_k8s_network_policies() {
    print_header "Kubernetes: Network Policies"

    local policies=$(find "$K8s" -name "*network-policy*" -o -name "*netpol*" | wc -l)

    if [ "$policies" -gt 0 ]; then
        report_pass "Found $policies network policies"
    else
        report_critical "No network policies found (all pods can communicate)"
    fi
}

check_k8s_rbac() {
    print_header "Kubernetes: RBAC"

    local roles=$(find "$K8s" -name "*role*" | grep -E "Role\|ClusterRole" | wc -l)

    if [ "$roles" -gt 0 ]; then
        report_pass "Found $roles RBAC definitions"
    else
        report_high "Consider implementing RBAC for service accounts"
    fi
}

# ============================================================================
# DATABASE CHECKS
# ============================================================================

check_database_migrations() {
    print_header "Database: Migration Patterns"

    local migrations=$(find "$BACKEND/migrations" -name "*.sql" 2>/dev/null | wc -l)

    if [ "$migrations" -gt 0 ]; then
        # Check for direct drops
        local drops=$(grep -r "DROP\|TRUNCATE" "$BACKEND/migrations" --include="*.sql" 2>/dev/null | grep -v "DROP IF" | wc -l)

        if [ "$drops" -gt 0 ]; then
            report_high "Found $drops unprotected DROP statements in migrations"
        else
            report_pass "No unprotected DROP statements found"
        fi

        # Check for triggers
        local triggers=$(grep -r "CREATE.*TRIGGER\|CREATE FUNCTION" "$BACKEND/migrations" --include="*.sql" 2>/dev/null | wc -l)

        if [ "$triggers" -gt 0 ]; then
            report_medium "Found $triggers triggers/functions (consider moving logic to app)"
        fi
    fi
}

# ============================================================================
# TESTING CHECKS
# ============================================================================

check_test_coverage() {
    print_header "Testing: Coverage"

    local test_files=$(find "$BACKEND" -name "*test*.rs" -not -path "*/target/*" | wc -l)
    local src_files=$(find "$BACKEND" -name "*.rs" -not -path "*/target/*" -not -name "*test*" | wc -l)

    if [ "$test_files" -gt 0 ]; then
        local ratio=$((test_files * 100 / src_files))
        if [ "$ratio" -ge 20 ]; then
            report_pass "Test coverage ratio: $ratio% ($test_files test files)"
        else
            report_medium "Low test coverage ratio: $ratio% (goal: 20%+)"
        fi
    fi
}

check_error_path_tests() {
    print_header "Testing: Error Path Coverage"

    local error_tests=$(grep -r "#\[test\].*error\|#\[test\].*fail" "$BACKEND" --include="*.rs" | wc -l)

    if [ "$error_tests" -gt 10 ]; then
        report_pass "Found $error_tests error path tests"
    else
        report_high "Missing error path tests (found $error_tests, goal: 10+)"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     Nova Social - Framework Compliance Scanner            ║"
    echo "║     Checking: Rust, iOS, gRPC, GraphQL, K8s, Database     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Rust checks
    check_rust_unwrap
    check_rust_timeouts
    check_rust_edition
    check_rust_async_patterns

    # iOS checks
    check_ios_memory_safety
    check_ios_error_handling
    check_ios_protocols

    # gRPC checks
    check_grpc_health_checks
    check_grpc_interceptors

    # GraphQL checks
    check_graphql_security
    check_graphql_complexity

    # Kubernetes checks
    check_k8s_security_context
    check_k8s_resource_limits
    check_k8s_network_policies
    check_k8s_rbac

    # Database checks
    check_database_migrations

    # Testing checks
    check_test_coverage
    check_error_path_tests

    # Summary
    print_header "SUMMARY"

    local total=$((CRITICAL_ISSUES + HIGH_ISSUES + MEDIUM_ISSUES + LOW_ISSUES))

    echo "Total Issues Found: $total"
    echo -e "  ${RED}Critical: $CRITICAL_ISSUES${NC}"
    echo -e "  ${RED}High: $HIGH_ISSUES${NC}"
    echo -e "  ${YELLOW}Medium: $MEDIUM_ISSUES${NC}"
    echo -e "  ${YELLOW}Low: $LOW_ISSUES${NC}"

    # Calculate score
    local score=$((100 - (CRITICAL_ISSUES * 10 + HIGH_ISSUES * 5 + MEDIUM_ISSUES * 2 + LOW_ISSUES)))
    [ "$score" -lt 0 ] && score=0

    echo -e "\n${BLUE}Compliance Score: ${GREEN}$score/100${NC}"

    if [ "$score" -ge 80 ]; then
        echo -e "${GREEN}Status: GOOD - Minor improvements needed${NC}"
        return 0
    elif [ "$score" -ge 60 ]; then
        echo -e "${YELLOW}Status: FAIR - Systematic improvements required${NC}"
        return 1
    else
        echo -e "${RED}Status: POOR - Critical issues must be addressed${NC}"
        return 2
    fi
}

main "$@"
