# Staging Infrastructure Verification Checklist
## Pre-Baseline Collection Verification (2025-10-20 09:00 UTC)

**Purpose**: Ensure all staging infrastructure components are healthy and ready for 24-hour baseline collection
**Target**: Complete all checks ≥2 hours before baseline collection starts (09:00 UTC deadline)
**Duration**: ~45 minutes
**Owner**: Ops Team

---

## 🔍 Quick Health Dashboard

```bash
# One-liner to get complete infrastructure status
kubectl get all -n nova-staging && \
kubectl get pvc -n nova-staging && \
kubectl get cm -n nova-staging && \
kubectl get secrets -n nova-staging
```

---

## ✅ Phase 1: Kubernetes Cluster & Namespace

### 1.1 Cluster Access
```bash
kubectl cluster-info
# Expected: Kubernetes master running at [URL]

kubectl get nodes
# Expected: All nodes in Ready status
# Minimum: 3 nodes for staging
```

**Verification**: ☐ Cluster responsive
**Verification**: ☐ All nodes ready

### 1.2 Namespace Status
```bash
kubectl get ns | grep nova-staging
# Expected: nova-staging Active

kubectl describe namespace nova-staging
# Expected: No warnings or errors
```

**Verification**: ☐ Namespace exists
**Verification**: ☐ Namespace active

---

## ✅ Phase 2: Deployment & Pod Status

### 2.1 Deployment Configuration
```bash
kubectl get deployment -n nova-staging
# Expected: video-ranking-deployment with 3 desired replicas

kubectl describe deployment video-ranking-deployment -n nova-staging
# Expected: All replicas ready and updated
```

**Verification**: ☐ Deployment exists
**Verification**: ☐ Desired replicas: 3
**Verification**: ☐ Ready replicas: 3
**Verification**: ☐ Updated replicas: 3

### 2.2 Pod Status
```bash
kubectl get pods -n nova-staging -o wide
# Expected: 3 pods in Running state

# Check individual pod logs
kubectl logs -n nova-staging deployment/video-ranking-deployment --tail=50
# Expected: No ERROR or FATAL messages, only INFO/DEBUG
```

**Verification**: ☐ Pods: 3/3 Running
**Verification**: ☐ Pods: 0 restarts
**Verification**: ☐ All containers ready

### 2.3 Pod Resource Usage
```bash
kubectl top pods -n nova-staging
# Expected:
#   - CPU: <200m per pod (target: <100m)
#   - Memory: <256Mi per pod (target: <128Mi)
```

**Verification**: ☐ CPU within limits
**Verification**: ☐ Memory within limits

### 2.4 HPA Status
```bash
kubectl get hpa -n nova-staging
# Expected: 3 current replicas, min 3, max 10

kubectl describe hpa video-ranking-hpa -n nova-staging
# Expected: Current metrics available, no warnings
```

**Verification**: ☐ HPA exists
**Verification**: ☐ Current: 3 replicas
**Verification**: ☐ Min: 3, Max: 10

---

## ✅ Phase 3: Service & Networking

### 3.1 Service Configuration
```bash
kubectl get svc -n nova-staging
# Expected: video-ranking-service with ClusterIP

kubectl get svc video-ranking-service -n nova-staging -o yaml | grep -A5 "ports:"
# Expected: 8080 (http), 9090 (metrics) exposed
```

**Verification**: ☐ Service exists
**Verification**: ☐ Port 8080: exposed
**Verification**: ☐ Port 9090: exposed

### 3.2 Service Endpoints
```bash
kubectl get endpoints -n nova-staging
# Expected: 3 endpoints (one per pod)

kubectl get endpoints video-ranking-service -n nova-staging -o yaml
# Expected: All pod IPs listed with ports
```

**Verification**: ☐ Endpoints: 3/3 ready
**Verification**: ☐ All ports mapped

### 3.3 DNS Resolution
```bash
# From a pod in the cluster
kubectl run -it --rm debug --image=busybox --restart=Never -n nova-staging -- \
  nslookup video-ranking-service.nova-staging.svc.cluster.local
# Expected: resolves to ClusterIP
```

**Verification**: ☐ DNS resolves correctly

---

## ✅ Phase 4: Health Endpoints

### 4.1 Liveness Probe
```bash
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  curl -s http://localhost:8080/health/live
# Expected: HTTP 200, {"status":"ok"}
```

**Verification**: ☐ Liveness: 200 OK

### 4.2 Readiness Probe
```bash
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  curl -s http://localhost:8080/health/ready
# Expected: HTTP 200, {"status":"ready"}
```

**Verification**: ☐ Readiness: 200 OK

### 4.3 API Endpoints
```bash
# Port-forward to access service
kubectl port-forward -n nova-staging svc/video-ranking-service 8080:8080 &

# Test core endpoints (in another terminal)
curl http://localhost:8080/api/v1/health
curl http://localhost:8080/api/v1/reels?user_id=test-user
curl http://localhost:8080/api/v1/reels/trending-sounds
```

**Verification**: ☐ /api/v1/health: 200 OK
**Verification**: ☐ /api/v1/reels: 200 OK
**Verification**: ☐ Trending endpoints: 200 OK

---

## ✅ Phase 5: External Dependencies

### 5.1 PostgreSQL
```bash
kubectl get pod -n nova-staging -l app=postgres -o wide
# Expected: 1 pod Running

# Test connection
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  psql -h postgres -U nova_user -d nova_db -c "SELECT version();"
# Expected: PostgreSQL version output
```

**Verification**: ☐ PostgreSQL pod: Running
**Verification**: ☐ Connection: Successful
**Verification**: ☐ Database: nova_db exists

### 5.2 Redis
```bash
kubectl get pod -n nova-staging -l app=redis -o wide
# Expected: 1 pod Running (or 3 if cluster)

# Test connection
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  redis-cli -h redis PING
# Expected: PONG
```

**Verification**: ☐ Redis pod(s): Running
**Verification**: ☐ Connection: PONG
**Verification**: ☐ Memory: >500MB available

### 5.3 ClickHouse
```bash
kubectl get pod -n nova-staging -l app=clickhouse -o wide
# Expected: 1 pod Running

# Test connection
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  clickhouse-client -h clickhouse -q "SELECT 1"
# Expected: 1
```

**Verification**: ☐ ClickHouse pod: Running
**Verification**: ☐ Query response: 1
**Verification**: ☐ Tables created (check schema)

### 5.4 Kafka
```bash
kubectl get pod -n nova-staging -l app=kafka -o wide
# Expected: 1-3 pods Running

# Test connection
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  kafka-broker-api-versions.sh --bootstrap-server kafka:9092
# Expected: Version info output
```

**Verification**: ☐ Kafka broker(s): Running
**Verification**: ☐ API version: Available
**Verification**: ☐ Topics: Created (engagement_events, etc.)

---

## ✅ Phase 6: Monitoring & Observability

### 6.1 ServiceMonitor
```bash
kubectl get servicemonitor -n nova-staging
# Expected: video-ranking-monitor exists

kubectl describe servicemonitor video-ranking-monitor -n nova-staging
# Expected: Selector matches service labels
```

**Verification**: ☐ ServiceMonitor: Exists
**Verification**: ☐ Labels: Matched

### 6.2 Prometheus Scraping
```bash
# Access Prometheus UI (port-forward if needed)
# Navigate to: http://prometheus:9090/targets
# Expected: video-ranking-service target in "UP" state

# Or query directly
kubectl exec -it -n monitoring prometheus-0 -- \
  curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job=="video-ranking")'
# Expected: 3 instances (one per pod)
```

**Verification**: ☐ Prometheus targets: UP
**Verification**: ☐ Scrape interval: 15s
**Verification**: ☐ Instances: 3/3 scraped

### 6.3 PrometheusRule
```bash
kubectl get prometheusrule -n nova-staging
# Expected: video-ranking-rules exists

kubectl get prometheusrule video-ranking-rules -n nova-staging -o yaml | grep -c "alert:"
# Expected: 20+ alert rules defined
```

**Verification**: ☐ PrometheusRule: Exists
**Verification**: ☐ Alert rules: 20+

### 6.4 Grafana Dashboards
```bash
# Access Grafana (usually port 3000)
# Expected dashboards:
#   - Video Ranking - System Health
#   - Video Ranking - API Performance
#   - Video Ranking - Cache Performance
#   - Video Ranking - Business Metrics

# Verify data is flowing
# All panels should show metrics (not "No data")
```

**Verification**: ☐ System Health dashboard: Data flowing
**Verification**: ☐ API Performance dashboard: Data flowing
**Verification**: ☐ Cache Performance dashboard: Data flowing
**Verification**: ☐ Business Metrics dashboard: Data flowing

### 6.5 Logs Aggregation
```bash
# Check if logs are being collected
kubectl logs -n nova-staging -l app=video-ranking --tail=100 | head -20
# Expected: Application logs visible

# Check centralized logging (if ELK/Loki is used)
# Verify logs appear in Kibana/Loki UI with proper labels
```

**Verification**: ☐ Logs: Collecting
**Verification**: ☐ Log format: Structured JSON
**Verification**: ☐ Labels: Applied correctly

---

## ✅ Phase 7: Storage & Configuration

### 7.1 Persistent Volumes
```bash
kubectl get pvc -n nova-staging
# Expected: Any required PVCs in Bound state

kubectl describe pvc -n nova-staging
# Expected: Size adequate, no warnings
```

**Verification**: ☐ PVCs: Bound
**Verification**: ☐ Available space: >10GB

### 7.2 ConfigMaps
```bash
kubectl get configmap -n nova-staging
# Expected: video-ranking-config exists

kubectl describe configmap video-ranking-config -n nova-staging
# Expected: All required keys present
```

**Verification**: ☐ ConfigMap: Created
**Verification**: ☐ Keys: All present

### 7.3 Secrets
```bash
kubectl get secrets -n nova-staging
# Expected: database-creds, redis-creds, etc. exist

kubectl describe secret database-creds -n nova-staging
# Expected: Encrypted, not showing values
```

**Verification**: ☐ Secrets: Created
**Verification**: ☐ Encrypted: Yes
**Verification**: ☐ Applied to pods: Yes

---

## ✅ Phase 8: Pre-Baseline Validation

### 8.1 Performance Baseline
```bash
# Run warmup requests to initialize caches
for i in {1..10}; do
  kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
    curl -s http://localhost:8080/api/v1/reels?user_id=baseline-user-$i > /dev/null
done

# Verify cache hit rate
kubectl logs -n nova-staging -l app=video-ranking --tail=50 | grep cache_hit
# Expected: Cache hit rate trending toward 90%+
```

**Verification**: ☐ Cache warming: Complete
**Verification**: ☐ Cache hit rate: >80%

### 8.2 Error Rate Check
```bash
# Check last hour of errors
kubectl logs -n nova-staging -l app=video-ranking --tail=1000 | grep ERROR | wc -l
# Expected: <5 errors in 1000 lines (error rate <0.5%)
```

**Verification**: ☐ Error rate: <0.5%
**Verification**: ☐ No fatal errors: Yes

### 8.3 Pod Stability
```bash
# Check for recent restarts
kubectl get pods -n nova-staging -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'
# Expected: All zeros or very low counts
```

**Verification**: ☐ Pod restarts: 0
**Verification**: ☐ Deployment stable: Yes

---

## ✅ Final Validation Checklist

### Resource Allocation
```bash
# Verify cluster has capacity for baseline collection (may spike to 5x normal)
kubectl describe nodes | grep -A3 "Allocated resources"
# Expected: CPU available: >5000m, Memory available: >20Gi
```

**Verification**: ☐ Cluster capacity: Sufficient
**Verification**: ☐ CPU headroom: >5000m
**Verification**: ☐ Memory headroom: >20Gi

### Network Policies
```bash
kubectl get networkpolicies -n nova-staging
# Expected: Policies configured to allow traffic

kubectl describe networkpolicy -n nova-staging
# Expected: Ingress/egress rules allow necessary traffic
```

**Verification**: ☐ Network policies: Configured
**Verification**: ☐ Connectivity: Allowed

### Security Context
```bash
kubectl get pod -n nova-staging -o jsonpath='{.items[0].spec.securityContext}'
# Expected: runAsNonRoot: true, fsReadOnlyRootFilesystem: true
```

**Verification**: ☐ Security context: Hardened
**Verification**: ☐ Running as non-root: Yes

---

## 🚨 Troubleshooting Quick Reference

| Issue | Check | Solution |
|-------|-------|----------|
| Pod not running | `kubectl describe pod` | Check resource limits, node capacity |
| DNS not resolving | `nslookup` from pod | Check CoreDNS pod status |
| Database connection failed | `psql` test | Verify credentials, network policy |
| Redis connection failed | `redis-cli PING` | Verify Redis pod, network access |
| Metrics not scraping | Check Prometheus targets | Verify ServiceMonitor, labels |
| High error rate | Check logs | Identify root cause, scale if needed |
| Out of resources | `kubectl describe nodes` | Scale down other workloads or add nodes |

---

## 📋 Verification Sign-Off

**Verified By**: ________________
**Timestamp**: ________________
**All Checks Passed**: ☐ YES ☐ NO

**Issues Found** (if any):
```
[List any issues and resolution]
```

**Baseline Collection Approval**: ☐ APPROVED ☐ HOLD

**Notes**:
```
[Add any additional notes for the baseline collection team]
```

---

## 📞 Escalation Path

If ANY checks fail:

1. **L1 (15 min)**: Initial troubleshooting, check logs, restart if safe
2. **L2 (30 min)**: Investigate root cause, review monitoring
3. **L3 (60 min)**: Escalate to Platform Engineering, delay baseline if needed

**Emergency Contact**: On-call (PagerDuty)
**Baseline Start Blocked Until**: All checks pass with L3 approval

