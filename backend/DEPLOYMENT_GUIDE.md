# Video Ranking Service - Deployment Guide
## Phase 4 Phase 3: Complete Deployment Instructions

**Version**: 1.0
**Last Updated**: 2025-10-19
**Status**: Production Ready

---

## 📋 Table of Contents
1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Kubernetes Deployment](#kubernetes-deployment)
4. [Configuration Management](#configuration-management)
5. [Monitoring & Alerting](#monitoring--alerting)
6. [Performance Verification](#performance-verification)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Services
- ✅ Kubernetes 1.24+ cluster
- ✅ PostgreSQL 14+
- ✅ Redis 7.0+
- ✅ ClickHouse 23.x+
- ✅ Kafka 3.x+
- ✅ Prometheus & Grafana

### Required Secrets
- PostgreSQL connection string
- Redis connection URL
- ClickHouse credentials
- Kafka broker addresses
- JWT signing keys (RSA-2048)
- AWS S3 credentials
- TLS certificates

### System Requirements
- CPU: 500m per pod (requested), 2000m (limit)
- Memory: 512Mi per pod (requested), 2Gi (limit)
- Disk: 50Gi minimum for PVC
- Network: Standard Kubernetes networking

---

## Pre-Deployment Checklist

### 1. Database Setup
```bash
# Verify PostgreSQL connection
psql postgresql://user:pass@postgres-service:5432/nova

# Run migrations
cargo run --manifest-path backend/user-service/Cargo.toml \
  --bin user-service -- migrate

# Expected output:
# Running migrations...
# Migration 001_initial_schema.sql: OK
# Migration 012_deep_learning_models.sql: OK
# Migrations completed successfully
```

### 2. ClickHouse Schema
```bash
# Initialize ClickHouse tables
clickhouse-client --host clickhouse-service \
  < backend/clickhouse/init-db.sql

# Verify tables exist
clickhouse-client --query "SHOW TABLES IN nova"
# Expected: video_ranking_signals_1h, user_watch_history_realtime, etc.
```

### 3. Redis Validation
```bash
# Test Redis connection
redis-cli -h redis-service ping
# Expected: PONG
```

### 4. Kafka Topics
```bash
# Create required topics
kafka-topics --bootstrap-server kafka:9092 \
  --create --topic engagement-events \
  --partitions 3 --replication-factor 2

kafka-topics --bootstrap-server kafka:9092 \
  --create --topic cdc.posts \
  --partitions 3 --replication-factor 2
```

### 5. Secrets Creation
```bash
# Create database secret
kubectl create secret generic database-credentials \
  --from-literal=url='postgresql://user:pass@postgres:5432/nova' \
  -n nova

# Create Redis secret
kubectl create secret generic redis-credentials \
  --from-literal=url='redis://redis-service:6379' \
  -n nova

# Create ClickHouse secret
kubectl create secret generic clickhouse-credentials \
  --from-literal=username=default \
  --from-literal=password=password123 \
  -n nova

# Create AWS credentials
kubectl create secret generic aws-credentials \
  --from-literal=access-key-id='AKXXXXXXXXX' \
  --from-literal=secret-access-key='secret...' \
  -n nova

# Create JWT keys
kubectl create secret generic jwt-keys \
  --from-file=private-key=./jwt_private.pem \
  --from-file=public-key=./jwt_public.pem \
  -n nova
```

### 6. ConfigMaps Creation
```bash
# Create ClickHouse config
kubectl create configmap clickhouse-config \
  --from-literal=url='http://clickhouse-service:8123' \
  --from-literal=database='nova' \
  -n nova

# Create Kafka config
kubectl create configmap kafka-config \
  --from-literal=brokers='kafka-0:9092,kafka-1:9092,kafka-2:9092' \
  --from-literal=events-topic='engagement-events' \
  -n nova

# Create S3 config
kubectl create configmap s3-config \
  --from-literal=endpoint='s3.amazonaws.com' \
  --from-literal=region='us-east-1' \
  --from-literal=bucket='nova-videos' \
  -n nova
```

---

## Kubernetes Deployment

### 1. Create Namespace
```bash
kubectl create namespace nova
kubectl label namespace nova monitoring=enabled
```

### 2. Deploy Service
```bash
# Build and push Docker image
docker build -t video-ranking-service:1.0.0 -f backend/user-service/Dockerfile backend/user-service/
docker tag video-ranking-service:1.0.0 docker.io/nova/video-ranking-service:1.0.0
docker push docker.io/nova/video-ranking-service:1.0.0

# Apply Kubernetes manifests
kubectl apply -f backend/k8s/video-ranking-deployment.yaml -n nova

# Verify deployment
kubectl get deployments -n nova
kubectl get pods -n nova
```

### 3. Verify Rollout
```bash
# Watch rollout progress
kubectl rollout status deployment/video-ranking-service -n nova

# Expected: "deployment "video-ranking-service" successfully rolled out"
```

### 4. Check Service Health
```bash
# Port-forward for testing
kubectl port-forward svc/video-ranking-service 8000:80 -n nova

# Test health endpoints
curl http://localhost:8000/api/v1/health
curl http://localhost:8000/api/v1/health/ready
curl http://localhost:8000/api/v1/health/live

# Expected: 200 OK responses
```

---

## Configuration Management

### Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| APP_ENV | production | Environment mode |
| DATABASE_URL | - | PostgreSQL connection string |
| REDIS_URL | - | Redis connection URL |
| CLICKHOUSE_URL | - | ClickHouse HTTP endpoint |
| CLICKHOUSE_DATABASE | nova | ClickHouse database name |
| KAFKA_BROKERS | - | Comma-separated Kafka broker addresses |
| RUST_LOG | info | Logging level |

### Configuration Updates
```bash
# Update ConfigMap
kubectl edit configmap kafka-config -n nova

# Update Secret
kubectl delete secret database-credentials -n nova
kubectl create secret generic database-credentials \
  --from-literal=url='new-postgresql-url' \
  -n nova

# Restart pods to pick up changes
kubectl rollout restart deployment/video-ranking-service -n nova
```

---

## Monitoring & Alerting

### 1. Prometheus Integration
```bash
# Verify ServiceMonitor is scraped
kubectl get servicemonitor -n nova

# Check Prometheus targets
curl http://prometheus:9090/api/v1/targets
```

### 2. Key Metrics to Track
```
# Cache Performance
feed_cache_hits_total
feed_cache_misses_total
feed_cache_hit_rate (derived)

# Feed Generation
feed_generation_duration_seconds (histogram)
feed_generation_success_total
feed_generation_total

# System Health
http_requests_total
http_request_duration_seconds
```

### 3. Alerting Rules
**Critical Alerts**:
- Cache hit rate < 85% (5m)
- Feed generation latency P95 > 500ms (2m)
- Redis connection errors (5m)
- Service pods in crash loop

**Warning Alerts**:
- Feed generation latency P95 > 300ms (5m)
- Database connection pool < 20% available
- ClickHouse query error rate > 0.05/sec
- Memory usage > 90% of limit

### 4. Grafana Dashboards
Create dashboards showing:
- Cache hit rate trends
- Feed generation latency percentiles
- Request throughput
- Error rates
- Pod resource usage
- Database connection pool status

---

## Performance Verification

### 1. Baseline Testing
```bash
# Test personalized feed endpoint
time curl -X GET \
  'http://localhost:8000/api/v1/reels?limit=40' \
  -H 'Authorization: Bearer $JWT_TOKEN'

# Expected: < 100ms (cache hit), < 300ms (cache miss)
```

### 2. Load Testing
```bash
# Using k6 load testing
k6 run --vus 10 --duration 30s backend/loadtest/feed_load_test.js

# Expected metrics:
# - P50 latency: < 100ms
# - P95 latency: < 300ms
# - P99 latency: < 500ms
# - Error rate: < 0.1%
```

### 3. Cache Warm-up
```bash
# Warm cache for top users before go-live
POST /api/v1/admin/cache-warmup
{
  "user_count": 1000,
  "batch_size": 10
}

# Expected: Completes in ~2 seconds for 1000 users
```

---

## Troubleshooting

### Issue: High Feed Generation Latency

**Symptoms**:
- P95 latency > 300ms consistently
- Cache hit rate normal

**Diagnosis**:
```bash
# Check ClickHouse query performance
clickhouse-client --query "SELECT query_duration_ms FROM system.query_log
  WHERE query LIKE '%video_ranking_signals%' ORDER BY event_time DESC LIMIT 10"

# Check database connection pool
curl http://localhost:8000/metrics | grep database_pool
```

**Solutions**:
1. Add indexes to ClickHouse tables
2. Increase database connection pool size
3. Optimize ranking algorithm weights
4. Scale up ClickHouse cluster

### Issue: Low Cache Hit Rate

**Symptoms**:
- Cache hit rate < 85%
- Redis connection successful

**Diagnosis**:
```bash
# Check cache key distribution
redis-cli KEYS "feed:u:*" | wc -l
redis-cli INFO stats | grep hits
```

**Solutions**:
1. Increase cache TTL
2. Implement predictive warming
3. Check for cache invalidation issues
4. Review user activity patterns

### Issue: Out of Memory

**Symptoms**:
- Pod restarts due to OOMKilled
- Memory usage approaching 2Gi limit

**Diagnosis**:
```bash
# Check pod resource usage
kubectl top pod -n nova

# Check memory allocation per component
curl http://localhost:8000/metrics | grep memory
```

**Solutions**:
1. Increase pod memory limit
2. Reduce ranking signals cache size
3. Implement pagination for large feeds
4. Profile memory allocations

### Issue: Pod Crash Loop

**Symptoms**:
- Pod keeps restarting
- Restart count increasing

**Diagnosis**:
```bash
# Check pod logs
kubectl logs -n nova deployment/video-ranking-service --tail=100

# Check pod events
kubectl describe pod -n nova <pod-name>
```

**Solutions**:
1. Verify all secrets and ConfigMaps exist
2. Check database connectivity
3. Review startup probe timeout settings
4. Check resource limits aren't too restrictive

---

## Rollback Procedure

### To Previous Version
```bash
# Check deployment history
kubectl rollout history deployment/video-ranking-service -n nova

# Rollback to previous revision
kubectl rollout undo deployment/video-ranking-service -n nova

# Verify rollback
kubectl rollout status deployment/video-ranking-service -n nova
```

---

## Post-Deployment Verification

```bash
# 1. Health checks pass
curl http://localhost:8000/api/v1/health

# 2. Metrics are being scraped
curl http://prometheus:9090/api/v1/query?query=feed_cache_hits_total

# 3. Cache is warming up
# Monitor cache_hits_total metric for steady increase

# 4. Feed generation working
curl -X GET 'http://localhost:8000/api/v1/reels' \
  -H 'Authorization: Bearer $JWT_TOKEN'

# 5. All alerts cleared
# Check Prometheus/Grafana alert status
```

---

## Production Runbook

### During Peak Hours
- Monitor cache hit rate (should stay > 90%)
- Watch feed generation latency P95
- Check database connection pool availability
- Verify Kafka lag for engagement events

### Maintenance Windows
1. Backup ClickHouse data
2. Rotate JWT signing keys (zero-downtime)
3. Update ranking weights (A/B test first)
4. Optimize ClickHouse table indices

### Emergency Procedures
- **Cache down**: Switch to ClickHouse-only mode (slower but functional)
- **Database down**: Service returns cached feeds from Redis
- **Kafka down**: Engagement events queued locally (memory loss on crash)

---

**Deployment Status**: ✅ Ready for Production

For support, contact: platform-engineering@example.com
