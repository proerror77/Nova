# Nova Backend - Deployment Guide

**Version:** 1.0
**Last Updated:** 2025-11-06
**Phase:** 1B Deployment Preparation

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Environment Configuration](#environment-configuration)
4. [Local Development Deployment](#local-development-deployment)
5. [Staging Deployment](#staging-deployment)
6. [Production Deployment](#production-deployment)
7. [Database Migrations](#database-migrations)
8. [Monitoring Setup](#monitoring-setup)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

- **Docker** 24.0+ and **Docker Compose** 2.20+
- **Kubernetes** 1.28+ (for production)
- **kubectl** 1.28+
- **kustomize** 5.0+ (optional, for K8s overlays)
- **Rust** 1.75+ (for local development)
- **PostgreSQL** 15+ client tools
- **Redis** 7+ client tools

### Infrastructure Dependencies

- **PostgreSQL** 15+ (relational database)
- **Redis** 7+ (cache and sessions)
- **ClickHouse** 23.11+ (Feed ranking)
- **Kafka** 3.5+ (event streaming)
- **Elasticsearch** 8.11+ (search, optional)
- **AWS S3** or S3-compatible storage (media uploads)

---

## Architecture Overview

### Services

Nova Backend consists of **11 microservices**:

| Service | HTTP Port | gRPC Port | Purpose |
|---------|-----------|-----------|---------|
| **auth-service** | 8083 | 9083 | Authentication, JWT, OAuth |
| **user-service** | 8080 | 9080 | User profiles, relationships |
| **content-service** | 8081 | 9081 | Posts, comments, stories |
| **feed-service** | 8084 | 9084 | Personalized feed ranking |
| **media-service** | 8082 | 9082 | Media uploads, video transcoding |
| **messaging-service** | 8085 | 9085 | Direct messages, group chat |
| **search-service** | 8086 | 9086 | Search, suggestions, trending |
| **streaming-service** | 8087 | 9087 | Live streaming, WebRTC |
| **notification-service** | 8088 | 9088 | Push notifications (APNs, FCM) |
| **cdn-service** | 8089 | 9089 | CDN integration, asset delivery |
| **events-service** | 8090 | 9090 | Event publishing, webhooks |

### Port Convention

**Rule:** `gRPC_PORT = HTTP_PORT + 1000`

Example:
- `auth-service` HTTP: 8083 → gRPC: 9083
- `user-service` HTTP: 8080 → gRPC: 9080

### Service Dependencies

```
┌─────────────────────────────────────────────┐
│  External Dependencies                      │
│  ─────────────────────────                 │
│  • PostgreSQL (all services)                │
│  • Redis (all services)                     │
│  • Kafka (all services)                     │
│  • ClickHouse (feed-service)                │
│  • Elasticsearch (search-service)           │
│  • AWS S3 (media-service)                   │
└─────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────┐
│  Microservices (11 services)                │
│  ────────────────────────                   │
│  • HTTP REST APIs (public)                  │
│  • gRPC APIs (internal)                     │
│  • Health checks (/api/v1/health)           │
└─────────────────────────────────────────────┘
```

---

## Environment Configuration

### 1. Copy Environment Template

```bash
cd backend
cp .env.example .env
```

### 2. Critical Configuration (Must Change)

#### JWT Keys (Production Only)

Generate RSA key pair for JWT signing:

```bash
# Generate private key
openssl genpkey -algorithm RSA -out jwt_private.pem -pkeyopt rsa_keygen_bits:2048

# Extract public key
openssl rsa -pubout -in jwt_private.pem -out jwt_public.pem

# Convert to single-line format for .env
JWT_PRIVATE_KEY_PEM=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' jwt_private.pem)
JWT_PUBLIC_KEY_PEM=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' jwt_public.pem)

# Add to .env
echo "JWT_PRIVATE_KEY_PEM=\"${JWT_PRIVATE_KEY_PEM}\"" >> .env
echo "JWT_PUBLIC_KEY_PEM=\"${JWT_PUBLIC_KEY_PEM}\"" >> .env
```

**Alternative:** Use file paths (recommended for production):

```bash
JWT_PRIVATE_KEY_PATH=/etc/secrets/jwt_private.pem
JWT_PUBLIC_KEY_PATH=/etc/secrets/jwt_public.pem
```

#### Database URL

```bash
# Development
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/nova

# Staging
DATABASE_URL=postgresql://nova_user:STRONG_PASSWORD@staging-db.internal:5432/nova

# Production
DATABASE_URL=postgresql://nova_user:STRONG_PASSWORD@prod-db-primary.internal:5432/nova
```

#### AWS S3 Configuration

```bash
AWS_S3_BUCKET=nova-media-prod
AWS_S3_REGION=us-east-1
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

#### SMTP Configuration

```bash
# Production (SendGrid example)
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=SG....
SMTP_FROM_EMAIL=noreply@nova.app

# Development (MailHog)
SMTP_HOST=localhost
SMTP_PORT=1025
```

### 3. Environment-Specific Overrides

#### Development (.env.dev)

```bash
APP_ENV=development
LOG_LEVEL=debug
DEBUG_SQL_QUERIES=true
DISABLE_AUTH=false  # Keep auth enabled even in dev

# Use local services
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/nova
REDIS_URL=redis://localhost:6379
CLICKHOUSE_URL=http://localhost:8123
KAFKA_BROKERS=localhost:9092
```

#### Staging (.env.staging)

```bash
APP_ENV=staging
LOG_LEVEL=info
DEBUG_SQL_QUERIES=false

# Use staging infrastructure
DATABASE_URL=postgresql://nova_user:STAGING_PASS@staging-db.internal:5432/nova
REDIS_URL=redis://staging-redis.internal:6379
CLICKHOUSE_URL=http://staging-clickhouse.internal:8123
KAFKA_BROKERS=staging-kafka-1.internal:9092,staging-kafka-2.internal:9092

# Staging S3 bucket
AWS_S3_BUCKET=nova-media-staging
```

#### Production (.env.prod)

```bash
APP_ENV=production
LOG_LEVEL=info
DEBUG_SQL_QUERIES=false

# Use production infrastructure (managed)
DATABASE_URL=postgresql://nova_user:PROD_PASS@prod-db-primary.internal:5432/nova
REDIS_URL=redis://prod-redis-cluster.internal:6379
CLICKHOUSE_URL=http://prod-clickhouse-cluster.internal:8123
KAFKA_BROKERS=prod-kafka-1.internal:9092,prod-kafka-2.internal:9092,prod-kafka-3.internal:9092

# Production S3 bucket
AWS_S3_BUCKET=nova-media-prod

# Enable connection pooling
DATABASE_MAX_CONNECTIONS=20
REDIS_POOL_SIZE=50
GRPC_CONNECTION_POOL_SIZE=20
```

---

## Local Development Deployment

### Step 1: Start Infrastructure Services

```bash
cd backend
docker-compose -f docker-compose.prod.yml up -d postgres redis clickhouse kafka
```

Wait for health checks to pass:

```bash
docker-compose -f docker-compose.prod.yml ps
```

Expected output:

```
NAME                  STATUS         PORTS
nova-postgres         Up (healthy)   5432/tcp
nova-redis            Up (healthy)   6379/tcp
nova-clickhouse       Up (healthy)   8123/tcp, 9000/tcp
nova-kafka            Up (healthy)   9092/tcp
```

### Step 2: Run Database Migrations

```bash
# Install sqlx-cli (first time only)
cargo install sqlx-cli --no-default-features --features postgres

# Run migrations
sqlx migrate run --database-url postgresql://postgres:postgres@localhost:5432/nova
```

### Step 3: Build and Run Services

**Option A: Docker Compose (All Services)**

```bash
docker-compose -f docker-compose.prod.yml up -d
```

**Option B: Cargo (Single Service for Development)**

```bash
# Example: Run auth-service locally
cd auth-service
cargo run
```

### Step 4: Verify Deployment

```bash
# Check all services
for port in 8080 8081 8082 8083 8084 8085 8086 8087 8088 8089 8090; do
  echo "Service on port $port:"
  curl -s http://localhost:$port/api/v1/health | jq
done
```

---

## Staging Deployment

### Step 1: Build Docker Images

```bash
cd backend

# Build all services (using unified Dockerfile template)
for service in auth-service user-service content-service feed-service media-service \
               messaging-service search-service streaming-service notification-service \
               cdn-service events-service; do
  echo "Building $service..."
  docker build \
    --build-arg SERVICE_NAME=$service \
    -f Dockerfile.template \
    -t nova-$service:staging \
    ..
done
```

### Step 2: Push to Container Registry

```bash
# Tag and push (replace with your registry)
REGISTRY=your-registry.example.com

for service in auth-service user-service content-service feed-service media-service \
               messaging-service search-service streaming-service notification-service \
               cdn-service events-service; do
  docker tag nova-$service:staging $REGISTRY/nova-$service:staging
  docker push $REGISTRY/nova-$service:staging
done
```

### Step 3: Deploy to Kubernetes (Staging Cluster)

```bash
# Set kubectl context to staging
kubectl config use-context staging-cluster

# Create namespace
kubectl apply -f k8s/base/namespace.yaml

# Create secrets (DO NOT commit secrets to git)
kubectl create secret generic nova-backend-secrets \
  -n nova-backend \
  --from-env-file=.env.staging \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply base manifests
kubectl apply -k k8s/overlays/staging/

# Wait for rollout
kubectl rollout status deployment -n nova-backend --timeout=5m
```

### Step 4: Verify Staging Deployment

```bash
# Check pod status
kubectl get pods -n nova-backend

# Check service endpoints
kubectl get svc -n nova-backend

# Test health endpoints
kubectl port-forward -n nova-backend svc/auth-service 8083:8083 &
curl http://localhost:8083/api/v1/health
```

---

## Production Deployment

### Prerequisites

- [ ] All services pass integration tests
- [ ] Database migrations tested in staging
- [ ] Secrets stored in secure vault (AWS Secrets Manager, HashiCorp Vault)
- [ ] Monitoring and alerting configured
- [ ] Rollback plan prepared

### Deployment Strategy: Canary Release

**Goal:** Gradually roll out new version to minimize risk.

**Phases:**
1. **5% traffic** → 15 minutes monitoring
2. **50% traffic** → 30 minutes monitoring
3. **100% traffic** → Full rollout

### Step 1: Build and Tag Production Images

```bash
VERSION=v1.0.0  # Semantic version

for service in auth-service user-service content-service feed-service media-service \
               messaging-service search-service streaming-service notification-service \
               cdn-service events-service; do
  docker build \
    --build-arg SERVICE_NAME=$service \
    -f Dockerfile.template \
    -t nova-$service:$VERSION \
    -t nova-$service:latest \
    ..

  # Push to production registry
  docker push $REGISTRY/nova-$service:$VERSION
  docker push $REGISTRY/nova-$service:latest
done
```

### Step 2: Update Kubernetes Manifests

Edit `k8s/overlays/prod/kustomization.yaml`:

```yaml
images:
  - name: nova-auth-service
    newTag: v1.0.0  # Update version
  # ... repeat for all services
```

### Step 3: Canary Deployment (5% Traffic)

```bash
# Apply canary overlay (5% traffic to new version)
kubectl apply -k k8s/overlays/prod/canary/

# Monitor for 15 minutes
watch kubectl get pods -n nova-backend -l version=v1.0.0
```

**Monitor metrics:**
- Error rate < 1%
- P95 latency < 500ms
- No increase in 5xx errors

### Step 4: Scale to 50% Traffic

```bash
# Update replicas: 50% old, 50% new
kubectl scale deployment -n nova-backend --replicas=3 auth-service-v1.0.0
kubectl scale deployment -n nova-backend --replicas=3 auth-service-v0.9.0

# Monitor for 30 minutes
```

### Step 5: Full Rollout (100% Traffic)

```bash
# Apply production overlay (100% traffic)
kubectl apply -k k8s/overlays/prod/

# Delete old version
kubectl delete deployment -n nova-backend auth-service-v0.9.0
```

### Step 6: Verify Production Deployment

```bash
# Check all pods are healthy
kubectl get pods -n nova-backend

# Check metrics
kubectl top pods -n nova-backend

# Test health endpoints via LoadBalancer
curl https://api.nova.app/api/v1/health
```

---

## Database Migrations

### Migration Strategy

**Rule:** All migrations must be **backward-compatible** (zero-downtime).

**Safe Patterns:**
- ✅ Add new columns (with default values)
- ✅ Add new tables
- ✅ Add new indexes (CONCURRENTLY in PostgreSQL)
- ❌ Rename columns (requires multi-step migration)
- ❌ Drop columns (requires multi-step migration)

### Running Migrations

**Development:**

```bash
sqlx migrate run --database-url $DATABASE_URL
```

**Staging/Production:**

```bash
# Dry-run (check what will run)
sqlx migrate info --database-url $DATABASE_URL

# Run migrations
sqlx migrate run --database-url $DATABASE_URL

# Verify
psql $DATABASE_URL -c "SELECT * FROM _sqlx_migrations ORDER BY version DESC LIMIT 5;"
```

### Migration Rollback

```bash
# Revert last migration
sqlx migrate revert --database-url $DATABASE_URL

# Revert specific version
sqlx migrate revert --database-url $DATABASE_URL --target-version 20250101000000
```

---

## Monitoring Setup

### Prometheus

**Deploy Prometheus:**

```bash
kubectl apply -f monitoring/prometheus/prometheus-config.yaml
kubectl apply -f monitoring/prometheus/prometheus-deployment.yaml
```

**Verify scraping:**

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets
```

### Grafana

**Deploy Grafana:**

```bash
kubectl apply -f monitoring/grafana/grafana-deployment.yaml
```

**Import Dashboard:**

1. Open Grafana: http://localhost:3000
2. Go to **Dashboards** → **Import**
3. Upload `monitoring/grafana/dashboards/nova-overview.json`

### Alerts

**Configure AlertManager:**

```bash
kubectl apply -f monitoring/prometheus/alertmanager-config.yaml
```

**Test Alert:**

```bash
# Trigger high latency alert (for testing)
kubectl exec -it -n nova-backend auth-service-xxx -- sh -c "sleep 10"
```

---

## Troubleshooting

### Service Won't Start

**Symptom:** Pod in `CrashLoopBackOff` state

**Check logs:**

```bash
kubectl logs -n nova-backend auth-service-xxx --previous
```

**Common causes:**
- Missing environment variables → Check ConfigMap/Secret
- Database connection failure → Check `DATABASE_URL`
- Migration not run → Run `sqlx migrate run`

### High Latency

**Symptom:** P95 latency > 500ms

**Check:**

```bash
# Database connections
psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity;"

# Redis latency
redis-cli --latency

# ClickHouse queries
curl "http://clickhouse:8123/?query=SELECT%20query_duration_ms%20FROM%20system.query_log%20ORDER%20BY%20event_time%20DESC%20LIMIT%2010"
```

### gRPC Connection Refused

**Symptom:** `grpc_client_errors` metric increasing

**Check:**

```bash
# Verify gRPC port is open
kubectl exec -it -n nova-backend user-service-xxx -- netstat -tuln | grep 9080

# Test gRPC health
grpcurl -plaintext user-service:9080 grpc.health.v1.Health/Check
```

### Database Migration Failure

**Symptom:** Migration fails halfway

**Recovery:**

```bash
# Check migration status
sqlx migrate info --database-url $DATABASE_URL

# Manually fix failed migration (if safe)
psql $DATABASE_URL -f backend/migrations/XXXXX_fix.sql

# Mark as completed (DANGEROUS, use with caution)
psql $DATABASE_URL -c "INSERT INTO _sqlx_migrations (version, description, installed_on, success) VALUES (XXXXX, 'Manual fix', NOW(), true);"
```

---

## Quick Reference

### Health Check Endpoints

- **Liveness:** `GET /api/v1/health/live` (returns 200 if process is alive)
- **Readiness:** `GET /api/v1/health/ready` (returns 200 if ready to serve traffic)
- **Detailed:** `GET /api/v1/health` (returns JSON with database status)

### Service Discovery (Kubernetes)

Internal DNS:
- `auth-service.nova-backend.svc.cluster.local:8083`
- `user-service.nova-backend.svc.cluster.local:8080`

Short form (within same namespace):
- `auth-service:8083`
- `user-service:8080`

### Common Commands

```bash
# Restart all services
kubectl rollout restart deployment -n nova-backend

# Scale service
kubectl scale deployment -n nova-backend auth-service --replicas=5

# View logs
kubectl logs -f -n nova-backend -l app=auth-service

# Port-forward for debugging
kubectl port-forward -n nova-backend svc/auth-service 8083:8083
```

---

**Next Steps:**

1. Review [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md) before deploying
2. Set up monitoring dashboards
3. Configure alerts in AlertManager
4. Run smoke tests in staging

**Support:**
- Slack: #nova-backend-ops
- On-call: PagerDuty rotation
- Docs: https://docs.nova.app/backend
