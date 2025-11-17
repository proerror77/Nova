#!/bin/bash

# Structured Logging Test Script
# Verifies JSON log format and checks for PII leakage

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_DURATION=5  # seconds
SERVICES=("identity-service" "feed-service" "graphql-gateway")

echo -e "${GREEN}=== Structured Logging Test Suite ===${NC}\n"

# Function to check if a service binary exists
check_service_binary() {
    local service=$1
    local binary_path="backend/${service}/target/debug/${service}"

    if [[ ! -f "$binary_path" ]]; then
        echo -e "${YELLOW}Building ${service}...${NC}"
        cd "backend/${service}"
        cargo build --quiet
        cd ../..
    fi
}

# Function to test JSON format
test_json_format() {
    local service=$1
    echo -e "${YELLOW}Testing JSON format for ${service}...${NC}"

    # Start service and capture logs
    cd "backend/${service}"
    RUST_LOG=debug timeout ${TEST_DURATION} cargo run --quiet 2>&1 | head -20 > "/tmp/${service}_logs.txt" || true
    cd ../..

    # Check if logs are valid JSON
    local json_valid=true
    local line_count=0
    local json_count=0

    while IFS= read -r line; do
        ((line_count++))
        if echo "$line" | jq empty 2>/dev/null; then
            ((json_count++))
        fi
    done < "/tmp/${service}_logs.txt"

    if [[ $json_count -gt 0 ]]; then
        echo -e "${GREEN}✓ JSON format: ${json_count}/${line_count} lines are valid JSON${NC}"
    else
        echo -e "${RED}✗ JSON format: No valid JSON lines found${NC}"
        json_valid=false
    fi

    # Check for required fields in JSON logs
    if [[ $json_valid == true ]]; then
        local has_timestamp=false
        local has_level=false
        local has_target=false
        local has_fields=false

        while IFS= read -r line; do
            if echo "$line" | jq -e '.timestamp' >/dev/null 2>&1; then has_timestamp=true; fi
            if echo "$line" | jq -e '.level' >/dev/null 2>&1; then has_level=true; fi
            if echo "$line" | jq -e '.target' >/dev/null 2>&1; then has_target=true; fi
            if echo "$line" | jq -e '.fields' >/dev/null 2>&1; then has_fields=true; fi
        done < "/tmp/${service}_logs.txt"

        echo -e "${YELLOW}Required JSON fields:${NC}"
        [[ $has_timestamp == true ]] && echo -e "${GREEN}  ✓ timestamp${NC}" || echo -e "${RED}  ✗ timestamp${NC}"
        [[ $has_level == true ]] && echo -e "${GREEN}  ✓ level${NC}" || echo -e "${RED}  ✗ level${NC}"
        [[ $has_target == true ]] && echo -e "${GREEN}  ✓ target${NC}" || echo -e "${RED}  ✓ target${NC}"
        [[ $has_fields == true ]] && echo -e "${GREEN}  ✓ fields${NC}" || echo -e "${RED}  ✗ fields${NC}"
    fi

    echo
}

# Function to check for PII leakage
test_pii_leakage() {
    local service=$1
    echo -e "${YELLOW}Testing for PII leakage in ${service}...${NC}"

    local pii_found=false
    local pii_patterns=("email" "phone" "password" "ssn" "credit_card" "birth_date")

    for pattern in "${pii_patterns[@]}"; do
        local matches=$(cat "/tmp/${service}_logs.txt" | jq -r '.fields' 2>/dev/null | grep -i "$pattern" || true)
        if [[ -n "$matches" ]]; then
            echo -e "${RED}✗ Found potential PII: ${pattern}${NC}"
            echo "$matches"
            pii_found=true
        fi
    done

    if [[ $pii_found == false ]]; then
        echo -e "${GREEN}✓ No PII leakage detected${NC}"
    fi

    echo
}

# Function to verify structured fields
test_structured_fields() {
    local service=$1
    echo -e "${YELLOW}Testing structured fields for ${service}...${NC}"

    # Extract sample structured fields
    local sample_fields=$(cat "/tmp/${service}_logs.txt" | jq -r '.fields | keys[]' 2>/dev/null | sort -u | head -10)

    if [[ -n "$sample_fields" ]]; then
        echo -e "${GREEN}Sample structured fields found:${NC}"
        echo "$sample_fields" | while read field; do
            echo "  - $field"
        done
    else
        echo -e "${RED}✗ No structured fields found${NC}"
    fi

    # Check for timing information
    local has_timing=$(cat "/tmp/${service}_logs.txt" | jq -r '.fields.elapsed_ms' 2>/dev/null | grep -v null | head -1)
    if [[ -n "$has_timing" ]]; then
        echo -e "${GREEN}✓ Timing information (elapsed_ms) present${NC}"
    else
        echo -e "${YELLOW}⚠ No timing information (elapsed_ms) found${NC}"
    fi

    echo
}

# Function to display sample JSON log
show_sample_log() {
    local service=$1
    echo -e "${YELLOW}Sample JSON log from ${service}:${NC}"

    cat "/tmp/${service}_logs.txt" | jq 'select(.level == "INFO")' 2>/dev/null | head -1 | jq '.'
    echo
}

# Main test execution
main() {
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is not installed. Please install jq to run this test.${NC}"
        echo "  macOS: brew install jq"
        echo "  Ubuntu: sudo apt-get install jq"
        exit 1
    fi

    # Run tests for each service
    for service in "${SERVICES[@]}"; do
        echo -e "${GREEN}=== Testing ${service} ===${NC}\n"

        # Check/build service binary
        check_service_binary "$service"

        # Run tests
        test_json_format "$service"
        test_pii_leakage "$service"
        test_structured_fields "$service"
        show_sample_log "$service"

        echo -e "${GREEN}=== Completed ${service} ===${NC}\n"
    done

    # Summary
    echo -e "${GREEN}=== Test Summary ===${NC}"
    echo "Test logs saved to /tmp/*_logs.txt"
    echo "Review logs with: jq . /tmp/<service>_logs.txt"
    echo
}

# Run main function
main
