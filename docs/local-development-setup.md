# Local Development Setup Guide

## Overview

This guide provides step-by-step instructions for setting up the Nova Streaming platform for local development. You'll learn how to configure the environment, build components, and run the complete streaming system locally.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [System Requirements](#system-requirements)
3. [Environment Setup](#environment-setup)
4. [Component Setup](#component-setup)
5. [Development Workflows](#development-workflows)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

- **Git**: Version control system
  ```bash
  git --version  # Should be >= 2.30
  ```

- **Docker & Docker Compose**: Container platform
  ```bash
  docker --version      # Should be >= 20.10
  docker-compose --version  # Should be >= 1.29
  ```

- **Rust**: Programming language for backend
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  source $HOME/.cargo/env
  rustc --version  # Should be >= 1.70
  cargo --version
  ```

- **Node.js & npm**: JavaScript runtime (for iOS app development)
  ```bash
  node --version   # Should be >= 18.0
  npm --version    # Should be >= 9.0
  ```

- **Python 3**: Python runtime (for test scripts)
  ```bash
  python3 --version  # Should be >= 3.9
  ```

- **FFmpeg**: Media processing (for streaming examples)
  ```bash
  # macOS
  brew install ffmpeg

  # Ubuntu/Debian
  sudo apt-get install ffmpeg

  # Verify
  ffmpeg -version | head -1
  ```

### Optional Tools

- **websocat**: WebSocket testing tool
  ```bash
  brew install websocat  # macOS
  # or: cargo install websocat
  ```

- **jq**: JSON query tool
  ```bash
  brew install jq  # macOS
  sudo apt-get install jq  # Ubuntu/Debian
  ```

- **Xcode Command Line Tools** (macOS only)
  ```bash
  xcode-select --install
  ```

---

## System Requirements

### Minimum Specifications

| Component | Requirement |
|-----------|-------------|
| **CPU** | 4 cores minimum |
| **RAM** | 8 GB minimum (16 GB recommended) |
| **Disk** | 20 GB free space |
| **OS** | macOS 11+, Ubuntu 20.04+, or Windows 10+ WSL2 |

### Docker Resource Configuration

Ensure Docker has sufficient resources:

```bash
# Check current Docker resource limits
docker system info | grep -A 5 "CPUs\|Memory"

# For macOS Docker Desktop:
# - Memory: 8GB or more
# - CPUs: 4 or more
# - Disk: 50GB or more
```

### Network Configuration

- Port `8081`: User service (REST API + metrics)
- Port `1935`: Nginx-RTMP (RTMP ingestion)
- Port `5432`: PostgreSQL database
- Port `6379`: Redis cache
- Port `9092`: Kafka broker
- Port `8123`: ClickHouse database
- Port `3000`: Grafana (optional)
- Port `9090`: Prometheus (optional)

Ensure these ports are available:

```bash
# Check port availability
lsof -i :8081
lsof -i :1935
lsof -i :5432
```

---

## Environment Setup

### 1. Clone Repository

```bash
git clone https://github.com/nova-social/nova.git
cd nova
```

### 2. Create Environment Files

Create `.env.local` for local development:

```bash
# Backend Configuration
RUST_LOG=debug,tokio=info,hyper=info
RUST_BACKTRACE=1
DATABASE_URL=postgresql://nova_user:nova_password@localhost:5432/nova_streaming
REDIS_URL=redis://localhost:6379/0
KAFKA_BROKERS=localhost:9092
CLICKHOUSE_URL=http://localhost:8123

# JWT Configuration
JWT_SECRET=dev_secret_key_min_32_chars_long_for_testing
JWT_EXPIRY_SECONDS=3600

# Server Configuration
LISTEN_ADDR=0.0.0.0
LISTEN_PORT=8081
METRICS_PORT=8081

# RTMP Configuration
RTMP_SERVER_URL=rtmp://localhost:1935/live
RTMP_CHUNK_SIZE=4096
RTMP_TIMEOUT_SECONDS=60

# Feature Flags
ENABLE_STREAMING=true
ENABLE_METRICS=true
ENABLE_WEBSOCKET=true
```

Create `.env.test` for integration tests:

```bash
# Same as .env.local but with test-specific values
RUST_LOG=debug
DATABASE_URL=postgresql://nova_user:nova_password@localhost:5433/nova_streaming_test
REDIS_URL=redis://localhost:6380/0
```

### 3. Setup Docker Services

Start the development environment:

```bash
# Start all services (PostgreSQL, Redis, Kafka, ClickHouse, Nginx-RTMP)
docker-compose -f docker-compose.dev.yml up -d

# Verify services are running
docker-compose -f docker-compose.dev.yml ps

# Check logs
docker-compose -f docker-compose.dev.yml logs -f user-service
```

Create development database:

```bash
# Create database and user
psql -h localhost -U postgres -c "CREATE USER nova_user WITH PASSWORD 'nova_password';"
psql -h localhost -U postgres -c "CREATE DATABASE nova_streaming OWNER nova_user;"
psql -h localhost -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE nova_streaming TO nova_user;"

# Run migrations
sqlx database create
sqlx migrate run
```

### 4. Verify Service Connectivity

```bash
# PostgreSQL
psql -h localhost -U nova_user -d nova_streaming -c "SELECT version();"

# Redis
redis-cli -h localhost ping

# Kafka
docker-compose -f docker-compose.dev.yml exec kafka kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# ClickHouse
curl http://localhost:8123/?query=SELECT%201

# Nginx-RTMP
curl -I http://localhost:1935/stat || echo "RTMP server listening on 1935"

# Prometheus (optional)
curl http://localhost:9090/api/v1/query?query=up
```

---

## Component Setup

### Backend (User Service)

#### Build

```bash
# Build the backend with all features
cargo build -p user-service

# Build with optimizations (release mode)
cargo build -p user-service --release

# Build specific components
cargo build -p user-service --lib  # Library only
cargo build -p user-service --bin user-service  # Binary only
```

#### Run

```bash
# Development (with hot-reload via cargo-watch)
cargo install cargo-watch
cargo watch -x 'run -p user-service'

# Or run directly
cargo run -p user-service

# With specific log level
RUST_LOG=debug cargo run -p user-service

# Run tests
cargo test -p user-service

# Run integration tests
cargo test -p user-service --test '*' -- --nocapture --test-threads=1
```

#### Development Server Output

Expected startup output:

```
   Compiling user-service v0.1.0
    Finished dev [unoptimized + debuginfo] target(s) in 1.23s
     Running `target/debug/user-service`

2025-10-21T10:30:45.123Z  INFO user-service: Starting Nova User Service...
2025-10-21T10:30:45.456Z  INFO user-service: Connecting to database...
2025-10-21T10:30:45.789Z  INFO user-service: Database connected successfully
2025-10-21T10:30:46.012Z  INFO user-service: Setting up metrics...
2025-10-21T10:30:46.234Z  INFO user-service: Initializing WebSocket hub...
2025-10-21T10:30:46.456Z  INFO user-service: Server listening on 0.0.0.0:8081
2025-10-21T10:30:46.789Z  INFO user-service: Metrics available at http://localhost:8081/metrics
```

### iOS Application

#### Prerequisites

- Xcode 15+ (Command Line Tools)
- iOS deployment target: 17.0+
- CocoaPods (optional, for dependency management)

#### Build

```bash
# Navigate to iOS app
cd ios/NovaSocialApp

# Install dependencies (if using CocoaPods)
pod install

# Build for simulator
xcodebuild -scheme NovaSocialApp -configuration Debug -sdk iphonesimulator -derivedDataPath build

# Build for device
xcodebuild -scheme NovaSocialApp -configuration Debug -sdk iphoneos -derivedDataPath build
```

#### Run

```bash
# In Xcode
open NovaSocialApp.xcworkspace
# Then: Cmd+R to run on simulator

# Or via command line
xcrun simctl install booted build/Release-iphonesimulator/NovaSocialApp.app
xcrun simctl launch booted com.nova.NovaSocialApp
```

#### Configure for Local Backend

Update `ios/NovaSocialApp/Network/Utils/AppConfig.swift`:

```swift
#if DEBUG
let API_BASE_URL = "http://localhost:8081/api/v1"
let WS_URL = "ws://localhost:8081/api/v1"
#else
let API_BASE_URL = "https://api.nova-social.io/api/v1"
let WS_URL = "wss://api.nova-social.io/api/v1"
#endif
```

### Python Test Client

```bash
# Install dependencies
pip install -r examples/requirements.txt

# Or install individually
pip install requests pycryptodome av

# Create test video
python examples/python-broadcaster-client.py --generate-test-video

# Run broadcaster client
python examples/python-broadcaster-client.py \
  --token "$JWT_TOKEN" \
  --generate-test-video \
  --title "Local Test Stream" \
  --fps 30 \
  --bitrate 5000
```

### JavaScript Client Testing

```bash
# Install dependencies
npm install -g minimist

# Test WebSocket viewer
node examples/javascript-viewer-client.js \
  --stream-id "550e8400-e29b-41d4-a716-446655440000" \
  --token "$JWT_TOKEN"

# Browser integration
# Include in HTML:
# <script src="examples/javascript-viewer-client.js"></script>
```

---

## Development Workflows

### Typical Development Session

#### 1. Start Services

```bash
# Terminal 1: Docker services
docker-compose -f docker-compose.dev.yml up

# Terminal 2: User service with hot-reload
cargo watch -x 'run -p user-service'
```

#### 2. Verify API

```bash
# Check service health
curl http://localhost:8081/health || echo "Service starting..."

# Get metrics
curl http://localhost:8081/metrics | head -20
```

#### 3. Test API Endpoints

```bash
# Create a JWT token for testing
# (Use your authentication service or test key)
export JWT_TOKEN="your-test-jwt-token"

# Create a stream
curl -X POST http://localhost:8081/api/v1/streams \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test", "description": "Development test"}'

# List active streams
curl http://localhost:8081/api/v1/streams/active \
  -H "Authorization: Bearer $JWT_TOKEN"
```

#### 4. Test WebSocket Connection

```bash
# Terminal 3: WebSocket testing
websocat "ws://localhost:8081/api/v1/streams/{stream_id}/ws?token=$JWT_TOKEN"

# Or use JavaScript client
node examples/javascript-viewer-client.js \
  --stream-id "550e8400-e29b-41d4-a716-446655440000" \
  --token "$JWT_TOKEN"
```

#### 5. Test RTMP Broadcasting

```bash
# Terminal 4: Generate and broadcast test video
python examples/python-broadcaster-client.py \
  --token "$JWT_TOKEN" \
  --generate-test-video \
  --title "Local Test" \
  --fps 30
```

### Code Changes Workflow

#### 1. Make Changes

```bash
# Edit files in your editor
vim backend/user-service/src/handlers/streaming_websocket.rs
```

#### 2. Verify Changes

```bash
# Check compilation
cargo check -p user-service

# Run formatter
cargo fmt -p user-service

# Run linter
cargo clippy -p user-service
```

#### 3. Test Changes

```bash
# Run tests related to changes
cargo test -p user-service --lib handlers::streaming_websocket

# Run integration tests
cargo test -p user-service --test 'integration_*'
```

#### 4. Commit Changes

```bash
# Stage changes
git add backend/user-service/src/handlers/streaming_websocket.rs

# Commit with descriptive message
git commit -m "feat(streaming): add [feature description]"

# Push to branch
git push origin feature/branch-name
```

### Database Migrations

#### Create Migration

```bash
# Create new migration file
sqlx migrate add -r create_streams_table

# This creates:
# migrations/{timestamp}_create_streams_table.sql
# migrations/{timestamp}_create_streams_table.revert.sql
```

#### Write Migration

Edit migration file with SQL:

```sql
-- Create streams table
CREATE TABLE IF NOT EXISTS streams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    broadcaster_id UUID NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMP,
    FOREIGN KEY (broadcaster_id) REFERENCES users(id)
);

CREATE INDEX idx_streams_broadcaster_id ON streams(broadcaster_id);
CREATE INDEX idx_streams_status ON streams(status);
```

#### Run Migrations

```bash
# Apply pending migrations
sqlx migrate run

# Check migration status
sqlx migrate info

# Revert last migration
sqlx migrate revert
```

### Performance Profiling

#### CPU Profiling

```bash
# Install perf tools
cargo install flamegraph

# Generate flame graph
cargo flamegraph -p user-service -- --profile cpu

# View result (opens in browser)
open flamegraph.svg
```

#### Memory Profiling

```bash
# Using heaptrack (Linux)
heaptrack cargo run -p user-service

# Generate report
heaptrack_gui heaptrack.cargo.*.gz
```

#### Benchmark Tests

```bash
# Run benchmarks (if available)
cargo bench -p user-service

# Run specific benchmark
cargo bench -p user-service -- --bench streaming_metrics
```

---

## Troubleshooting

### Service Won't Start

**Problem**: Port already in use

```bash
# Find process using port
lsof -i :8081

# Kill process
kill -9 <PID>

# Or use different port
LISTEN_PORT=8082 cargo run -p user-service
```

**Problem**: Database connection failed

```bash
# Check if PostgreSQL is running
docker-compose -f docker-compose.dev.yml ps | grep postgres

# Check connection string
echo $DATABASE_URL

# Test connection manually
psql -h localhost -U nova_user -d nova_streaming -c "SELECT 1;"
```

### Tests Failing

**Problem**: Database not ready for tests

```bash
# Create test database
docker-compose -f docker-compose.dev.yml up postgres
sleep 5
sqlx database create --database-url postgresql://nova_user:nova_password@localhost:5433/nova_streaming_test
```

**Problem**: Redis connection errors

```bash
# Check Redis service
redis-cli -h localhost ping

# Restart Redis
docker-compose -f docker-compose.dev.yml restart redis
```

### RTMP Streaming Issues

**Problem**: Nginx-RTMP not accepting connections

```bash
# Check RTMP server logs
docker-compose -f docker-compose.dev.yml logs nginx-rtmp

# Verify RTMP server is listening
curl -v rtmp://localhost:1935/stat 2>&1 | head -20

# Test RTMP connection with simple stream
ffmpeg -f lavfi -i color=blue:s=1280x720:d=5 -f lavfi -i sine=frequency=1000:duration=5 \
  -c:v libx264 -preset fast -b:v 2000k -c:a aac -b:a 128k \
  -f flv rtmp://localhost:1935/live/test-stream
```

### WebSocket Connection Issues

**Problem**: WebSocket connection refused

```bash
# Check if user service is running
curl -I http://localhost:8081/metrics

# Check WebSocket endpoint
curl -v -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  'ws://localhost:8081/api/v1/streams/test-id/ws?token=test-token'

# Look for errors in logs
docker-compose -f docker-compose.dev.yml logs user-service | grep -i websocket
```

### Metrics Not Appearing

**Problem**: Prometheus metrics empty

```bash
# Verify metrics endpoint
curl http://localhost:8081/metrics | head -30

# Check specific metric
curl http://localhost:8081/metrics | grep nova_streaming

# Verify metrics are being recorded
# Check application logs for metric recording
RUST_LOG=debug cargo run -p user-service
```

### Performance Issues

**Problem**: Slow API responses

```bash
# Check service logs for slow queries
docker-compose -f docker-compose.dev.yml logs -f user-service

# Analyze slow queries
# Run test and capture timing
time curl http://localhost:8081/api/v1/streams/active \
  -H "Authorization: Bearer $JWT_TOKEN"

# Profile the service
cargo flamegraph -p user-service
```

### Cleanup

#### Full Reset

```bash
# Stop all services
docker-compose -f docker-compose.dev.yml down

# Remove volumes (WARNING: deletes data)
docker-compose -f docker-compose.dev.yml down -v

# Clean build artifacts
cargo clean

# Restart fresh
docker-compose -f docker-compose.dev.yml up -d
sqlx migrate run
```

#### Partial Cleanup

```bash
# Clear only test databases
docker-compose -f docker-compose.dev.yml exec postgres \
  psql -U postgres -c "DROP DATABASE IF EXISTS nova_streaming_test;"

# Flush Redis cache
redis-cli -h localhost FLUSHALL

# Reset Kafka topics
docker-compose -f docker-compose.dev.yml exec kafka \
  kafka-topics.sh --bootstrap-server localhost:9092 --delete-topic streaming-events
```

---

## Next Steps

Once you have your local environment set up:

1. **Read the Architecture Guide**: Understand the system design
2. **Review API Documentation**: See `docs/openapi-streaming.yaml`
3. **Check WebSocket Protocol**: See `docs/websocket-protocol.md`
4. **Run Integration Tests**: `cargo test -p user-service --test '*'`
5. **Start Building**: Create your first feature following TDD

## References

- [Rust Official Guide](https://doc.rust-lang.org/book/)
- [Docker Documentation](https://docs.docker.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Redis Documentation](https://redis.io/documentation)
- [Nginx-RTMP Module](https://github.com/arut/nginx-rtmp-module)
- [Nova API Documentation](./openapi-streaming.yaml)
- [Nova WebSocket Protocol](./websocket-protocol.md)

---

## Support

For issues or questions:

1. Check the [Troubleshooting](#troubleshooting) section above
2. Review service logs: `docker-compose -f docker-compose.dev.yml logs -f`
3. Search existing documentation
4. Open an issue on GitHub with detailed reproduction steps
