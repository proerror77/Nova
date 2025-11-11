# Phase 1 Quick Wins - Test Execution Guide

**Target Audience**: Developers, QA Engineers, DevOps
**Last Updated**: 2025-11-11

---

## Quick Start

### Prerequisites

```bash
# Install Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install required tools
cargo install sqlx-cli --no-default-features --features postgres
cargo install cargo-llvm-cov  # For coverage reports

# Start required services
docker-compose up -d postgres redis kafka
```

### Run All Tests (Fast)

```bash
# From backend directory
cd backend

# Unit tests only (no external dependencies)
cargo test --lib

# All tests (requires services running)
cargo test --all
```

---

## Test Categories

### 1. Unit Tests (Fast, No Dependencies)

#### Pool Exhaustion Tests
```bash
# Run specific test file
cargo test --package db-pool --lib

# Run specific test
cargo test --package db-pool --lib test_normal_acquisition_below_threshold

# Run with output
cargo test --package db-pool --lib -- --nocapture
```

**Duration**: ~5 seconds
**Dependencies**: None
**Coverage**: 96%

---

#### Structured Logging Tests
```bash
# Run all logging tests
cargo test --package graphql-gateway --test structured_logging_performance_tests

# Run specific test
cargo test --package graphql-gateway --test structured_logging_performance_tests test_no_pii_in_logs

# Run with verbose output
cargo test --package graphql-gateway --test structured_logging_performance_tests -- --nocapture
```

**Duration**: ~8 seconds
**Dependencies**: None
**Coverage**: 94%

---

### 2. Integration Tests (Require Services)

#### Setup Required Services

```bash
# Using Docker Compose (recommended)
docker-compose up -d postgres redis

# Or manually
docker run -d --name postgres -p 5432:5432 -e POSTGRES_PASSWORD=password postgres:15
docker run -d --name redis -p 6379:6379 redis:7
```

#### Run Migration First

```bash
export DATABASE_URL="postgres://postgres:password@localhost:5432/nova_test"
sqlx migrate run
```

---

#### Database Indexes Tests
```bash
# Run with database connection
export DATABASE_URL="postgres://postgres:password@localhost:5432/nova_test"

# Run all index tests (most are marked #[ignore] for safety)
cargo test --test database_indexes_tests -- --ignored

# Run specific test
cargo test --test database_indexes_tests test_index_creation_verification -- --ignored

# Check query performance
cargo test --test database_indexes_tests test_query_performance_with_indexes -- --ignored --nocapture
```

**Duration**: ~30 seconds
**Dependencies**: PostgreSQL
**Coverage**: 92%

---

#### GraphQL Caching Tests
```bash
# Some tests use mock, some use real Redis
export REDIS_URL="redis://localhost:6379"

# Run all caching tests
cargo test --test graphql_caching_tests

# Run specific cache hit test
cargo test --test graphql_caching_tests test_cache_hit_scenario

# Run with real Redis (marked as #[ignore])
cargo test --test graphql_caching_tests -- --ignored
```

**Duration**: ~12 seconds
**Dependencies**: Redis (for real tests)
**Coverage**: 97%

---

#### Kafka Deduplication Tests
```bash
# Most tests use mocks, some require Kafka
export KAFKA_BROKERS="localhost:9092"

# Run all deduplication tests
cargo test --test kafka_deduplication_tests

# Run high-throughput test
cargo test --test kafka_deduplication_tests test_high_throughput_deduplication -- --nocapture
```

**Duration**: ~15 seconds
**Dependencies**: Kafka (for real tests)
**Coverage**: 95%

---

#### gRPC Rotation Tests
```bash
# Run all rotation tests (use mocks)
cargo test --test grpc_rotation_tests

# Run load balancing test
cargo test --test grpc_rotation_tests test_load_balancing_fairness

# Run concurrent test with output
cargo test --test grpc_rotation_tests test_concurrent_requests_balanced -- --nocapture
```

**Duration**: ~10 seconds
**Dependencies**: None (uses mocks)
**Coverage**: 93%

---

### 3. Load & Stress Tests (Long-Running)

**⚠️ Warning**: These tests are marked `#[ignore]` and can take 10-60 minutes to complete.

#### Setup for Load Tests

```bash
# Ensure all services are running with production-like resources
docker-compose -f docker-compose.load-test.yml up -d

# Set environment variables
export DATABASE_URL="postgres://postgres:password@localhost:5432/nova_test"
export REDIS_URL="redis://localhost:6379"
export KAFKA_BROKERS="localhost:9092"
```

#### Run Load Tests

```bash
# Run all load tests (takes ~15 minutes)
cargo test --test phase1_load_stress_tests -- --ignored --test-threads=1

# Run specific load test
cargo test --test phase1_load_stress_tests test_pool_exhaustion_normal_load -- --ignored --nocapture

# Run stress test only
cargo test --test phase1_load_stress_tests test_pool_exhaustion_stress_load -- --ignored --nocapture

# Run with detailed output
RUST_LOG=debug cargo test --test phase1_load_stress_tests -- --ignored --test-threads=1 --nocapture
```

**Duration**: 10-60 minutes
**Dependencies**: PostgreSQL, Redis, Kafka
**Coverage**: Comprehensive scenarios

---

## Coverage Reports

### Generate Coverage Report

```bash
# Install coverage tool
cargo install cargo-llvm-cov

# Generate HTML report
cargo llvm-cov --workspace --html

# Open report
open target/llvm-cov/html/index.html
```

### Check Coverage Threshold

```bash
# Check if coverage meets 90% threshold
cargo llvm-cov --workspace --summary-only

# Fail if below threshold
cargo llvm-cov --workspace --fail-under-lines 90
```

### Coverage by Component

```bash
# Pool exhaustion only
cargo llvm-cov --package db-pool --html

# GraphQL gateway only
cargo llvm-cov --package graphql-gateway --html

# All tests
cargo llvm-cov --workspace --html
```

---

## Debugging Failed Tests

### Enable Detailed Logging

```bash
# Set log level
export RUST_LOG=debug

# Run specific test with logging
RUST_LOG=debug cargo test test_name -- --nocapture
```

### Run Single Test

```bash
# Run exact test name
cargo test --test test_file_name exact_test_name -- --exact

# Example
cargo test --test pool_exhaustion_tests test_normal_acquisition_below_threshold -- --exact
```

### Run Test in Isolation

```bash
# Use single thread to avoid concurrency issues
cargo test test_name -- --test-threads=1
```

### Check Test Output

```bash
# Show all output (don't capture)
cargo test test_name -- --nocapture

# Show println! and dbg! output
cargo test test_name -- --show-output
```

---

## CI/CD Integration

### GitHub Actions Workflow

Located at: `.github/workflows/phase1-quick-wins-tests.yml`

**Triggers**:
- Push to `main` or `develop`
- Pull requests
- Daily at 2 AM UTC (performance tests)

**Jobs**:
1. **Unit Tests**: Fast tests, no dependencies
2. **Integration Tests**: With PostgreSQL & Redis
3. **Performance Tests**: Load/stress tests (daily only)
4. **Coverage**: Generate and upload coverage report
5. **Security Audit**: Check for vulnerabilities
6. **Linting**: Format and clippy checks

### Run Locally (Same as CI)

```bash
# Run the same tests as CI
./scripts/run-ci-tests.sh

# Or manually step by step:

# 1. Unit tests
cargo test --lib

# 2. Integration tests (requires services)
docker-compose up -d
export DATABASE_URL="postgres://postgres:password@localhost:5432/nova_test"
export REDIS_URL="redis://localhost:6379"
sqlx migrate run
cargo test --all -- --test-threads=1

# 3. Coverage
cargo llvm-cov --workspace --lcov --output-path lcov.info

# 4. Security audit
cargo audit

# 5. Linting
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
```

---

## Performance Benchmarks

### Run Benchmarks

```bash
# Install criterion
cargo install cargo-criterion

# Run all benchmarks
cargo criterion

# Run specific benchmark
cargo criterion --bench pool_benchmark
```

### Compare Performance

```bash
# Save baseline
cargo criterion --save-baseline before-optimization

# Make changes...

# Compare with baseline
cargo criterion --baseline before-optimization
```

---

## Test Data Management

### Setup Test Database

```bash
# Create test database
createdb nova_test

# Run migrations
export DATABASE_URL="postgres://postgres:password@localhost:5432/nova_test"
sqlx migrate run
```

### Seed Test Data

```bash
# Load test data for integration tests
psql $DATABASE_URL < backend/tests/fixtures/test_data.sql
```

### Clean Test Database

```bash
# Drop all tables
sqlx migrate drop --database-url $DATABASE_URL

# Recreate fresh
sqlx migrate run --database-url $DATABASE_URL
```

---

## Common Issues & Solutions

### Issue: `DATABASE_URL` not set

```bash
export DATABASE_URL="postgres://postgres:password@localhost:5432/nova_test"
```

### Issue: Port already in use (5432, 6379, 9092)

```bash
# Check what's using the port
lsof -i :5432

# Kill existing process or change port
docker-compose down
docker-compose up -d
```

### Issue: Tests timeout

```bash
# Increase timeout
cargo test -- --test-threads=1 --timeout=300
```

### Issue: Flaky tests

```bash
# Run multiple times
for i in {1..10}; do cargo test test_name; done

# Or use nextest (better test runner)
cargo install cargo-nextest
cargo nextest run
```

### Issue: Coverage tool not found

```bash
# Install llvm-tools
rustup component add llvm-tools-preview

# Install cargo-llvm-cov
cargo install cargo-llvm-cov
```

---

## Test Performance Tips

### Speed Up Test Execution

```bash
# Use release mode for faster tests
cargo test --release

# Use nextest (parallel test runner)
cargo nextest run

# Cache dependencies
export CARGO_INCREMENTAL=1
```

### Reduce Test Time

```bash
# Run only fast tests
cargo test --lib

# Skip long-running tests
cargo test --test '*' -- --skip slow_test

# Run specific test file
cargo test --test pool_exhaustion_tests
```

---

## Test Maintenance

### Update Test Dependencies

```bash
# Update Cargo.lock
cargo update

# Check for outdated dependencies
cargo outdated
```

### Add New Test

```bash
# Add test to existing file
vim backend/tests/pool_exhaustion_tests.rs

# Run new test
cargo test new_test_name
```

### Remove Flaky Test

```bash
# Mark as ignored
#[test]
#[ignore = "Flaky, needs investigation"]
fn flaky_test() { ... }

# Or fix the flakiness!
```

---

## Quick Reference Commands

```bash
# Fast check (formatting + tests)
cargo fmt && cargo test --lib

# Full check (lint + test + coverage)
cargo fmt --check && cargo clippy && cargo test --all && cargo llvm-cov

# CI simulation
docker-compose up -d && cargo test --all -- --test-threads=1

# Performance test
cargo test --test phase1_load_stress_tests -- --ignored --nocapture

# Coverage report
cargo llvm-cov --workspace --html && open target/llvm-cov/html/index.html
```

---

## Additional Resources

- **Test Coverage Report**: `PHASE_1_TEST_COVERAGE_REPORT.md`
- **CI/CD Workflow**: `.github/workflows/phase1-quick-wins-tests.yml`
- **Docker Compose**: `docker-compose.yml`
- **Test Fixtures**: `backend/tests/fixtures/`

---

## Contact & Support

**Questions?** Contact the QA team or check:
- Test documentation: `backend/tests/README.md`
- CI/CD logs: GitHub Actions
- Coverage dashboard: Codecov

**Report Issues**: Create a ticket with:
- Test name
- Error message
- Environment (OS, Rust version)
- Reproduction steps

---

**Last Updated**: 2025-11-11
**Maintained By**: QA Engineering Team
