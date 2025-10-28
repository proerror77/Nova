# Nova Backend Development Guide

## Architecture Overview

Nova backend now consists of four primary microservices:

- **user-service** (port 8080) - Authentication, user profiles, OAuth
- **content-service** (port 8081 / gRPC 9081) - Feed ranking, posts, stories (feeds now resolved here)
- **messaging-service** (port 3000) - WebSocket messaging, DMs
- **search-service** (port 8086) - Full-text search for messages

All services are built with Rust and share a monorepo workspace structure.

## Prerequisites

### Required Tools

- **Rust 1.75+** - Install via [rustup](https://rustup.rs/)
- **Docker & Docker Compose** - For running infrastructure
- **PostgreSQL 14+** - Database (runs in Docker)
- **Redis 7+** - Cache and pub/sub (runs in Docker)

### Optional Tools

```bash
# Install development utilities
make install-tools
```

This installs:
- `sqlx-cli` - Database migrations
- `cargo-watch` - Hot reload during development
- `cargo-tarpaulin` - Code coverage
- `cargo-audit` - Security vulnerability scanning
- `cargo-nextest` - Faster test runner

## Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/proerror77/nova.git
cd nova

# Create .env from template
make setup
```

### 2. Start Infrastructure

```bash
# Start PostgreSQL, Redis, Kafka, ClickHouse, Neo4j, etc.
make dev
```

This starts all required services via `docker-compose`. Services will be available at:

- PostgreSQL: `localhost:55432`
- Redis: `localhost:6379`
- Kafka UI: `http://localhost:8080` (if enabled)
- MailHog (email testing): `http://localhost:8025`
- Neo4j Browser: `http://localhost:7474`
- ClickHouse: `http://localhost:8123`

### 3. Run Database Migrations

```bash
make migrate
```

### 4. Build and Test

```bash
# Build all services
make build

# Run all tests
make test

# Run with verbose output
make test-verbose
```

### 5. Run Services

#### Option A: Docker Compose (Recommended)

```bash
# Already running from step 2
docker-compose logs -f user-service
docker-compose logs -f messaging-service
docker-compose logs -f search-service
```

#### Option B: Local Development (Hot Reload)

```bash
# Terminal 1: user-service
cd backend/user-service
cargo watch -x run

# Terminal 2: messaging-service
cd backend/messaging-service
cargo watch -x run

# Terminal 3: search-service
cd backend/search-service
cargo watch -x run
```

### 6. Access Services

- **API Gateway**: `http://localhost:3000`
- **User Service**: `http://localhost:8080` (if exposed)
- **Messaging Service**: `http://localhost:8085` (if exposed)
- **Search Service**: `http://localhost:8086` (if exposed)
- **Content Service**: `http://localhost:8081`

Health checks:
```bash
curl http://localhost:8080/api/v1/health
curl http://localhost:8081/api/v1/health
```

## Development Workflow

### Code Quality Checks

```bash
# Format code
make fmt

# Check formatting (CI will fail if not formatted)
make fmt-check

# Run linter (strict mode)
make lint

# Quick compile check (faster than full build)
make check
```

### Testing

```bash
# Run all tests
make test

# Run with nextest (faster)
make test-nextest

# Run specific test
cd backend/user-service
cargo test test_name -- --nocapture

# Generate coverage report
make coverage
```

### Feed API (user-service ↔ content-service)

Feed requests are now proxied from user-service to content-service via gRPC. To verify the end-to-end flow:

```bash
# Terminal 1
cd backend/content-service
CONTENT_SERVICE_PORT=8081 cargo run

# Terminal 2
cd backend/user-service
CONTENT_SERVICE_GRPC_URL=http://127.0.0.1:9081 cargo run

# Terminal 3 (ensure you have a valid JWT for the user ID below)
curl -H "Authorization: Bearer <token>" \
     "http://127.0.0.1:8080/api/v1/feed?limit=10"
```

You can also call the gRPC endpoint directly when debugging:

```bash
grpcurl -plaintext -d '{"user_id":"<uuid>","limit":10}' \
    127.0.0.1:9081 nova.content.ContentService/GetFeed
```

In Kubernetes, the user-service deployment reads `CONTENT_SERVICE_GRPC_URL` from `nova-config`, so no additional wiring is required once both services are deployed.

### Database Management

```bash
# Run migrations
make migrate

# Revert last migration
make migrate-revert

# Create new migration
cd backend
sqlx migrate add migration_name
```

### Docker Development

```bash
# Build all service images
make docker-build

# Build specific service
make docker-build-user
make docker-build-messaging
make docker-build-search

# Clean everything and start fresh
make clean
make dev
```

### Debugging

```bash
# View logs
make logs              # user-service
make logs-db           # PostgreSQL
make logs-redis        # Redis

# Check service health
make health

# Watch logs in real-time
docker-compose logs -f
```

## Project Structure

```
nova/
├── backend/
│   ├── Cargo.toml                    # Workspace definition
│   ├── user-service/
│   │   ├── Cargo.toml
│   │   ├── src/
│   │   │   ├── main.rs
│   │   │   ├── routes/              # API endpoints
│   │   │   ├── handlers/            # Request handlers
│   │   │   ├── models/              # Database models
│   │   │   └── lib.rs
│   │   └── tests/                   # Integration tests
│   ├── messaging-service/
│   │   ├── Cargo.toml
│   │   └── src/
│   ├── search-service/
│   │   ├── Cargo.toml
│   │   └── src/
│   ├── libs/
│   │   └── crypto-core/             # Shared crypto utilities
│   ├── migrations/                  # Database migrations (SQLx)
│   ├── Dockerfile                   # user-service image
│   ├── Dockerfile.messaging         # messaging-service image
│   └── nginx/                       # API Gateway config
├── .github/workflows/               # CI/CD pipelines
├── docker-compose.yml               # Local dev infrastructure
├── Makefile                         # Development commands
└── .env.example                     # Environment template
```

## Environment Variables

Copy `.env.example` to `.env` and customize:

### Critical Variables

```bash
# Database
DATABASE_URL=postgresql://postgres:postgres@localhost:55432/nova_auth

# Redis
REDIS_URL=redis://:redis123@localhost:6379/0

# JWT (CHANGE IN PRODUCTION)
JWT_SECRET=dev_secret_change_in_production_32chars_minimum_length

# Email (uses MailHog in dev)
SMTP_HOST=localhost
SMTP_PORT=1025
```

### Optional Variables

```bash
# Enable Neo4j graph features
NEO4J_ENABLED=true

# Enable Kafka CDC
ENABLE_CDC=true

# OAuth providers (requires credentials)
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-secret
```

## Common Tasks

### Adding a New Endpoint

1. Define route in `routes/mod.rs`
2. Implement handler in `handlers/`
3. Add model in `models/` (if needed)
4. Write tests in `tests/`
5. Update OpenAPI docs

### Adding a Dependency

```bash
cd backend
cargo add dependency-name --features feature1,feature2
```

For workspace-wide dependencies, edit `backend/Cargo.toml`:

```toml
[workspace.dependencies]
new-crate = "1.0"
```

Then in service `Cargo.toml`:

```toml
[dependencies]
new-crate = { workspace = true }
```

### Running Individual Services

```bash
# User service
cd backend/user-service
cargo run

# Messaging service
cd backend/messaging-service
cargo run

# Search service
cd backend/search-service
cargo run
```

## Troubleshooting

### Port Already in Use

```bash
# Find process using port
lsof -i :8080

# Kill process
kill -9 PID
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
docker-compose ps postgres

# View database logs
make logs-db

# Restart database
docker-compose restart postgres
```

### Redis Connection Issues

```bash
# Check Redis is running
docker-compose ps redis

# Test connection
redis-cli -h localhost ping

# Restart Redis
docker-compose restart redis
```

### Migration Failures

```bash
# Reset database (DESTROYS DATA)
make clean
make dev
make migrate
```

### Build Failures

```bash
# Clean and rebuild
cd backend
cargo clean
cargo build --workspace

# Update dependencies
cargo update
```

### Test Failures

```bash
# Run tests with backtrace
RUST_BACKTRACE=1 cargo test

# Run single test with output
cargo test test_name -- --nocapture --test-threads=1
```

## Performance Optimization

### Development Builds

```bash
# Use release mode for faster runtime
cargo build --release

# Use mold linker (faster linking on Linux)
# Add to ~/.cargo/config.toml:
[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=mold"]
```

### Docker Build Speed

```bash
# Enable BuildKit
export DOCKER_BUILDKIT=1

# Use cache mounts
docker-compose build --parallel
```

## CI/CD

### Local CI Testing

```bash
# Run same checks as CI
make fmt-check
make lint
make test
make build-release
```

### GitHub Actions

CI runs on every push and PR:

1. **ci.yml** - Code quality, tests, build
2. **security.yml** - Vulnerability scanning, license checks
3. **migration-validation.yml** - Database migration tests
4. **docker-build.yml** - Build and push Docker images

All checks must pass before merging.

## Security

### Audit Dependencies

```bash
make audit
```

### Update Dependencies

```bash
cd backend
cargo update
cargo audit
```

### Secrets Management

- Never commit `.env` file
- Use environment variables for all secrets
- Rotate JWT secrets regularly
- Use AWS Secrets Manager or Vault in production

## Additional Resources

- [Rust Book](https://doc.rust-lang.org/book/)
- [Actix-web Docs](https://actix.rs/docs/)
- [Axum Docs](https://docs.rs/axum/latest/axum/)
- [SQLx Docs](https://docs.rs/sqlx/latest/sqlx/)
- [PostgreSQL Docs](https://www.postgresql.org/docs/)

## Getting Help

- Open an issue on GitHub
- Check existing issues for solutions
- Review CI logs for build failures
- Check `docker-compose logs` for runtime errors
