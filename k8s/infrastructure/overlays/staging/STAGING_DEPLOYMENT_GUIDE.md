# Nova Staging Environment Deployment Guide

**Version**: 2.0 (Comprehensive Production-Ready)
**Last Updated**: 2025-11-14
**Scope**: Complete staging environment setup supporting 14 microservices + all dependencies

---

## Overview

This guide covers the deployment of a production-ready staging environment for Nova, supporting:
- **14 Rust microservices** + GraphQL gateway
- **gRPC** service-to-service communication (port 50051)
- **Multi-database architecture**: PostgreSQL (15 databases), Redis Cluster, ClickHouse, Kafka, Neo4j
- **Managed infrastructure** with Kustomize + ArgoCD

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│                   (nova-staging namespace)                  │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │          Microservices (14 services)                   │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐              │ │
│  │  │user-svc  │ │content   │ │feed-svc  │ ...          │ │
│  │  │:50051    │ │:50051    │ │:50051    │              │ │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘              │ │
│  │       │            │            │                      │ │
│  │  ┌────▼────────────▼────────────▼────┐               │ │
│  │  │   gRPC Service Discovery (DNS)     │               │ │
│  │  │   nova-grpc-services (headless)    │               │ │
│  │  └────────────────────────────────────┘               │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           Data & Messaging Layer                       │ │
│  │  ┌─────────────┐  ┌──────────┐  ┌──────────┐         │ │
│  │  │PostgreSQL   │  │Redis     │  │Kafka +   │         │ │
│  │  │(StatefulSet)│  │Cluster   │  │Zookeeper │         │ │
│  │  │15 databases │  │3 nodes   │  │1 node    │         │ │
│  │  └─────────────┘  └──────────┘  └──────────┘         │ │
│  │  ┌────────────┐  ┌──────────┐                        │ │
│  │  │ClickHouse  │  │Neo4j     │                        │ │
│  │  │(CRD)       │  │(external)│                        │ │
│  │  └────────────┘  └──────────┘                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │        Initialization & Orchestration                  │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │ Startup Jobs (run sequentially)                 │  │ │
│  │  │ 1. PostgreSQL init (15 databases + users)      │  │ │
│  │  │ 2. SQLx migrations (all services)              │  │ │
│  │  │ 3. Redis cluster topology                       │  │ │
│  │  │ 4. Kafka topic creation                         │  │ │
│  │  │ 5. ClickHouse database initialization           │  │ │
│  │  │ 6. Proto validation                             │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  │                                                         │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │ Init Containers (dependency ordering)           │  │ │
│  │  │ Each service waits for its dependencies before  │  │ │
│  │  │ starting (kafka, redis, postgres, gRPC svc)    │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required
- Kubernetes cluster (1.21+)
- kubectl configured with access to nova-staging namespace
- Kustomize 4.0+
- ArgoCD (optional, for GitOps deployment)

### AWS Requirements
- ECR access for container images
- S3 for Terraform state (nova-terraform-state bucket)
- Secrets Manager with nova-staging secrets
- ap-northeast-1 region

### Storage Classes
- gp3 storage class configured (used by PostgreSQL, Redis, ClickHouse)

```bash
# Verify storage class
kubectl get storageclass
```

## Pre-Deployment Checklist

- [ ] Kubernetes cluster is accessible
- [ ] nova-staging namespace exists
- [ ] External Secrets Operator is installed
- [ ] ClickHouse Operator is installed (for ClickHouse support)
- [ ] AWS Secrets Manager has nova-staging secrets
- [ ] gp3 storage class is available
- [ ] Image registry credentials are configured

## Deployment Steps

### Step 1: Verify Prerequisites

```bash
# Check namespace
kubectl get namespace nova-staging

# Verify storage class
kubectl get storageclass | grep gp3

# Check for required operators
kubectl get deployment -A | grep "external-secrets\|clickhouse-operator"

# Test AWS credentials
aws secretsmanager get-secret-value \
  --secret-id nova-staging \
  --region ap-northeast-1
```

### Step 2: Apply Kustomization

```bash
# Navigate to staging overlays
cd k8s/infrastructure/overlays/staging

# Preview changes (dry-run)
kubectl kustomize . | head -50

# Apply all resources
kubectl apply -k .

# Monitor deployment
kubectl rollout status -n nova-staging deployment/user-service --timeout=5m
```

### Step 3: Verify Initialization Jobs

Monitor the initialization sequence (runs in dependency order):

```bash
# Watch initialization progress
kubectl get jobs -n nova-staging -w

# Check PostgreSQL initialization
kubectl logs -n nova-staging job/seed-data-job -f

# Check SQLx migrations
kubectl logs -n nova-staging job/sqlx-migrate -f

# Check Redis cluster init
kubectl logs -n nova-staging job/redis-cluster-init -f

# Check Kafka topics
kubectl logs -n nova-staging job/kafka-init-topics -f

# Check ClickHouse initialization
kubectl logs -n nova-staging job/clickhouse-init -f

# Check proto validation
kubectl logs -n nova-staging job/proto-validate -f
```

### Step 4: Verify Service Startup

```bash
# Wait for all pods to be ready (should take ~3-5 minutes)
kubectl wait --for=condition=ready pod \
  -l app=user-service \
  -n nova-staging \
  --timeout=5m

# Check all service pods
kubectl get pods -n nova-staging | grep -E "service|postgres|redis|kafka|clickhouse"

# Verify Init Containers ran successfully
kubectl describe pod user-service-xxx -n nova-staging | grep -A 5 "Init Containers"
```

### Step 5: Validate Service Communication

```bash
# Test gRPC service discovery
kubectl get svc -n nova-staging | grep -E "user-service|feed-service|grpc"

# Test DNS resolution from within cluster
kubectl run -it --rm --image=busybox --restart=Never \
  -n nova-staging \
  -- nslookup user-service.nova-staging.svc.cluster.local

# Test gRPC endpoint
kubectl run -it --rm --image=grpcurl/grpcurl --restart=Never \
  -n nova-staging \
  -- grpcurl -plaintext user-service.nova-staging.svc.cluster.local:50051 list
```

### Step 6: Validate Data Layer

```bash
# PostgreSQL: Connect and verify databases
PGPASSWORD=$(kubectl get secret nova-db-credentials -n nova-staging -o jsonpath='{.data.password}' | base64 -d)

kubectl run -it --rm --image=postgres:15 --restart=Never \
  -n nova-staging \
  -e PGPASSWORD=$PGPASSWORD \
  -- psql -h postgres -U postgres -d postgres -c "\l" | grep nova_

# Redis: Check cluster topology
kubectl exec -it redis-cluster-0 -n nova-staging -- redis-cli cluster info

# Kafka: List topics
kubectl exec -it kafka-0 -n nova-staging -- \
  kafka-topics.sh --bootstrap-server kafka:9092 --list

# ClickHouse: Verify databases
kubectl exec -it nova-clickhouse-0 -n nova-staging -- \
  clickhouse-client --query "SHOW DATABASES;"
```

## Key Configuration Files

### P0: Core Infrastructure

**grpc-services.yaml**
- 15 Kubernetes Service definitions
- Each service on port 50051 (gRPC) + 9090 (metrics)
- Enables DNS-based service discovery
- Headless service for internal discovery

**sqlx-migrate-job.yaml**
- Creates 15 PostgreSQL databases
- Runs SQLx migrations for each service
- Ensures schema initialization before services start
- Runs automatically as Job with automatic cleanup

**postgres-multi-db-init.yaml**
- ConfigMaps with SQL initialization scripts
- Creates 14 service-specific databases
- Creates per-service users with least-privilege access
- Enables UUID and crypto extensions

### P1: Service Orchestration

**service-init-containers-patch.yaml**
- Init Containers for 8 critical services
- Dependency chains:
  - feed-service → user-service + kafka
  - messaging-service → user-service + postgres
  - search-service → postgres + elasticsearch
  - analytics-service → kafka + clickhouse
  - ranking-service → redis + postgres
  - realtime-chat-service → user-service + messaging-service + redis
  - trust-safety-service → postgres + kafka

### P2: Data Infrastructure

**redis-cluster-statefulset.yaml**
- 3-node Redis Cluster
- Persistent volumes (10Gi each)
- Cluster topology initialization
- Used by: notification, ranking, realtime-chat services

**kafka-zookeeper-deployment.yaml**
- Single-node Kafka + Zookeeper (staging)
- Automatic topic creation for 9 topics
- Used by: feed-service, analytics-service, trust-safety-service

**clickhouse-installation.yaml**
- ClickHouseInstallation CRD (requires ClickHouse Operator)
- Configured for analytics workload
- Tables for: events, user_activity, content_metrics, feed_analytics, service_metrics

### P3: API Contract Management

**proto-management.yaml**
- ConfigMaps with Protocol Buffer definitions
- Service registry with dependency graph
- Version tracking (current: 1.0.0)
- Proto validation job

## Service Dependencies Map

```
Core (no dependencies):
├── user-service
├── media-service
├── notification-service
└── identity-service

Depends on user-service:
├── content-service
├── graph-service
├── messaging-service
└── trust-safety-service

Depends on multiple services:
├── feed-service (user + content + kafka)
├── search-service (content + elasticsearch)
├── ranking-service (user + content + redis)
├── analytics-service (kafka + clickhouse)
└── realtime-chat-service (user + messaging + redis)

Gateway:
└── graphql-gateway (all services)
```

## Database Mapping

| Service | Database | User | Purpose |
|---------|----------|------|---------|
| auth-service | nova_auth | nova_auth_svc | Authentication |
| user-service | nova_user | nova_user_svc | User profiles |
| content-service | nova_content | nova_content_svc | User-generated content |
| feed-service | nova_feed | nova_feed_svc | Feed generation |
| messaging-service | nova_messaging | nova_messaging_svc | Direct messaging |
| search-service | nova_search | nova_search_svc | Search indexes |
| notification-service | nova_notification | nova_notification_svc | Notifications |
| media-service | nova_media | nova_media_svc | Media metadata |
| analytics-service | nova_analytics | nova_analytics_svc | Analytics events |
| graph-service | nova_graph | nova_graph_svc | Relationship graphs |
| ranking-service | nova_ranking | nova_ranking_svc | Ranking scores |
| feature-store | nova_feature_store | nova_feature_store_svc | ML features |
| identity-service | nova_identity | nova_identity_svc | Identity verification |
| trust-safety-service | nova_trust_safety | nova_trust_safety_svc | Safety checks |
| realtime-chat-service | nova_realtime_chat | nova_realtime_chat_svc | Real-time chat |

## Monitoring & Verification

### Service Health

```bash
# Check service pod status
kubectl get pods -n nova-staging -o wide

# Check resource usage
kubectl top nodes
kubectl top pods -n nova-staging

# Check logs
kubectl logs -n nova-staging deployment/user-service --tail=50 -f

# Check events
kubectl get events -n nova-staging --sort-by='.lastTimestamp'
```

### Database Health

```bash
# PostgreSQL: Check connections
kubectl exec -it postgres-0 -n nova-staging -- \
  psql -U postgres -c "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;"

# Redis: Check cluster status
kubectl exec -it redis-cluster-0 -n nova-staging -- \
  redis-cli cluster nodes

# Kafka: Check broker status
kubectl exec -it kafka-0 -n nova-staging -- \
  kafka-broker-api-versions.sh --bootstrap-server kafka:9092
```

### gRPC Service Discovery

```bash
# Verify service endpoints
kubectl get endpoints -n nova-staging | grep service

# Test gRPC reflection
kubectl run -it --rm --image=grpcurl/grpcurl --restart=Never \
  -n nova-staging \
  -- grpcurl -plaintext user-service:50051 grpc.reflection.v1.ServerReflection/ListServices
```

## Troubleshooting

### Services not starting

**Symptoms**: Pods stuck in InitContainers

```bash
# Check init container logs
kubectl logs -n nova-staging pod/feed-service-xxx -c wait-for-user-service

# Solution: Verify dependency service is running
kubectl get pods -n nova-staging | grep user-service
```

### Database initialization failed

**Symptoms**: sqlx-migrate job failing

```bash
# Check job logs
kubectl logs -n nova-staging job/sqlx-migrate

# Verify PostgreSQL is running
kubectl exec -it postgres-0 -n nova-staging -- pg_isready

# Check database connectivity
kubectl run -it --rm --image=postgres:15 --restart=Never \
  -n nova-staging \
  -- psql -h postgres -c "SELECT version();"
```

### gRPC connection failures

**Symptoms**: Services unable to reach other services

```bash
# Verify service DNS resolution
kubectl run -it --rm --image=busybox --restart=Never \
  -n nova-staging \
  -- nslookup user-service.nova-staging.svc.cluster.local

# Check network policies
kubectl get networkpolicies -n nova-staging

# Verify service ports
kubectl get svc -n nova-staging -o wide | grep grpc
```

### Redis cluster initialization issues

**Symptoms**: redis-cluster-init job failing

```bash
# Check Redis pod readiness
kubectl get pods -n nova-staging | grep redis-cluster

# Verify cluster topology
kubectl exec -it redis-cluster-0 -n nova-staging -- \
  redis-cli cluster info

# Check Redis logs
kubectl logs -n nova-staging redis-cluster-0 --tail=50
```

## Performance Tuning

### PostgreSQL
```bash
# Increase max_connections if needed
kubectl patch statefulset postgres -n nova-staging \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/env/0", "value": {"name": "POSTGRES_INIT_ARGS", "value": "-c max_connections=200"}}]'
```

### Redis
```bash
# Increase memory limit
kubectl patch statefulset redis-cluster -n nova-staging \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "1Gi"}}]'
```

### Kafka
```bash
# Increase log retention
kubectl set env deployment/kafka \
  -n nova-staging \
  KAFKA_LOG_RETENTION_HOURS=240
```

## Security Considerations

1. **Credentials**: All passwords stored in AWS Secrets Manager
2. **Network Policies**: Services communicate via internal DNS
3. **RBAC**: Use service accounts for pod authentication
4. **Encryption**: Enable encryption at rest for databases
5. **TLS**: Enable mutual TLS for inter-service communication

## Cleanup

```bash
# Delete all staging resources
kubectl delete namespace nova-staging

# Or, delete only specific resources
kubectl delete -k k8s/infrastructure/overlays/staging -n nova-staging
```

## Rollback

If deployment fails:

```bash
# Rollback specific deployment
kubectl rollout undo deployment/user-service -n nova-staging

# Rollback all via GitOps (if using ArgoCD)
argocd app rollback nova-staging
```

## Next Steps

1. **Enable Ingress**: Configure ingress for GraphQL gateway
2. **Enable TLS**: Configure cert-manager for HTTPS
3. **Setup Monitoring**: Deploy Prometheus + Grafana
4. **Setup Logging**: Configure ELK or Loki for log aggregation
5. **Setup CI/CD**: Configure ArgoCD for automatic deployments
6. **Load Testing**: Run capacity testing before production

## Support & Documentation

- Protocol Buffer definitions: `proto-management.yaml`
- Service registry: `nova-service-registry` ConfigMap
- Database schema: `postgres-multi-db-init.yaml`
- Dependency graph: `service-init-containers-patch.yaml`

---

**Last Updated**: 2025-11-14
**Status**: Production-Ready
**Maintained By**: DevOps Team
