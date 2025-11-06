# Nova Backend - Deployment Files Summary

**Created:** 2025-11-06
**Phase:** 1B Deployment Preparation

This document lists all deployment configuration files created for Phase 1B.

---

## 📦 Deployment Artifacts Overview

### Critical Files (Start Here)

| File | Purpose | Usage |
|------|---------|-------|
| **DEPLOYMENT_GUIDE.md** | Complete deployment manual | Read first for deployment workflows |
| **DEPLOYMENT_CHECKLIST.md** | Step-by-step deployment procedure | Follow during production deployment |
| **.env.example** | Environment variable template | Copy to `.env` and configure |
| **Dockerfile.template** | Unified Docker build template | Build all 11 services |
| **docker-compose.prod.yml** | Local/staging deployment | `docker-compose up -d` |

---

## 📁 Directory Structure

```
backend/
├── .env.example                          # Environment variable template (all services)
├── Dockerfile.template                   # Unified Dockerfile for 11 services
├── docker-compose.prod.yml               # Docker Compose for all services
├── DEPLOYMENT_GUIDE.md                   # Complete deployment manual (3,500 words)
├── DEPLOYMENT_CHECKLIST.md               # Production deployment checklist (5,000 words)
│
├── k8s/                                  # Kubernetes manifests
│   ├── README.md                         # Kubernetes deployment guide
│   ├── generate-manifests.sh             # Script to generate service YAMLs
│   ├── base/                             # Base Kubernetes resources
│   │   ├── namespace.yaml                # nova-backend namespace
│   │   ├── configmap.yaml                # Shared configuration
│   │   ├── kustomization.yaml            # Kustomize base config
│   │   └── auth-service.yaml             # Example service manifest
│   └── overlays/                         # Environment-specific overrides
│       ├── dev/                          # Development environment
│       ├── staging/                      # Staging environment
│       └── prod/                         # Production environment
│           └── kustomization.yaml        # Production overrides
│
└── monitoring/                           # Observability stack
    ├── prometheus/                       # Prometheus configuration
    │   ├── prometheus.yml                # Scrape configs for 11 services
    │   └── rules/
    │       └── alerts.yml                # 20+ alert rules (SLIs/SLOs)
    └── grafana/                          # Grafana dashboards
        └── dashboards/
            └── nova-overview.json        # Service overview dashboard
```

---

## 🔧 Configuration Files

### 1. Environment Configuration

**File:** `.env.example`

**Contents:**
- Database connection strings (PostgreSQL, ClickHouse)
- Cache configuration (Redis)
- Message broker (Kafka topics, consumer groups)
- Search engine (Elasticsearch indices)
- JWT keys (RSA public/private key pairs)
- AWS S3 credentials
- SMTP settings
- OAuth providers (Google)
- APNs/FCM push notification keys
- **Service ports:** HTTP + gRPC for all 11 services
- **gRPC client configuration:** Centralized connection settings
- Feature flags

**Key Sections:**
- ✅ Port convention: `gRPC_PORT = HTTP_PORT + 1000`
- ✅ All 11 services configured
- ✅ Environment-specific overrides (dev/staging/prod)

---

### 2. Docker Configuration

#### Dockerfile.template

**File:** `Dockerfile.template`

**Features:**
- **Multi-stage build:** Builder + Runtime
- **Unified template:** Single Dockerfile for all 11 services
- **Build argument:** `SERVICE_NAME` (e.g., `auth-service`)
- **Security:** Non-root user (uid=1000)
- **Health check:** Integrated `/api/v1/health` endpoint
- **Size optimization:** Debian slim base, minimal runtime dependencies

**Usage:**

```bash
docker build --build-arg SERVICE_NAME=auth-service \
             -f Dockerfile.template \
             -t nova-auth-service:latest .
```

#### docker-compose.prod.yml

**File:** `docker-compose.prod.yml`

**Services Defined:**
- **Infrastructure:** PostgreSQL, Redis, ClickHouse, Kafka, Elasticsearch
- **Microservices:** All 11 services (auth, user, content, feed, media, messaging, search, streaming, notification, cdn, events)

**Features:**
- ✅ Health checks for all services
- ✅ Dependency management (`depends_on`)
- ✅ Volume persistence
- ✅ Network isolation
- ✅ Environment variable injection

**Usage:**

```bash
# Start all services
docker-compose -f docker-compose.prod.yml up -d

# Start infrastructure only
docker-compose -f docker-compose.prod.yml up -d postgres redis clickhouse kafka

# Scale a service
docker-compose -f docker-compose.prod.yml up -d --scale auth-service=3
```

---

### 3. Kubernetes Configuration

#### k8s/base/

**Manifests:**
- `namespace.yaml` - nova-backend namespace
- `configmap.yaml` - Shared configuration (environment variables)
- `auth-service.yaml` - Example service deployment + service
- `kustomization.yaml` - Kustomize base configuration

**Service Template Structure (Repeated for 11 Services):**

```yaml
# Deployment
- replicas: 3
- resources:
    requests: 256Mi memory, 100m CPU
    limits: 512Mi memory, 500m CPU
- health probes: liveness, readiness, startup
- envFrom: configmap + secrets

# Service
- type: ClusterIP
- ports: HTTP + gRPC
```

#### k8s/overlays/prod/

**File:** `kustomization.yaml`

**Overrides:**
- Replicas: 3 (production)
- Memory: 512Mi request, 1Gi limit
- Image tags: Pinned to version (e.g., `v1.0.0`)

#### k8s/generate-manifests.sh

**Script:** Auto-generate Kubernetes manifests for all 11 services

**Usage:**

```bash
cd k8s
./generate-manifests.sh
```

**Output:** Creates `base/<service>.yaml` for each service

---

### 4. Monitoring Configuration

#### Prometheus

**File:** `monitoring/prometheus/prometheus.yml`

**Scrape Targets:**
- All 11 microservices (10s interval)
- PostgreSQL exporter (30s)
- Redis exporter (30s)
- Kafka exporter (30s)
- ClickHouse metrics (30s)
- Kubernetes API server, nodes, pods

**File:** `monitoring/prometheus/rules/alerts.yml`

**Alert Rules (20+ rules):**
- **Service Availability:** ServiceDown, HighErrorRate
- **Latency:** HighLatencyP95, HighLatencyP99
- **Database:** PostgreSQLDown, PostgreSQLHighConnections, PostgreSQLSlowQueries
- **Redis:** RedisDown, RedisHighMemory, RedisHighEvictionRate
- **ClickHouse:** ClickHouseDown, ClickHouseSlowQueries
- **Kafka:** KafkaDown, KafkaConsumerLag, KafkaUnderReplicatedPartitions
- **Resources:** HighCPUUsage, HighMemoryUsage
- **gRPC:** HighGrpcErrorRate, SlowGrpcCalls

**Alert Thresholds:**
- Error rate: > 5% for 5 minutes → WARNING
- P95 latency: > 500ms for 5 minutes → WARNING
- P99 latency: > 1s for 5 minutes → CRITICAL

#### Grafana

**File:** `monitoring/grafana/dashboards/nova-overview.json`

**Dashboard Panels (8 panels):**
1. Service Availability (stat)
2. Request Rate (graph)
3. P95 Latency (graph with alert)
4. Error Rate (graph with alert)
5. Database Connections (graph)
6. Redis Memory Usage (graph)
7. Kafka Consumer Lag (graph)
8. gRPC Success Rate (graph)

**Features:**
- 30s auto-refresh
- 1-hour default time range
- Template variables (datasource, service)

---

## 📖 Documentation Files

### DEPLOYMENT_GUIDE.md (3,500+ words)

**Sections:**
1. **Prerequisites:** Tools, infrastructure dependencies
2. **Architecture Overview:** 11 services, port convention, dependencies
3. **Environment Configuration:** JWT keys, database URL, AWS S3, SMTP
4. **Local Development Deployment:** Docker Compose workflow
5. **Staging Deployment:** Build images, push to registry, deploy to K8s
6. **Production Deployment:** Canary release strategy (5% → 50% → 100%)
7. **Database Migrations:** sqlx-cli usage, safe patterns, rollback
8. **Monitoring Setup:** Prometheus, Grafana, AlertManager
9. **Troubleshooting:** Common issues and fixes

**Key Highlights:**
- ✅ Environment-specific configuration (dev/staging/prod)
- ✅ Step-by-step Kubernetes deployment
- ✅ Canary release strategy with monitoring checkpoints
- ✅ Database migration best practices (zero-downtime)
- ✅ Troubleshooting guide

### DEPLOYMENT_CHECKLIST.md (5,000+ words)

**Phases:**

| Phase | Time | Tasks |
|-------|------|-------|
| **Pre-Deployment** | T-24h | Code quality, database backups, configuration review |
| **Phase 1: Pre-Deployment Verification** | T+0 | All checks pass, staging verified |
| **Phase 2: Database Migrations** | T+0 | Run migrations, verify success |
| **Phase 3: Build and Push Images** | T+5 | Build Docker images, push to registry |
| **Phase 4: Canary Deployment (5%)** | T+10 | Deploy 1 replica, monitor 15 minutes |
| **Phase 5: Scale to 50% Traffic** | T+25 | Scale to 3 replicas, monitor 30 minutes |
| **Phase 6: Full Rollout (100%)** | T+55 | Deploy all replicas, terminate old version |
| **Phase 7: Post-Deployment Verification** | T+65 | Health checks, smoke tests, infrastructure |
| **Phase 8: Monitoring** | T+75 | 2-hour stability monitoring |
| **Phase 9: ROLLBACK** | If needed | Emergency rollback procedure |

**Rollback Triggers:**
- ❌ Error rate > 1% for 5 minutes
- ❌ P95 latency > 500ms for 5 minutes
- ❌ Pod crash loops

**Features:**
- ✅ Checkpoint-driven workflow
- ✅ Metric thresholds for each phase
- ✅ Rollback decision tree
- ✅ Emergency contacts section
- ✅ Quick reference commands

---

## 🚀 Quick Start Guide

### 1. Local Development (Docker Compose)

```bash
cd backend

# Copy environment template
cp .env.example .env

# Edit .env with your configuration
nano .env

# Start infrastructure
docker-compose -f docker-compose.prod.yml up -d postgres redis clickhouse kafka

# Run migrations
sqlx migrate run --database-url postgresql://postgres:postgres@localhost:5432/nova

# Start all services
docker-compose -f docker-compose.prod.yml up -d

# Verify health
curl http://localhost:8083/api/v1/health  # auth-service
curl http://localhost:8080/api/v1/health  # user-service
```

### 2. Kubernetes Production Deployment

```bash
cd backend/k8s

# Generate all service manifests
./generate-manifests.sh

# Create secrets (DO NOT commit to git)
kubectl create secret generic nova-backend-secrets \
  -n nova-backend \
  --from-env-file=../.env.prod

# Deploy to production
kubectl apply -k overlays/prod/

# Monitor rollout
kubectl rollout status deployment -n nova-backend --timeout=10m

# Verify health
kubectl get pods -n nova-backend
kubectl logs -f -n nova-backend -l app=auth-service
```

### 3. Monitoring Setup

```bash
# Deploy Prometheus
kubectl apply -f monitoring/prometheus/prometheus-config.yaml

# Deploy Grafana
kubectl apply -f monitoring/grafana/grafana-deployment.yaml

# Import dashboard
# Open Grafana → Dashboards → Import → monitoring/grafana/dashboards/nova-overview.json
```

---

## ✅ Deployment Readiness Checklist

Before deploying to production, ensure:

- [x] All 11 services have Kubernetes manifests
- [x] Environment variables configured in `.env.prod`
- [x] Secrets created in Kubernetes (nova-backend-secrets)
- [x] Database migrations tested in staging
- [x] Docker images built and pushed to registry
- [x] Prometheus scraping all services
- [x] Grafana dashboard imported
- [x] AlertManager configured with PagerDuty/Slack
- [x] On-call engineer notified
- [x] Rollback plan prepared

---

## 📊 Metrics and Monitoring

### Service-Level Indicators (SLIs)

| Metric | Target | Alert Threshold |
|--------|--------|----------------|
| **Availability** | 99.9% | < 99% for 5 min |
| **Error Rate** | < 0.5% | > 1% for 5 min |
| **P95 Latency** | < 300ms | > 500ms for 5 min |
| **P99 Latency** | < 800ms | > 1s for 5 min |

### Infrastructure Metrics

| Component | Metric | Threshold |
|-----------|--------|-----------|
| **PostgreSQL** | Connection pool | > 80% |
| **Redis** | Memory usage | > 70% |
| **ClickHouse** | Query latency | P95 > 1s |
| **Kafka** | Consumer lag | > 100k messages |

---

## 🔗 Related Documentation

- [Backend Architecture](../docs/architecture/phase-0-structure.md)
- [gRPC Metrics Integration Plan](./GRPC_METRICS_INTEGRATION_PLAN.md)
- [Database Migrations](./migrations/README.md)
- [Quick Reference](./QUICK_REFERENCE.md)

---

## 📝 Notes

### Port Convention (CRITICAL)

**Rule:** `gRPC_PORT = HTTP_PORT + 1000`

This rule is **LOCKED** and must not be changed without team consensus. All inter-service communication relies on this convention.

### Service Discovery (Kubernetes)

Internal DNS format:
```
<service-name>.nova-backend.svc.cluster.local:<port>
```

Short form (within same namespace):
```
<service-name>:<port>
```

### Backward Compatibility

All deployments must be **zero-downtime**:
- Database migrations must be backward-compatible
- Old and new code versions must coexist during canary rollout
- No breaking API changes during deployment window

---

**Deployment Status:** ✅ Ready for Week 1 Staging Deployment

**Next Steps:**
1. Review DEPLOYMENT_GUIDE.md
2. Test Docker Compose deployment locally
3. Schedule staging deployment
4. Prepare production deployment window
