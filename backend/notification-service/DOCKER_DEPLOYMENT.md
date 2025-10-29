# Notification Service - Docker & CI/CD Deployment Guide

## Overview

Complete Docker and CI/CD setup for the notification service, supporting local development, testing, and production deployment.

## Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- Rust 1.75+ (for local builds)
- Git

## Local Development Setup

### Quick Start with Docker Compose

```bash
# Start all services (PostgreSQL, Redis, Kafka, Notification Service)
docker-compose -f docker-compose.notification.yml up -d

# View logs
docker-compose -f docker-compose.notification.yml logs -f notification-service

# Stop services
docker-compose -f docker-compose.notification.yml down
```

### Service Endpoints

| Service | URL | Port |
|---------|-----|------|
| Notification Service API | http://localhost:8000 | 8000 |
| PostgreSQL | localhost | 5433 |
| Redis | localhost | 6380 |
| Kafka Broker | localhost | 9093 |
| Zookeeper | localhost | 2182 |
| Prometheus Metrics | http://localhost:9091 | 9091 |

### Environment Variables

Create `.env.notification` for local configuration:

```env
# Service Configuration
RUST_LOG=info
PORT=8000

# Database
DATABASE_URL=postgres://nova_user:nova_password@localhost:5433/nova_notifications

# Redis
REDIS_URL=redis://localhost:6380

# Kafka
KAFKA_BROKERS=localhost:9093
KAFKA_TOPIC=notifications
KAFKA_GROUP_ID=notifications-consumer

# FCM Configuration (optional)
FCM_API_KEY=your_fcm_key_here
FCM_SENDER_ID=your_sender_id

# APNs Configuration (optional)
APNS_BUNDLE_ID=com.example.app
APNS_KEY_ID=your_key_id
APNS_TEAM_ID=your_team_id
APNS_CERTIFICATE_PATH=/path/to/cert.p8

# Features
ENABLE_FCM=true
ENABLE_APNS=false
ENABLE_WEBSOCKET=false
```

### Testing Locally

```bash
# Run all tests
cd backend
cargo test --package notification-service

# Run specific test suite
cargo test --package notification-service --test api_integration_tests

# Run with output
cargo test --package notification-service -- --nocapture

# Generate coverage report
cargo tarpaulin --package notification-service
```

## Docker Image Building

### Build Locally

```bash
# Build image
docker build -f backend/notification-service/Dockerfile -t notification-service:latest .

# Build with specific tag
docker build -f backend/notification-service/Dockerfile \
  -t notification-service:v1.0.0 \
  -t notification-service:latest .

# Build and run
docker run -p 8000:8000 \
  -e DATABASE_URL=postgres://user:password@host/db \
  -e REDIS_URL=redis://host:6379 \
  notification-service:latest
```

### Image Specifications

- **Base Image**: `debian:bookworm-slim` (runtime)
- **Build Stage**: `rust:1.75`
- **Size**: ~150MB compressed
- **Startup Time**: ~2-3 seconds
- **Health Check**: HTTP GET `/health` every 30s

## Docker Compose Configuration

### Services Included

1. **notification-service** - Main application
2. **postgres** - PostgreSQL 16 database
3. **redis** - Redis cache store
4. **kafka** - Kafka message broker
5. **zookeeper** - Kafka coordination
6. **prometheus** - Metrics collection

### Volume Management

```bash
# List volumes
docker volume ls | grep notification

# Clean up volumes
docker-compose -f docker-compose.notification.yml down -v

# Backup database
docker exec notification-postgres pg_dump -U nova_user nova_notifications > backup.sql

# Restore database
docker exec -i notification-postgres psql -U nova_user nova_notifications < backup.sql
```

### Database Migrations

Migrations are automatically applied on container startup from:
- `backend/notification-service/migrations/` directory

To add new migrations:

```bash
# Create migration file
sqlx migrate add -r <migration_name>

# Run migrations
sqlx migrate run
```

## CI/CD Pipeline

### GitHub Actions Workflow

**Location**: `.github/workflows/ci.yml`

**Triggers**:
- Push to `main`, `develop`, `feature/backend-optimization`
- Pull requests to `main` or `develop`
- Any changes to notification-service or related libs

### Pipeline Stages

#### 1. Check
```bash
cargo check --package notification-service --all-targets
```
- Verifies compilation without errors
- Fast feedback on syntax issues

#### 2. Format
```bash
cargo fmt --package notification-service -- --check
```
- Ensures code follows Rust formatting standards
- Uses rustfmt

#### 3. Clippy Lint
```bash
cargo clippy --package notification-service --all-targets -- -D warnings
```
- Warns about idiomatic Rust issues
- All warnings treated as errors

#### 4. Test Suite
```bash
cargo test --package notification-service --verbose
```
- Runs all 73 unit and integration tests
- Tests run against PostgreSQL container
- Coverage: 100% of public API

#### 5. Docker Build
```bash
docker buildx build --file backend/notification-service/Dockerfile
```
- Builds and caches Docker image
- Only runs on main branch merges
- Uses BuildKit for faster builds

#### 6. Code Coverage
```bash
cargo tarpaulin --package notification-service --out Xml
```
- Generates coverage reports
- Uploads to Codecov.io
- Tracks coverage trends

#### 7. Security Audit
```bash
cargo audit
```
- Checks for known vulnerabilities
- Runs against RustSec database
- Prevents vulnerable dependencies

### Build Status Badge

Add to README:

```markdown
![CI Status](https://github.com/yourusername/nova/actions/workflows/ci.yml/badge.svg?branch=main)
```

## Production Deployment

### Kubernetes Deployment

See `backend/k8s/notification-service-deployment.yaml` for full K8s manifests.

```bash
# Deploy to cluster
kubectl apply -f backend/k8s/notification-service-deployment.yaml

# Check status
kubectl get pods -l app=notification-service

# View logs
kubectl logs -l app=notification-service --tail=100

# Scale replicas
kubectl scale deployment notification-service --replicas=3
```

### Docker Registry Push

```bash
# Tag image
docker tag notification-service:latest myregistry.azurecr.io/notification-service:latest

# Push to registry
docker push myregistry.azurecr.io/notification-service:latest

# Pull from registry
docker pull myregistry.azurecr.io/notification-service:latest
```

### Environment Variables for Production

```env
# Service
RUST_LOG=warn
PORT=8000

# Database (RDS/Cloud SQL)
DATABASE_URL=postgres://user:securepass@rds-instance.amazonaws.com/nova_notifications

# Redis (ElastiCache/Cloud Memorystore)
REDIS_URL=redis://redis-instance.com:6379

# Kafka (MSK/Cloud Pub/Sub)
KAFKA_BROKERS=kafka-broker-1.com:9092,kafka-broker-2.com:9092
KAFKA_TOPIC=notifications
KAFKA_CONSUMER_GROUP=notifications-prod

# Security
FCM_API_KEY=${FCM_API_KEY}
APNS_CERTIFICATE_PATH=${APNS_CERT_SECRET}

# Monitoring
DATADOG_ENABLED=true
DATADOG_API_KEY=${DATADOG_KEY}
```

## Monitoring & Observability

### Health Checks

```bash
# Check service health
curl http://localhost:8000/health
# Response: OK

# Check detailed metrics
curl http://localhost:8000/metrics
```

### Prometheus Metrics

Access Prometheus at `http://localhost:9091`

Key metrics:
- `notification_service_requests_total` - Total requests
- `notification_service_request_duration_seconds` - Response time
- `notification_service_messages_queued` - Queue size
- `notification_service_batch_flush_duration_seconds` - Batch flush time
- `notification_service_errors_total` - Error count

### Logging

```bash
# View logs from docker-compose
docker-compose -f docker-compose.notification.yml logs notification-service

# Follow logs in real-time
docker-compose -f docker-compose.notification.yml logs -f notification-service

# Filter logs
docker-compose -f docker-compose.notification.yml logs --since 10m notification-service
```

## Troubleshooting

### Connection Issues

```bash
# Check if services are running
docker-compose -f docker-compose.notification.yml ps

# Check network connectivity
docker-compose -f docker-compose.notification.yml exec notification-service \
  curl -s http://postgres:5432 || echo "Cannot reach postgres"

# Inspect network
docker network inspect backend_notification-network
```

### Database Issues

```bash
# Connect to database
docker exec -it notification-postgres psql -U nova_user -d nova_notifications

# Check database size
SELECT pg_size_pretty(pg_database_size('nova_notifications'));

# View connection count
SELECT count(*) FROM pg_stat_activity;
```

### Performance Issues

```bash
# Check memory usage
docker stats notification-service

# Check Kafka lag
docker exec notification-kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --group notifications-consumer \
  --describe

# Monitor query performance
docker exec notification-postgres \
  psql -U nova_user -d nova_notifications \
  -c "SELECT * FROM pg_stat_statements LIMIT 10;"
```

## Best Practices

1. **Always use health checks** - Services won't be marked ready until health check passes
2. **Mount volumes for persistence** - Database and cache data survive container restarts
3. **Use environment variables** - Separate configuration from code
4. **Set resource limits** - Prevent containers from consuming all system resources
5. **Enable logging** - Use structured logging with log levels
6. **Monitor metrics** - Track performance and errors in production
7. **Regular backups** - Backup database before major deployments
8. **Version images** - Tag images with semantic versioning

## Related Documentation

- [API Documentation](./API_DOCUMENTATION.md)
- [Test Coverage](./TEST_COVERAGE.md)
- [Architecture](../../docs/NOTIFICATION_SERVICE_ARCHITECTURE.md)
- [Kubernetes Deployment](../k8s/notification-service-deployment.yaml)
- [Database Schema](./migrations/)
