#!/usr/bin/env bash
# run-all-tests.sh
# 运行完整测试套件 (包括性能测试和压力测试)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Nova Test Suite - Complete Run"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Start services
echo -e "${YELLOW}▶${NC} Starting test services..."
docker-compose -f docker-compose.test.yml up -d

# Step 2: Wait for services
./scripts/wait-for-services.sh

# Step 3: Run core flow tests
echo ""
echo -e "${YELLOW}▶${NC} Running Core Flow Tests..."
cargo test --test core_flow_test

# Step 4: Run regression tests
echo ""
echo -e "${YELLOW}▶${NC} Running Known Issues Regression Tests..."
cargo test --test known_issues_regression_test

# Step 5: Run performance benchmarks
echo ""
echo -e "${YELLOW}▶${NC} Running Performance Benchmark Tests..."
cargo test --test performance_benchmark_test

# Step 6: Run stress tests (ignored by default)
echo ""
echo -e "${YELLOW}▶${NC} Running Stress Tests (this may take a while)..."
cargo test --test performance_benchmark_test -- --ignored --nocapture

# Step 7: Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✓ All tests completed successfully!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Cleanup with:"
echo "  docker-compose -f docker-compose.test.yml down -v"
echo ""
