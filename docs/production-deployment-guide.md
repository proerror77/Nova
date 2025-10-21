# Production Deployment Guide

## Overview

This guide covers the complete production deployment of Nova Streaming platform. Production deployments require careful planning, extensive testing, and strict change control procedures. This document ensures all deployments follow established best practices and minimize downtime.

## Table of Contents

1. [Pre-Deployment Requirements](#pre-deployment-requirements)
2. [Deployment Architecture](#deployment-architecture)
3. [Deployment Procedures](#deployment-procedures)
4. [Blue-Green Deployment](#blue-green-deployment)
5. [Monitoring and Validation](#monitoring-and-validation)
6. [Rollback Procedures](#rollback-procedures)
7. [Post-Deployment Tasks](#post-deployment-tasks)

---

## Pre-Deployment Requirements

### 1. Prerequisites

All of the following must be satisfied before proceeding:

- [ ] **Staging deployment successful**
  - Staging environment must have passed all acceptance tests
  - Performance metrics must meet SLOs
  - No critical issues remaining
  - Team sign-off obtained (see Staging Deployment Checklist)

- [ ] **Change approval obtained**
  - Technical lead: approval document
  - Product owner: approval document
  - Security team: security review completed
  - Infrastructure team: infrastructure review completed

- [ ] **Capacity planning completed**
  - Database capacity: > 30% free space
  - Cache capacity: > 50% free space
  - Kubernetes nodes: > 20% free resources
  - Network bandwidth: > 40% available

- [ ] **Disaster recovery prepared**
  - Backup verified and tested
  - Recovery time objective (RTO): < 1 hour
  - Recovery point objective (RPO): < 15 minutes
  - Runbook prepared and team trained

### 2. Pre-Deployment Checklist

**24 hours before deployment:**

```bash
# Verify all systems healthy
kubectl get nodes -o wide
kubectl get pvc
kubectl logs -f deployment/user-service | head -20

# Database health
psql -h prod-db.nova-social.io -U nova_admin -c "SELECT version();"
psql -h prod-db.nova-social.io -U nova_admin -c "VACUUM ANALYZE;" 2>&1 | head -5

# Cache health
redis-cli -h prod-redis.nova-social.io INFO server | head -10

# Backup status
aws s3 ls s3://nova-backups/prod/ --recursive | tail -1

# Create deployment ticket
# Link to: Staging results, Change approval, Runbooks
```

**2 hours before deployment:**

```bash
# Final health check
kubectl get all -A | grep -E "NotReady|Failed|Pending"

# Verify backup
aws s3 sync s3://nova-backups/prod/latest . --dryrun

# Test rollback procedure
# (In non-production, or as dry-run)

# Notify stakeholders
# "Deployment starting in 2 hours. Expected downtime: ~10 minutes"
```

### 3. Deployment Window

**Production deployment schedule:**

- **Preferred**: Tuesday - Thursday, 02:00 - 04:00 UTC (maintenance window)
- **Avoid**: Weekends, holidays, end-of-month
- **Duration**: 30-45 minutes estimated
- **Rollback window**: 2 hours

---

## Deployment Architecture

### High-Level Topology

```
┌─────────────────────────────────────────────────────────────┐
│                     PRODUCTION ENVIRONMENT                   │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  CloudFront / AWS Global Accelerator                │   │
│  │  (DDoS protection, caching, global distribution)    │   │
│  └──────────────────────┬───────────────────────────────┘   │
│                         │                                     │
│  ┌──────────────────────┴───────────────────────────────┐   │
│  │  Network Load Balancer                               │   │
│  │  (HTTP/HTTPS termination, SSL/TLS)                   │   │
│  └──────────────┬────────────────────────────────────────┘   │
│                 │                                             │
│  ┌──────────────┼─────────────────────────────────────────┐  │
│  │              │     KUBERNETES CLUSTER                 │  │
│  │              │                                         │  │
│  │  ┌───────────▼──────────┐  ┌──────────────────────┐  │  │
│  │  │ User Service (Blue)  │  │ User Service (Green) │  │  │
│  │  │ - API endpoints      │  │ - API endpoints      │  │  │
│  │  │ - WebSocket handler  │  │ - WebSocket handler  │  │  │
│  │  │ - Metrics exporter   │  │ - Metrics exporter   │  │  │
│  │  └──────────────────────┘  └──────────────────────┘  │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────────┐ │  │
│  │  │ Ingress Controller                               │ │  │
│  │  │ (Routes traffic to Blue or Green)                │ │  │
│  │  └──────────────────────────────────────────────────┘ │  │
│  │                                                        │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌──────────────┬──────────────┬──────────────────────────┐ │
│  │              │              │                          │ │
│  ▼              ▼              ▼                          ▼ │
│ ┌──────┐  ┌──────────┐  ┌─────────┐  ┌──────────────────┐  │
│ │ RDS  │  │ Redis    │  │ Kafka   │  │ ClickHouse       │  │
│ │ (PG) │  │(Cache)   │  │(Events) │  │ (Analytics)      │  │
│ └──────┘  └──────────┘  └─────────┘  └──────────────────┘  │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Nginx-RTMP (Separate deployment)                    │   │
│  │  - RTMP ingest (port 1935)                           │   │
│  │  - Separate load balancer                            │   │
│  │  - Auto-scaling based on stream count                │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Blue-Green Setup Details

**Blue Deployment (Current Production)**
- Service name: `user-service-blue`
- Replica set: user-service-blue-xxxxxxx
- Image: `nova/user-service:v1.2.3`
- Traffic weight: 100%

**Green Deployment (New Version)**
- Service name: `user-service-green`
- Replica set: user-service-green-xxxxxxx
- Image: `nova/user-service:v1.2.4`
- Traffic weight: 0% (initially)

---

## Deployment Procedures

### Phase 1: Pre-Flight Checks (10 minutes)

#### Step 1.1: Verify Current System State

```bash
# Check node status
kubectl get nodes
# Expected: All nodes Ready

# Check resource availability
kubectl top nodes
# Expected: CPU < 60%, Memory < 70%

# Check pod status
kubectl get pods -n production
# Expected: All pods Running

# Check database connections
psql -h prod-db.nova-social.io -U nova_admin \
  -c "SELECT count(*) FROM pg_stat_activity;"
# Expected: Active connections < max_connections * 0.7
```

#### Step 1.2: Create Database Backup

```bash
# Trigger immediate backup
aws rds create-db-snapshot \
  --db-instance-identifier nova-prod \
  --db-snapshot-identifier nova-prod-pre-deploy-v1.2.4 \
  --region us-east-1

# Wait for backup to complete
aws rds describe-db-snapshots \
  --db-snapshot-identifier nova-prod-pre-deploy-v1.2.4 \
  --region us-east-1 \
  --query 'DBSnapshots[0].Status' \
  --output text

# Expected output: "available" (within 5 minutes)
```

#### Step 1.3: Verify Artifacts

```bash
# Check Docker image exists and is scannable
docker pull nova/user-service:v1.2.4
docker run --rm nova/user-service:v1.2.4 --version
# Expected: no errors, version matches v1.2.4

# Verify Helm chart
helm lint k8s/nova-streaming-v1.2.4
# Expected: no errors

# Check configuration
kubectl get configmaps -n production
kubectl get secrets -n production
# Expected: all configurations present
```

### Phase 2: Green Deployment (15 minutes)

#### Step 2.1: Deploy Green Version

```bash
# Create namespace for green deployment (if not exists)
kubectl create namespace production-green --dry-run=client -o yaml | kubectl apply -f -

# Deploy green version with Helm
helm install nova-streaming-green k8s/nova-streaming-v1.2.4 \
  --namespace production-green \
  --values k8s/values-prod.yaml \
  --set image.tag=v1.2.4 \
  --set deployment.name=user-service-green \
  --wait \
  --timeout 10m

# Verify deployment
kubectl get deployment -n production-green
kubectl get pods -n production-green
# Expected: Desired replicas running
```

#### Step 2.2: Wait for Green Health Checks

```bash
# Watch pod startup
kubectl logs -f deployment/user-service-green -n production-green

# Wait for health checks to pass
sleep 30
kubectl get pods -n production-green -o wide
# Expected: All pods Ready=True

# Verify green service is responding
GREEN_POD=$(kubectl get pods -n production-green \
  -l app=user-service-green \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $GREEN_POD -n production-green -- \
  curl http://localhost:8081/health
# Expected: {"status": "healthy"}
```

#### Step 2.3: Run Smoke Tests Against Green

```bash
# Get green service internal IP
GREEN_IP=$(kubectl get svc user-service-green -n production-green \
  -o jsonpath='{.spec.clusterIP}')

# Basic health check
curl http://$GREEN_IP:8081/health

# Metrics endpoint
curl http://$GREEN_IP:8081/metrics | head -10

# API endpoint (with auth)
curl -X GET "http://$GREEN_IP:8081/api/v1/streams/active" \
  -H "Authorization: Bearer $TEST_JWT_TOKEN"

# Expected: All endpoints respond without errors
```

#### Step 2.4: Run Extended Tests Against Green

```bash
# Create test stream on green
TEST_STREAM=$(curl -s -X POST "http://$GREEN_IP:8081/api/v1/streams" \
  -H "Authorization: Bearer $TEST_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Green Smoke Test", "description": ""}' \
  | jq -r '.id')

echo "Test stream ID: $TEST_STREAM"

# Verify stream created
curl -X GET "http://$GREEN_IP:8081/api/v1/streams/$TEST_STREAM" \
  -H "Authorization: Bearer $TEST_JWT_TOKEN" | jq .

# Delete test stream
curl -X DELETE "http://$GREEN_IP:8081/api/v1/streams/$TEST_STREAM" \
  -H "Authorization: Bearer $TEST_JWT_TOKEN"

# Expected: All operations successful
```

### Phase 3: Traffic Switch (5 minutes)

#### Step 3.1: Update Ingress Rules

```bash
# Backup current ingress config
kubectl get ingress api-ingress -n production -o yaml > ingress-backup.yaml

# Update ingress to route to green
kubectl patch ingress api-ingress -n production \
  --type json \
  -p '[
    {
      "op": "replace",
      "path": "/spec/rules/0/http/paths/0/backend/service/name",
      "value": "user-service-green"
    }
  ]'

# Verify update
kubectl get ingress api-ingress -n production -o yaml | grep serviceName
# Expected: user-service-green
```

#### Step 3.2: Monitor Traffic Switch

```bash
# Watch metrics during switch
watch -n 1 'curl -s http://prod-api.nova-social.io/metrics | grep nova_streaming_active_streams'

# Monitor error rates
kubectl logs -f deployment/user-service-green -n production-green | grep -i error

# Check load balancer connection status
kubectl top pods -n production-green
```

#### Step 3.3: Validate Green in Production

```bash
# Verify production API responds correctly
curl -X GET "https://api.nova-social.io/api/v1/streams/active" \
  -H "Authorization: Bearer $PROD_JWT_TOKEN" | jq '.total_count'

# Check metrics
curl -s "https://api.nova-social.io/metrics" | grep nova_streaming

# Monitor error logs
tail -f /var/log/nova/streaming.log | grep -i error
```

#### Step 3.4: Monitor for Issues (10 minutes)

```bash
# Watch for errors
watch -n 5 'kubectl logs -f deployment/user-service-green -n production-green | tail -20'

# Check Prometheus alerts
curl -s "http://prometheus.prod:9090/api/v1/query?query=ALERTS" | jq .

# Monitor user-reported issues
# (Check support channel for complaints)

# If issues detected → Go to Rollback Procedures
```

### Phase 4: Clean Up Blue (5 minutes)

#### Step 4.1: Scale Down Blue Deployment

```bash
# Gracefully scale down blue
kubectl scale deployment user-service-blue -n production --replicas=0

# Verify blue is scaled down
kubectl get pods -n production | grep user-service-blue
# Expected: no pods running
```

#### Step 4.2: Archive Blue for Quick Rollback

```bash
# Keep blue deployment manifest available for quick restart
kubectl get deployment user-service-blue -n production -o yaml > user-service-blue-backup.yaml

# Tag blue image for archival
docker tag nova/user-service:v1.2.3 nova/user-service:v1.2.3-archived-$(date +%Y%m%d-%H%M%S)
```

#### Step 4.3: Final Verification

```bash
# Confirm green is handling all traffic
kubectl top pods -n production-green

# Verify no errors in logs
kubectl logs deployment/user-service-green -n production-green | grep -c ERROR
# Expected: 0

# Check database performance
psql -h prod-db.nova-social.io -U nova_admin \
  -c "SELECT avg(query_time) FROM slow_log WHERE timestamp > NOW() - INTERVAL 5 MINUTES;"
```

---

## Blue-Green Deployment

### Complete Blue-Green Workflow

```bash
#!/bin/bash
# deploy.sh - Production blue-green deployment script

set -e

VERSION="v1.2.4"
DEPLOY_WAIT_TIME="10m"

echo "=== Nova Streaming Production Deployment ==="
echo "Version: $VERSION"
echo "Timestamp: $(date)"

# Phase 1: Pre-flight checks
echo -e "\n[1/4] Running pre-flight checks..."
kubectl get nodes
kubectl get pods -n production

# Create backup
echo -e "\n[2/4] Creating database backup..."
SNAPSHOT_ID="nova-prod-pre-deploy-$(date +%Y%m%d-%H%M%S)"
aws rds create-db-snapshot \
  --db-instance-identifier nova-prod \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --region us-east-1

# Phase 2: Deploy green
echo -e "\n[3/4] Deploying green version..."
helm install nova-streaming-green k8s/nova-streaming-$VERSION \
  --namespace production-green \
  --values k8s/values-prod.yaml \
  --set image.tag=$VERSION \
  --wait \
  --timeout $DEPLOY_WAIT_TIME

# Wait for health
sleep 30
kubectl get pods -n production-green

# Smoke tests
echo -e "\n[4/4] Running smoke tests..."
GREEN_POD=$(kubectl get pods -n production-green \
  -l app=user-service-green \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $GREEN_POD -n production-green -- \
  curl http://localhost:8081/health

# Phase 3: Switch traffic
echo -e "\n[SWITCH] Switching traffic to green..."
kubectl patch ingress api-ingress -n production \
  --type json \
  -p '[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "user-service-green"}]'

# Monitor
echo -e "\n[MONITOR] Monitoring for 10 minutes..."
for i in {1..10}; do
  echo "[$i/10] Checking health..."
  curl -s https://api.nova-social.io/health | jq .
  sleep 60
done

# Phase 4: Cleanup
echo -e "\n[CLEANUP] Scaling down blue deployment..."
kubectl scale deployment user-service-blue -n production --replicas=0

echo -e "\n✓ Deployment complete!"
echo "Version: $VERSION"
echo "Snapshot ID: $SNAPSHOT_ID"
echo "Timestamp: $(date)"
```

**Run deployment:**

```bash
bash deploy.sh 2>&1 | tee deployment-$(date +%Y%m%d-%H%M%S).log
```

---

## Monitoring and Validation

### Real-Time Monitoring Dashboard

**Metrics to watch during deployment:**

1. **API Response Times**
   ```
   Query: histogram_quantile(0.95, nova_http_request_duration_seconds)
   Threshold: < 200ms
   ```

2. **Error Rate**
   ```
   Query: rate(nova_http_errors_total[5m])
   Threshold: < 0.1%
   ```

3. **WebSocket Connections**
   ```
   Query: nova_streaming_websocket_connections
   Threshold: Stable (no sudden drops)
   ```

4. **Database Query Latency**
   ```
   Query: histogram_quantile(0.95, pg_query_duration_seconds)
   Threshold: < 100ms
   ```

### Health Checks

```bash
# Every 30 seconds during deployment
watch -n 30 'bash -c "
  echo \"=== API Health ===\"
  curl -s https://api.nova-social.io/health | jq .

  echo -e \"\n=== Metrics ===\"
  curl -s https://api.nova-social.io/metrics | grep nova_streaming_active_streams | head -3

  echo -e \"\n=== Pod Status ===\"
  kubectl get pods -n production-green | grep user-service-green
"'
```

---

## Rollback Procedures

### Immediate Rollback (< 5 minutes)

If critical issues detected within 10 minutes of deployment:

#### Option 1: Switch Back to Blue (Fastest)

```bash
# Immediately switch traffic back to blue
kubectl patch ingress api-ingress -n production \
  --type json \
  -p '[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "user-service-blue"}]'

# Scale up blue
kubectl scale deployment user-service-blue -n production --replicas=3

# Verify blue is handling traffic
curl -s https://api.nova-social.io/health | jq .

# Timeline: 1-2 minutes
```

#### Option 2: Database Rollback (Moderate)

```bash
# If database schema changes caused issues
# Restore from snapshot created before deployment

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier nova-prod-recovered \
  --db-snapshot-identifier nova-prod-pre-deploy-v1.2.4 \
  --region us-east-1

# Wait for recovery (5-15 minutes)
aws rds describe-db-instances \
  --db-instance-identifier nova-prod-recovered \
  --query 'DBInstances[0].DBInstanceStatus' \
  --region us-east-1 --output text

# Once available, update connection strings
# kubectl set env deployment/user-service-blue \
#   DATABASE_URL=postgresql://...nova-prod-recovered...

# Timeline: 5-15 minutes
```

#### Option 3: Full Service Rollback (Complete)

```bash
# Uninstall green deployment
helm uninstall nova-streaming-green --namespace production-green

# Scale blue to full capacity
kubectl scale deployment user-service-blue -n production --replicas=5

# Update ingress to blue
kubectl patch ingress api-ingress -n production \
  --type json \
  -p '[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "user-service-blue"}]'

# Timeline: < 2 minutes
```

### Staged Rollback (15-30 minutes)

If issues not critical but deployment unsuccessful:

```bash
# Step 1: Reduce green traffic percentage (if load balancer supports weighted routing)
kubectl set env deployment/user-service-green -n production-green \
  TRAFFIC_WEIGHT=25

# Step 2: Monitor error rate decline
watch -n 5 'curl -s http://prometheus:9090/api/v1/query?query=rate(nova_http_errors_total[5m])'

# Step 3: If error rate recovers, investigate green issue
kubectl logs deployment/user-service-green -n production-green | tail -100

# Step 4: If unfixable, return to blue
kubectl patch ingress api-ingress -n production \
  --type json \
  -p '[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "user-service-blue"}]'
```

### Post-Rollback Analysis

```bash
# Collect rollback data
kubectl logs deployment/user-service-green -n production-green > green-logs.txt
kubectl logs deployment/user-service-blue -n production > blue-logs.txt

# Analyze Prometheus metrics before/after
curl -s 'http://prometheus:9090/api/v1/query_range?query=rate(nova_http_errors_total[5m])&start=1697900000&end=1697903600&step=60'

# Check application error logs
grep ERROR green-logs.txt | head -20

# Create incident report
cat > rollback-incident.md << EOF
# Deployment Rollback Incident Report

**Date**: $(date)
**Version**: v1.2.4
**Duration**: X minutes
**Root Cause**: [To be determined]
**Timeline**: [Events]
**Resolution**: [Actions taken]
**Recommendations**: [Future improvements]
EOF
```

---

## Post-Deployment Tasks

### Immediate (First 15 minutes)

- [ ] **Verify all services healthy**
  ```bash
  kubectl get all -n production
  kubectl get pods --all-namespaces | grep -v Running | grep -v Completed
  ```

- [ ] **Check error logs**
  ```bash
  kubectl logs deployment/user-service-green -n production-green | grep -i error | tail -10
  ```

- [ ] **Notify team**
  - Green deployment successful
  - Traffic switched
  - All systems operational
  - No user-reported issues

### Short-term (Next 1 hour)

- [ ] **Monitor key metrics**
  ```bash
  # Set up monitoring dashboard
  # Watch: error rates, latency, connections, database load
  ```

- [ ] **User communication**
  - Update status page: "Deployment complete"
  - Notify stakeholders
  - Open ticket for feedback

- [ ] **Documentation update**
  - Update deployment log
  - Record actual timeline
  - Note any deviations from plan

### Follow-up (Next 24 hours)

- [ ] **Performance analysis**
  ```bash
  # Compare metrics before/after deployment
  # Check for any performance regressions
  # Verify all features working correctly
  ```

- [ ] **Security validation**
  - Run security tests
  - Verify SSL/TLS certificates valid
  - Check authentication working correctly

- [ ] **Cost analysis**
  - Verify resource usage as expected
  - Check for any unexpected cloud charges
  - Optimize if needed

- [ ] **Post-deployment review**
  - Schedule with team
  - Review what went well
  - Identify improvements
  - Update procedures for next time

### Clean-up (Within 1 week)

- [ ] **Archive deployment artifacts**
  ```bash
  mkdir -p /archive/deployments/v1.2.4
  cp deployment-*.log /archive/deployments/v1.2.4/
  cp user-service-blue-backup.yaml /archive/deployments/v1.2.4/
  ```

- [ ] **Delete old backups**
  ```bash
  # Keep last 7 production snapshots
  aws rds describe-db-snapshots \
    --query 'DBSnapshots[?Type==`manual`] | sort_by(@, &SnapshotCreateTime) | [:-7].[DBSnapshotIdentifier]' \
    --output text | xargs -I {} aws rds delete-db-snapshot --db-snapshot-identifier {}
  ```

- [ ] **Update runbooks**
  - Record any changes needed
  - Update next deployment plan
  - Share lessons learned

---

## Emergency Procedures

### Production Issues Detected

**Escalation procedure:**

```
Issue Severity Assessment
    │
    ├─ CRITICAL (API down, data loss)
    │   └─ → Immediate rollback (< 5 min)
    │
    ├─ HIGH (Errors > 5%, WebSocket failures)
    │   └─ → Investigate (5 min), then rollback if needed
    │
    ├─ MEDIUM (Errors 1-5%, performance degradation)
    │   └─ → Investigate (30 min), continue monitoring
    │
    └─ LOW (Error rate < 1%, warnings in logs)
        └─ → Monitor, fix in next release
```

### War Room Setup

```bash
# On-call engineer immediately:
1. Open war room: Teams/Slack #nova-incident
2. Declare incident severity
3. Assign roles:
   - Incident Commander (overall coordination)
   - Lead Engineer (technical decisions)
   - Communications (status updates)

# Collect data:
kubectl logs deployment/user-service-green -n production-green > incident.log
kubectl describe pod <pod-name> -n production-green >> incident.log
kubectl top pods -n production-green >> incident.log

# Timeline template:
14:30 UTC - Issue detected (error rate spike)
14:31 UTC - War room opened
14:32 UTC - Root cause: database connection leak
14:33 UTC - Decision: rollback
14:35 UTC - Rollback started
14:37 UTC - Blue back in production
14:40 UTC - Error rate normal
```

---

## References

- Staging Deployment Checklist: `docs/staging-deployment-checklist.md`
- Troubleshooting Runbook: `docs/troubleshooting-runbook.md`
- Incident Response Plan: `docs/incident-response.md`
- Infrastructure Code: `k8s/nova-streaming-*.yaml`
- Helm Charts: `k8s/helm/nova-streaming/`

---

## Support

For deployment issues or questions:

1. **During deployment**: Contact on-call engineer
2. **After deployment**: Check troubleshooting guide
3. **For improvements**: File ticket in issue tracker
4. **For escalation**: Notify infrastructure team lead
