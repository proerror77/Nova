# Integration Testing Setup Guide

This document explains how to set up the test environment for running integration tests.

## Prerequisites

- PostgreSQL 12+ installed and running
- Rust toolchain installed
- `sqlx-cli` for database migrations

## Setup Steps

### 1. Install sqlx-cli (if not already installed)

```bash
cargo install sqlx-cli --no-default-features --features postgres
```

### 2. Create Test Database

```bash
# Using psql (adjust user/password as needed)
psql -U postgres -c "CREATE DATABASE nova_test;"
```

Or using Docker:

```bash
docker run --name postgres-test -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 postgres:15
docker exec postgres-test psql -U postgres -c "CREATE DATABASE nova_test;"
```

### 3. Set Environment Variables

Create a `.env.test` file in the `backend/user-service` directory:

```bash
# Database
DATABASE_URL=postgres://postgres:postgres@localhost:5432/nova_test

# Application
APP_ENV=test
APP_HOST=127.0.0.1
APP_PORT=8080

# Redis
REDIS_URL=redis://localhost:6379

# JWT Keys (must be base64-encoded PEM content)
# Generate test keys:
# openssl genpkey -algorithm RSA -out test_private.pem -pkeyopt rsa_keygen_bits:2048
# openssl pkey -in test_private.pem -pubout -out test_public.pem
# base64 -i test_private.pem > private_b64.txt
# base64 -i test_public.pem > public_b64.txt
JWT_SECRET=test_secret_key_minimum_32_bytes_required_for_production
JWT_PRIVATE_KEY_PEM=<base64-encoded-private-key>
JWT_PUBLIC_KEY_PEM=<base64-encoded-public-key>

# Email
SMTP_HOST=localhost
SMTP_PORT=1025
SMTP_USERNAME=test
SMTP_PASSWORD=test
SMTP_FROM=test@nova.dev

# S3
S3_BUCKET_NAME=nova-test
S3_REGION=us-east-1
AWS_ACCESS_KEY_ID=test_access_key
AWS_SECRET_ACCESS_KEY=test_secret_key
CLOUDFRONT_URL=https://d123456.cloudfront.net

# CORS
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:3001
CORS_MAX_AGE=3600
```

### 4. Run Tests

```bash
# Load environment from .env.test
export $(cat .env.test | xargs)

# Run all tests
cd backend/user-service
cargo test

# Run specific test file
cargo test --test posts_test

# Run tests with output
cargo test -- --nocapture

# Run tests in parallel with specific number of threads
cargo test -- --test-threads=4
```

### 5. Automated Migrations

The test setup automatically runs migrations from `../migrations` directory. Ensure migrations are available at:

```
backend/migrations/
```

## Troubleshooting

### Connection Refused

If you get "connection refused" errors:
1. Verify PostgreSQL is running: `psql -U postgres -c "SELECT 1;"`
2. Check the DATABASE_URL is correct
3. Ensure nova_test database exists: `psql -U postgres -l | grep nova_test`

### Migration Failures

If migrations fail:
1. Check migrations directory exists: `ls backend/migrations/`
2. Verify database is empty: `psql nova_test -c "\dt"`
3. Run migrations manually:
   ```bash
   sqlx migrate run --database-url="postgres://postgres:postgres@localhost:5432/nova_test" --source backend/migrations
   ```

### JWT Key Issues

If JWT keys are invalid:
1. Generate proper RSA keys:
   ```bash
   openssl genpkey -algorithm RSA -out test_private.pem -pkeyopt rsa_keygen_bits:2048
   openssl pkey -in test_private.pem -pubout -out test_public.pem
   ```
2. Convert to base64:
   ```bash
   cat test_private.pem | base64
   cat test_public.pem | base64
   ```
3. Update .env.test with the base64 values

## GitHub Actions / CI/CD

For running tests in CI/CD:

```yaml
- name: Start PostgreSQL
  uses: ankane/setup-postgres@v1
  with:
    postgres-version: 15

- name: Create test database
  run: |
    createdb nova_test
    psql nova_test < backend/migrations/*.sql

- name: Run tests
  run: cargo test
  env:
    DATABASE_URL: postgres://postgres:@localhost/nova_test
    # ... other env vars
```

## Test Database Cleanup

Between test runs, the database is automatically cleaned up by the `cleanup_test_data()` function in `tests/common/fixtures.rs`. This ensures test isolation.

To manually clean up:

```bash
psql nova_test -c "
  DELETE FROM upload_sessions;
  DELETE FROM post_images;
  DELETE FROM post_metadata;
  DELETE FROM posts;
  DELETE FROM refresh_tokens;
  DELETE FROM sessions;
  DELETE FROM email_verifications;
  DELETE FROM users;
"
```

## Performance Tips

1. **Use transactions in tests**: Tests wrap database operations in transactions that are rolled back, ensuring faster cleanup
2. **Parallel execution**: Run tests with multiple threads for faster execution (but watch for database lock contention)
3. **Skip slow tests**: Use `#[ignore]` attribute for slow tests and run them separately

## Quick Start Script

Create `scripts/setup-test-env.sh`:

```bash
#!/bin/bash
set -e

echo "Setting up test environment..."

# Create database if not exists
psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'nova_test'" | grep -q 1 || \
    psql -U postgres -c "CREATE DATABASE nova_test;"

# Copy .env.test if it doesn't exist
if [ ! -f backend/user-service/.env.test ]; then
    cp backend/user-service/.env.test.example backend/user-service/.env.test
    echo "Created .env.test - please update with your values"
fi

echo "Test environment ready!"
```

Then run: `chmod +x scripts/setup-test-env.sh && ./scripts/setup-test-env.sh`
