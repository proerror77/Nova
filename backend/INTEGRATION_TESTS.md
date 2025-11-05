# Integration Tests Guide

This document describes how to run integration tests locally and in CI for the Nova backend services.

## Local Testing with Docker Compose

### Prerequisites

- Docker and Docker Compose installed
- Rust 1.75+ installed
- `cargo` available in PATH

### Quick Start

```bash
# Start all infrastructure services
docker-compose -f docker-compose.dev.yml up -d

# Run all integration tests
cargo test --test '*' --lib

# Or run specific service tests
cargo test -p auth-service --lib --test '*'
cargo test -p user-service --lib --test '*'

# Stop infrastructure services
docker-compose -f docker-compose.dev.yml down
```

## Service-Specific Tests

### Auth Service

The auth service includes both unit tests and gRPC integration tests.

```bash
# Unit tests (no external dependencies)
cargo test -p auth-service --lib

# gRPC integration tests (requires services running)
docker-compose -f docker-compose.dev.yml up -d
cargo test -p auth-service --test grpc_integration_tests -- --nocapture
docker-compose -f docker-compose.dev.yml down
```

**Test Coverage**:
- Register/login flow validation
- JWT token generation and validation
- Error handling for invalid credentials
- Account lockout after 5 failed attempts

### Content Service

The content service includes gRPC integration tests for post operations.

```bash
# Build content service
cargo build -p content-service

# Start infrastructure + content service
docker-compose -f docker-compose.dev.yml up -d
(cd backend/content-service && cargo run) &  # Start service in background

# Run gRPC tests
cargo test -p content-service --test grpc_content_service_test -- --nocapture --test-threads=1

# Cleanup
pkill -f "cargo run"  # Stop service
docker-compose -f docker-compose.dev.yml down
```

**Test Coverage**:
- GetPostsByIds (batch retrieval)
- GetPostsByAuthor (pagination)
- UpdatePost (with cache invalidation)
- DeletePost (soft delete)
- DecrementLikeCount
- CheckPostExists

### User Service

The user service includes integration tests for various features.

```bash
# Start infrastructure
docker-compose -f docker-compose.dev.yml up -d

# Run specific integration tests
cargo test -p user-service --test neo4j_suggest_tests -- --nocapture
cargo test -p user-service --test load_test -- --nocapture --ignored

# Run all tests
cargo test -p user-service --lib --test '*'

# Stop infrastructure
docker-compose -f docker-compose.dev.yml down
```

## CI/CD Integration

### GitHub Actions

The repository includes an automatic CI workflow that runs on:
- Every push to `main` or `develop`
- Every pull request
- Nightly schedule (2 AM UTC)

**Workflow**: `.github/workflows/integration-tests.yml`

The workflow:
1. Sets up Rust toolchain
2. Starts Postgres and Redis services
3. Runs unit and integration tests
4. Generates code coverage reports
5. Uploads to Codecov

### Local CI Simulation

To simulate the CI environment locally:

```bash
# Start services (GitHub Actions starts these automatically)
docker-compose -f docker-compose.dev.yml up -d postgres redis

# Set environment variables
export DATABASE_URL=postgresql://nova:nova_password@localhost:5432/postgres
export REDIS_URL=redis://localhost:6379

# Run tests
cargo test --all --lib
cargo test --all --test '*'

# Cleanup
docker-compose -f docker-compose.dev.yml down
```

## Testcontainers Usage

For tests that need isolated container instances, use the testcontainers harness in `backend/tests/common/testcontainers.rs`:

```rust
use crate::common::testcontainers::{PostgresContainer, RedisContainer, TestEnvironment};

#[tokio::test]
async fn test_with_containers() {
    let env = TestEnvironment::start().await.unwrap();

    // Use env.postgres.connection_string()
    // Use env.redis.connection_string()

    // Tests run with isolated containers
}
```

## Debugging Tests

### View detailed output

```bash
# Run tests with output
cargo test --test grpc_content_service_test -- --nocapture

# Run with specific log level
RUST_LOG=debug cargo test --test grpc_content_service_test -- --nocapture

# Run single test
cargo test test_get_posts_by_ids_batch_retrieval -- --exact --nocapture
```

### Inspect running containers

```bash
# List running containers
docker-compose -f docker-compose.dev.yml ps

# View container logs
docker-compose -f docker-compose.dev.yml logs postgres
docker-compose -f docker-compose.dev.yml logs redis

# Connect to container directly
docker-compose -f docker-compose.dev.yml exec postgres psql -U nova
docker-compose -f docker-compose.dev.yml exec redis redis-cli
```

## Performance Testing

For load tests and performance benchmarks:

```bash
# Run performance tests
cargo test -p user-service --test events_load_test -- --nocapture --ignored

# With profiling
cargo test -p user-service --test '*' --release -- --nocapture --ignored
```

## Troubleshooting

### Port Already in Use

If you get "address already in use" errors:

```bash
# Kill existing containers
docker-compose -f docker-compose.dev.yml down -v

# Or kill specific ports
lsof -ti:5432 | xargs kill -9
lsof -ti:6379 | xargs kill -9

# Restart services
docker-compose -f docker-compose.dev.yml up -d
```

### Connection Refused

If tests fail with connection errors:

1. Verify containers are running: `docker-compose -f docker-compose.dev.yml ps`
2. Wait for services to be healthy: `docker-compose -f docker-compose.dev.yml logs`
3. Test connectivity: `psql postgresql://nova:nova_password@localhost:5432/postgres`

### Out of Memory

If you encounter OOM errors during tests:

```bash
# Reduce parallel test threads
cargo test --test '*' -- --test-threads=1

# Or set resource limits in docker-compose
docker-compose -f docker-compose.dev.yml up --memory=2g
```

## Best Practices

1. **Always stop services after testing**: `docker-compose down -v` cleans up volumes too
2. **Run tests sequentially for gRPC tests**: Use `--test-threads=1` to avoid port conflicts
3. **Use feature flags for optional tests**: Tests requiring specific infrastructure should be feature-gated
4. **Document test dependencies**: Include comments explaining what services each test needs
5. **Use testcontainers for isolation**: New tests should use testcontainers for automatic cleanup

## Adding New Integration Tests

When adding new integration tests:

1. Create test file in appropriate directory (`tests/integration/`, `tests/unit/`, etc.)
2. Add testcontainers usage for external dependencies
3. Use meaningful test names that describe what's being tested
4. Document prerequisites in comments
5. Add test to `Cargo.toml` if needed
6. Update this documentation with new test instructions
