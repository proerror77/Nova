#!/bin/bash
# Integration test runner for Nova Authentication Service
# Runs all test suites and generates coverage report

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Nova Authentication Service - Test Suite${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check environment variables
echo -e "${YELLOW}Checking environment variables...${NC}"
required_vars=("DATABASE_URL" "REDIS_URL" "JWT_PRIVATE_KEY" "JWT_PUBLIC_KEY")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo -e "${RED}Missing required environment variables:${NC}"
    printf '%s\n' "${missing_vars[@]}"
    echo -e "${YELLOW}Please set them in .env file or export them${NC}"
    exit 1
fi

echo -e "${GREEN}All required environment variables present${NC}\n"

# Ensure test database exists and is migrated
echo -e "${YELLOW}Running database migrations...${NC}"
sqlx database create || true
sqlx migrate run || {
    echo -e "${RED}Migration failed${NC}"
    exit 1
}
echo -e "${GREEN}Migrations complete${NC}\n"

# Run unit tests
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Running Unit Tests${NC}"
echo -e "${BLUE}========================================${NC}"
cargo test --lib --verbose || {
    echo -e "${RED}Unit tests failed${NC}"
    exit 1
}
echo -e "${GREEN}Unit tests passed${NC}\n"

# Run integration tests
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Running Integration Tests${NC}"
echo -e "${BLUE}========================================${NC}"

test_suites=("posts_test" "oauth_test" "feed_ranking_test" "job_test" "auth_password_reset_test")

for suite in "${test_suites[@]}"; do
    echo -e "${YELLOW}Running $suite...${NC}"
    cargo test --test "$suite" --verbose || {
        echo -e "${RED}$suite failed${NC}"
        exit 1
    }
done

echo -e "${GREEN}All integration tests passed${NC}\n"

# Run security tests
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Running Security Tests${NC}"
echo -e "${BLUE}========================================${NC}"
cargo test --test security_test --verbose || {
    echo -e "${RED}Security tests failed${NC}"
    exit 1
}
echo -e "${GREEN}Security tests passed${NC}\n"

# Run performance tests (optional, can be skipped with --skip-perf flag)
if [[ ! " $@ " =~ " --skip-perf " ]]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Running Performance Tests${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}This may take several minutes...${NC}"
    cargo test --test load_test -- --ignored --nocapture || {
        echo -e "${RED}Performance tests failed${NC}"
        exit 1
    }
    echo -e "${GREEN}Performance tests passed${NC}\n"
else
    echo -e "${YELLOW}Skipping performance tests (use without --skip-perf to run)${NC}\n"
fi

# Generate coverage report
if command -v cargo-tarpaulin &> /dev/null; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Generating Coverage Report${NC}"
    echo -e "${BLUE}========================================${NC}"

    cargo tarpaulin \
        --out Html \
        --output-dir coverage \
        --timeout 300 \
        --exclude-files "*/tests/*" \
        --skip-clean || {
        echo -e "${RED}Coverage generation failed${NC}"
        exit 1
    }

    echo -e "${GREEN}Coverage report generated: coverage/index.html${NC}"

    # Display coverage summary
    echo -e "\n${BLUE}Coverage Summary:${NC}"
    cargo tarpaulin --out Stdout | grep -E "Coverage|Line" || true

else
    echo -e "${YELLOW}cargo-tarpaulin not installed. Skipping coverage report.${NC}"
    echo -e "${YELLOW}Install with: cargo install cargo-tarpaulin${NC}\n"
fi

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}All Tests Passed Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"

if command -v cargo-tarpaulin &> /dev/null; then
    echo -e "${BLUE}Coverage report:${NC} coverage/index.html"
fi

echo -e "\n${BLUE}Test artifacts:${NC}"
echo -e "  - Coverage: coverage/"
echo -e "  - Logs: target/debug/"
