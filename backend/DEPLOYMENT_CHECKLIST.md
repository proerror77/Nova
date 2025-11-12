# Production Deployment Checklist - Nova Microservices Platform

**Document Version**: 1.0
**Last Updated**: 2025-11-12
**Scope**: Production deployments of all Nova microservices
**Deployment Window**: Saturday 2:00 AM UTC (low-traffic window)

---

## Service Deployment Dependency Order

The following 5-tier dependency chain MUST be respected during deployment:

### Tier 1: Foundation Services (Identity & Authentication)
- **identity-service** (Core auth foundation)

### Tier 2: User Management
- **user-service** (Depends on identity-service)

### Tier 3: Core Content Platform
- **content-service** (Depends on user-service)

### Tier 4: Social & Graph Infrastructure
- **social-service** (Depends on content-service)
- **graph-service** (Depends on social-service)

### Tier 5: Advanced Features
- **feed-service** (Depends on graph-service)
- **ranking-service** (Depends on feed-service)
- **analytics-service** (Depends on ranking-service)
- **notification-service** (Depends on content-service)
- **realtime-chat-service** (Depends on user-service)
- **search-service** (Depends on content-service)
- **media-service** (Depends on content-service)
- **trust-safety-service** (Depends on content-service)

### Tier 6: API Gateway (Final)
- **graphql-gateway** (Depends on all Tier 1-5 services)

---

## Pre-Deployment Phase (T-24 Hours)

### Infrastructure Readiness Checks

- [ ] **Kubernetes Cluster Health**
  - [ ] All nodes in Ready state
  - [ ] No disk pressure or memory pressure conditions
  - [ ] Kubelet version matches cluster requirements
  - [ ] All system pods running (kube-proxy, coredns, etc.)

- [ ] **Database Cluster Status**
  - [ ] Primary database accepts read/write operations
  - [ ] All replicas synchronized (replication lag < 1s)
  - [ ] PgBouncer connection pool healthy
  - [ ] Verify 3+ healthy standby replicas exist
  - [ ] WAL archiving to S3 working correctly

- [ ] **Storage Systems**
  - [ ] Persistent volumes have >30% free capacity
  - [ ] No failed volume claims
  - [ ] S3/object storage buckets accessible and healthy

- [ ] **Observability Stack**
  - [ ] Prometheus scraping all targets (>98% success rate)
  - [ ] Jaeger accepting traces
  - [ ] Elasticsearch/logging accepting log ingest
  - [ ] AlertManager configured with all channels

### Database Backup & Point-in-Time Recovery

- [ ] **Full Database Backup Completed**
  - [ ] Backup size verified (>10GB expected)
  - [ ] Backup timestamp recorded: _______________
  - [ ] Backup stored in S3 with versioning enabled
  - [ ] Backup encryption verified (KMS key in use)
  - [ ] Test restore on staging cluster completed
  - [ ] PITR available for last 30 days

### Security Audit Pre-Deployment

- [ ] **Secrets Management**
  - [ ] All hardcoded credentials removed
  - [ ] AWS Secrets Manager has all required secrets
  - [ ] JWT signing keys rotated
  - [ ] Database passwords meet complexity requirements
  - [ ] Kubernetes External Secrets operator syncing

- [ ] **Network Security**
  - [ ] Network policies enforce pod-to-pod communication
  - [ ] Ingress TLS certificates valid (not expiring within 30 days)
  - [ ] DNS CAA records configured
  - [ ] VPC security groups reviewed

- [ ] **API Security**
  - [ ] All HTTP endpoints require authentication
  - [ ] Rate limiting configured
  - [ ] CORS headers properly configured
  - [ ] Request validation middleware enabled

- [ ] **Dependency Security Scan**
  - [ ] cargo audit: 0 vulnerabilities with CVSS > 6.0
  - [ ] Container image scan passed (no HIGH/CRITICAL)
  - [ ] Helm chart dependencies up-to-date

### Capacity Planning & Resource Validation

- [ ] **Compute Capacity**
  - [ ] Current cluster utilization < 70% CPU, < 75% memory
  - [ ] Autoscaling configured (min: 5, max: 20 nodes)
  - [ ] Cluster has >40% spare capacity after deployment

- [ ] **Database Capacity**
  - [ ] Table sizes analyzed and acceptable
  - [ ] Query plans reviewed
  - [ ] Connection limits set appropriately
  - [ ] Connection pool max < database max

### Service Health Baseline

- [ ] **Current Metrics Recorded** (at T-24h)
  - [ ] P99 latency (current): ________________ ms
  - [ ] P95 latency (current): ________________ ms
  - [ ] Error rate (current): ________________ %
  - [ ] Throughput (current): ________________ req/s

- [ ] **Health Check Endpoints Verified**
  - [ ] Each service responds to /health with 200 OK
  - [ ] Each service responds to /metrics
  - [ ] Database connections in health check pass
  - [ ] Cache connections (Redis) pass

---

## Pre-Deployment Phase (T-1 Hour)

### Final Health Checks

- [ ] **Staging Environment Validation**
  - [ ] All services running on staging
  - [ ] Staging tests passing (>95% pass rate)
  - [ ] Load test shows acceptable latency
  - [ ] Stress test completed without failures

- [ ] **Production-like Load Testing**
  - [ ] 5-minute load test at 50% expected peak traffic
  - [ ] 5-minute load test at 100% expected peak traffic
  - [ ] Error rate remains <0.1%
  - [ ] No memory leaks (heap growth <5%)

### Staging Validation

- [ ] **End-to-End Test Suite**
  - [ ] Run smoke tests against staging
  - [ ] Create test user and verify authentication flow
  - [ ] Create test post/content and verify distribution
  - [ ] Verify message sending and real-time delivery

- [ ] **Database Migration Validation**
  - [ ] All pending migrations executed without errors
  - [ ] Data integrity validated
  - [ ] Backward compatibility verified
  - [ ] Rollback procedure tested manually

### Communication Readiness

- [ ] **Incident Communications Setup**
  - [ ] Slack #incidents channel active
  - [ ] PagerDuty on-call engineer notified and confirmed
  - [ ] Incident commander assigned: ____________________
  - [ ] Status page set to "Maintenance Window"
  - [ ] External stakeholders notified via email

- [ ] **Monitoring & Alerting**
  - [ ] Alerting rules reviewed and thresholds confirmed
  - [ ] Alert channels verified (PagerDuty, Slack, email)
  - [ ] Grafana dashboards loaded and visible
  - [ ] Custom deployment metrics dashboard created

- [ ] **Rollback Plan Ready**
  - [ ] Rollback commands documented and tested
  - [ ] Previous version images available in registry
  - [ ] Database rollback scripts verified (< 10 min)

---

## Canary Deployment Phase (T+0 to T+15 minutes)

### Initial Canary Deployment (5% Traffic)

- [ ] **Tier 1: Identity Service Canary**
  - [ ] Deploy to 1 pod (5% traffic)
  - [ ] Pod logs checked for startup errors
  - [ ] Readiness probe passing
  - [ ] Liveness probe passing

### Canary Metrics & Monitoring (5% Traffic)

**Monitor for 5 minutes before proceeding:**

- [ ] **Error Rates**
  - [ ] Error rate on canary: < 0.5%
  - [ ] 5xx errors: 0
  - [ ] 4xx errors: < 0.1%

- [ ] **Latency Metrics**
  - [ ] P99 latency: < baseline + 20%
  - [ ] P95 latency: < baseline + 15%
  - [ ] P50 latency: < baseline + 10%

- [ ] **Resource Consumption**
  - [ ] CPU usage: < 200m
  - [ ] Memory usage: < 256Mi
  - [ ] Disk I/O: normal
  - [ ] Network bandwidth: normal

- [ ] **Dependency Health**
  - [ ] Database connection pool healthy
  - [ ] Cache (Redis) connection stable
  - [ ] Outbound gRPC calls succeeding: >99%
  - [ ] Message queue (Kafka) lag: < 10s

### Go/No-Go Decision: 5% Canary

**PASS CRITERIA (ALL must pass):**
- [ ] Error rate < 0.5%
- [ ] P99 latency < baseline + 20%
- [ ] No 5xx errors
- [ ] No pod crashes or restarts
- [ ] Logs show normal operation

**IF PASS**: Proceed to 25% → **GO**
**IF FAIL**: Immediately rollback → **NO-GO**

**Decision Made By**: ________________
**Timestamp**: ________________

---

## Progressive Rollout Phase

### Stage 1: 25% Traffic (T+15 to T+30 minutes)

- [ ] **Scale Tier 1: Identity Service to 5 Pods**
  - [ ] All 5 pods running and ready
  - [ ] Monitor for 10 minutes
  - [ ] All dependencies healthy

| Metric | Baseline | Threshold | Actual | Status |
|--------|----------|-----------|--------|--------|
| Error Rate | baseline | <0.5% | ___ | [ ] |
| P99 Latency | baseline | <+20% | ___ | [ ] |
| CPU Usage | ___ | <300m | ___ | [ ] |
| Memory Usage | ___ | <350Mi | ___ | [ ] |

**Go/No-Go Decision**: [ ] GO to 50%  [ ] NO-GO

---

### Stage 2: 50% Traffic (T+30 to T+45 minutes)

- [ ] **Scale Tier 2: User Service to 5 Pods**
  - [ ] Monitor rollout
  - [ ] All pods running and ready
  - [ ] Monitor for 10 minutes

| Metric | Baseline | Threshold | Actual | Status |
|--------|----------|-----------|--------|--------|
| Error Rate | baseline | <0.5% | ___ | [ ] |
| P99 Latency | baseline | <+20% | ___ | [ ] |
| CPU Usage | ___ | <400m | ___ | [ ] |
| Memory Usage | ___ | <450Mi | ___ | [ ] |

**Go/No-Go Decision**: [ ] GO to 100%  [ ] NO-GO

---

### Stage 3: 100% Rollout (T+45 to T+90 minutes)

- [ ] **Tier 3: Content Service** (T+45) - 5 pods, validate < 0.5% error rate
- [ ] **Tier 4: Social & Graph** (T+55) - Deploy in parallel, monitor 10 min
- [ ] **Tier 5: Advanced Features** (T+65) - Deploy all, monitor 15 min
- [ ] **Tier 6: GraphQL Gateway** (T+85) - Deploy last, validate schema

**Full System Metrics** (at T+90)

| Metric | Baseline | Threshold | Actual | Status |
|--------|----------|-----------|--------|--------|
| Error Rate | baseline | <0.3% | ___ | [ ] |
| P99 Latency | baseline | <+15% | ___ | [ ] |
| Cluster CPU | ___ | <60% | ___ | [ ] |
| Cluster Memory | ___ | <70% | ___ | [ ] |

**Final Go/No-Go Decision**: [ ] SUCCESSFUL  [ ] ROLLBACK

---

## Post-Deployment Verification Phase (T+90 to T+120 minutes)

### Verification Queries

```sql
-- 1. Verify all services reporting metrics
SELECT service_name, COUNT(*) as metric_count, MAX(timestamp) as last_report
FROM metrics WHERE timestamp > now() - interval '5 minutes'
GROUP BY service_name ORDER BY last_report DESC;

-- 2. Check data anomalies
SELECT COUNT(*) as user_count FROM users WHERE created_at > now() - interval '5 minutes';
SELECT COUNT(*) as content_count FROM posts WHERE created_at > now() - interval '5 minutes';

-- 3. Check replication lag
SELECT slot_name, active FROM pg_replication_slots;

-- 4. Verify outbox pattern
SELECT COUNT(*) as pending_events FROM outbox WHERE processed_at IS NULL;
```

### Traffic Pattern Analysis

- [ ] **Real User Monitoring**
  - [ ] Traffic distribution normal
  - [ ] Geographic distribution normal
  - [ ] User session duration normal
  - [ ] Page load times < 2s (p95)

- [ ] **API Usage Patterns**
  - [ ] GraphQL query complexity within limits
  - [ ] Mutation execution times acceptable
  - [ ] Subscription handshakes: >99%

### Record New Baselines (T+120)

| Metric | New Baseline | Previous | Change | Status |
|--------|--------------|----------|--------|--------|
| P99 Latency | ________________ | ________________ | ±__% | [ ] |
| P95 Latency | ________________ | ________________ | ±__% | [ ] |
| Error Rate | ________________ | ________________ | ±__% | [ ] |
| Throughput | ________________ | ________________ | ±__% | [ ] |

---

## Rollback Trigger Conditions

**Critical (Immediate Rollback):**
- Error rate > 5% for >1 minute
- P99 latency > baseline × 2.0 for >2 minutes
- Service completely unavailable (0 healthy pods)
- Data corruption detected
- Auth/authz failures >1% of requests
- DB connection pool exhaustion
- Disk space < 1GB free
- OOM kill events
- Network partition

**High Priority (Rollback within 5 min):**
- Error rate > 2% for >5 minutes
- P99 latency > baseline × 1.5 for >5 minutes
- Memory usage > 80% (sustained)
- CPU throttling affecting >30%
- DB query time degradation > 100%
- Cache hit rate < 70%
- Queue lag > 60 seconds

### Rollback Execution

```bash
# Execute in reverse dependency order
kubectl rollout undo deployment/graphql-gateway -n nova-prod
kubectl rollout undo deployment/feed-service -n nova-prod
kubectl rollout undo deployment/user-service -n nova-prod
kubectl rollout undo deployment/identity-service -n nova-prod

# Monitor rollback
kubectl rollout status deployment/identity-service -n nova-prod

# Verify stability (60 seconds)
for i in {1..12}; do
  kubectl logs -l app=identity-service --tail=100 -n nova-prod
  sleep 5
done
```

---

## Success Criteria

**Deployment is SUCCESSFUL if ALL criteria met:**

- [ ] All services in desired replica count
- [ ] Error rate increase < 0.5%
- [ ] P99 latency increase < 20%
- [ ] No Critical severity alerts
- [ ] Database replication lag < 1s
- [ ] All health checks green
- [ ] Smoke tests passing
- [ ] No data loss/corruption
- [ ] Within planned window
- [ ] Stakeholders notified

---

## Post-Deployment Checklist (T+2 hours)

- [ ] Remove maintenance window from status page
- [ ] Archive war room recordings
- [ ] Collect and review logs
- [ ] Update deployment runbook
- [ ] Close temporary bypass configs
- [ ] Verify backups resumed
- [ ] Team debrief (30 min)
- [ ] Schedule post-mortem if needed
- [ ] Notify business stakeholders

---

## Document Sign-Off

| Role | Name | Signature | Date | Time |
|------|------|-----------|------|------|
| Engineering Lead | | | | |
| Platform Engineer | | | | |
| On-Call Engineer | | | | |
| Incident Commander | | | | |

**Document Approval**: [ ] Approved  [ ] With Changes  [ ] Not Approved

**Next Deployment Window**: ____________________
**Post-Deployment Review**: ____________________
