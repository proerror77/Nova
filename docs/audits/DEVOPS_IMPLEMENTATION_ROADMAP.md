# DevOps Implementation Roadmap - Nova Social

**Created**: November 26, 2025
**Target Completion**: Q1 2026
**Current Level**: 3.2/5 → Target: 4.5/5

---

## Phase 1: Foundation (Weeks 1-2) - Critical Issues

### 1.1 Enforce unwrap() Linting

**Owner**: Backend Lead
**Time**: 3-5 days
**Risk**: Medium

**Steps**:

1. **Audit Current State**
   ```bash
   cd backend
   cargo clippy --all-targets -- -D clippy::unwrap_used 2>&1 | tee unwrap-violations.txt
   grep "unwrap" unwrap-violations.txt | wc -l  # Should show ~803
   ```

2. **Create Remediation Plan**
   ```bash
   # Categorize by file and service
   grep -r "\.unwrap()" backend --include="*.rs" | grep -v "/test" | wc -l
   # Output: Count of production unwrap() calls

   # Group by service
   for service in backend/*/; do
     echo "$(basename $service): $(grep -r "\.unwrap()" "$service" 2>/dev/null | grep -v "/test" | wc -l)"
   done | sort -t: -k2 -rn
   ```

3. **Implement Fixes (Priority Order)**

   **Tier 1** (Easy, ~2 hours):
   ```rust
   // BEFORE
   let config = load_config().unwrap();

   // AFTER
   let config = load_config()
       .context("Failed to load configuration")?;
   ```

   **Tier 2** (Medium, ~4 hours):
   ```rust
   // BEFORE
   let user = db.get_user(id).await.unwrap();

   // AFTER
   let user = db.get_user(id).await
       .context("User not found")?;
   ```

   **Tier 3** (Complex, ~8 hours):
   ```rust
   // BEFORE - custom error handling needed
   let result = risky_operation().unwrap();

   // AFTER
   let result = risky_operation()
       .map_err(|e| anyhow!("Operation failed: {}", e))?;
   ```

4. **Add CI Enforcement**
   ```yaml
   # .github/workflows/code-quality.yml - UPDATE
   - name: Enforce no unwrap() calls
     run: |
       cd backend
       UNWRAPS=$(cargo clippy --all-targets -- -D clippy::unwrap_used 2>&1 | grep "unwrap" | wc -l)
       if [ "$UNWRAPS" -gt 0 ]; then
         echo "❌ Found unwrap() violations: $UNWRAPS"
         cargo clippy --all-targets -- -D clippy::unwrap_used
         exit 1
       fi
       echo "✅ No unwrap() violations found"
   ```

5. **Gradual Enforcement Timeline**
   - Week 1: Report current violations, create tracking spreadsheet
   - Week 2: Fix top 100 (Tier 1)
   - Week 3: Fix next 200 (Tier 2)
   - Week 4: Fix remaining 500 (Tier 3, spread across team)
   - Week 5: Enable hard blocking in CI

**Estimated Team Distribution**:
- 1 senior backend engineer: 20 hours (guidance + complex fixes)
- 3-4 junior engineers: 15 hours each (straightforward fixes)

### 1.2 Implement ArgoCD for GitOps

**Owner**: DevOps Lead
**Time**: 3-5 days
**Risk**: Low (staging only initially)

**Steps**:

1. **Install ArgoCD**
   ```bash
   # Create namespace
   kubectl create namespace argocd

   # Install ArgoCD
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

   # Wait for rollout
   kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

   # Get initial password
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

   # Port-forward
   kubectl port-forward -n argocd svc/argocd-server 8080:443
   # Access: https://localhost:8080
   # Username: admin
   # Password: <from above>
   ```

2. **Create ArgoCD Application for Staging**
   ```yaml
   # k8s/argocd/application-staging.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: nova-staging
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: https://github.com/proerror/nova
       targetRevision: main
       path: k8s/overlays/staging
     destination:
       server: https://kubernetes.default.svc
       namespace: nova-staging
     syncPolicy:
       automated:
         prune: true      # Remove resources not in git
         selfHeal: true   # Revert manual kubectl changes
       syncOptions:
       - CreateNamespace=true
       retry:
         limit: 5
         backoff:
           duration: 5s
           factor: 2
           maxDuration: 5m
   ```

3. **Update CI/CD Pipeline**
   ```yaml
   # .github/workflows/ci-cd-pipeline.yml - REPLACE deploy-staging job

   deploy-staging-gitops:
     timeout-minutes: 15
     name: Deploy to EKS Staging (GitOps)
     runs-on: ubuntu-latest
     needs: build-and-push
     if: github.ref == 'refs/heads/feature/phase1-grpc-migration' || github.ref == 'refs/heads/main'
     steps:
       - name: Checkout code
         uses: actions/checkout@v4

       - name: Update image tags in Kustomization
         run: |
           cd k8s/overlays/staging
           # Update all image tags to new commit SHA
           for service in analytics-service content-service feed-service graph-service graphql-gateway identity-service media-service notification-service ranking-service realtime-chat-service search-service social-service trust-safety-service; do
             sed -i "s|newTag:.*|newTag: ${{ github.sha }}|g" kustomization.yaml
           done

       - name: Commit and push image updates
         run: |
           git config user.email "github-actions@nova.io"
           git config user.name "GitHub Actions"
           git add k8s/overlays/staging/kustomization.yaml
           git commit -m "chore(deploy): update staging image tags to ${{ github.sha }}" || true
           git push origin HEAD:refs/heads/feature/phase1-grpc-migration

       - name: Verify ArgoCD sync
         env:
           ARGOCD_TOKEN: ${{ secrets.ARGOCD_TOKEN }}
         run: |
           # Wait for ArgoCD to detect and sync changes
           for i in {1..30}; do
             SYNC_STATUS=$(argocd app get nova-staging --refresh --refresh-type=normal 2>/dev/null | grep "Sync Status" || echo "Unknown")
             echo "Sync Status: $SYNC_STATUS"
             if [[ "$SYNC_STATUS" == *"Synced"* ]]; then
               echo "✅ Staging deployment synced successfully"
               exit 0
             fi
             sleep 5
           done
           echo "❌ Deployment sync timeout"
           exit 1
   ```

4. **Create RBAC for GitHub Actions**
   ```bash
   # Create ArgoCD admin account for CI/CD
   kubectl -n argocd create serviceaccount github-actions
   kubectl -n argocd create clusterrolebinding github-actions --clusterrole=admin --serviceaccount=argocd:github-actions

   # Get token
   TOKEN=$(kubectl -n argocd create token github-actions)
   echo "ARGOCD_TOKEN=$TOKEN" >> $GITHUB_ENV
   ```

5. **Verification Checklist**
   - [ ] ArgoCD pod running
   - [ ] GitHub repo connected
   - [ ] Application syncing automatically
   - [ ] Manual kubectl changes reverted by selfHeal
   - [ ] Git commit triggers ArgoCD sync
   - [ ] Old ci-cd-pipeline.yml deploy job disabled

### 1.3 Add Prometheus Alert Rules

**Owner**: Observability Engineer
**Time**: 2-3 days
**Risk**: Low

**Steps**:

1. **Create Alert Rules ConfigMap**
   ```yaml
   # k8s/infrastructure/prometheus-rules.yaml
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: nova-alerts
     namespace: monitoring
   spec:
     groups:
     - name: nova.rules
       interval: 30s
       rules:
       # HTTP Errors
       - alert: HighErrorRate
         expr: |
           rate(http_requests_total{status=~"5.."}[5m]) > 0.05
         for: 5m
         annotations:
           summary: "Service {{ $labels.service }} error rate > 5%"
           description: "Error rate for {{ $labels.service }} has exceeded 5%"

       # Latency
       - alert: HighLatencyP95
         expr: |
           histogram_quantile(0.95,
             rate(http_request_duration_seconds_bucket[5m])
           ) > 1
         for: 5m
         annotations:
           summary: "P95 latency > 1s for {{ $labels.service }}"

       # Pod Crashes
       - alert: PodCrashLooping
         expr: rate(kube_pod_container_status_restarts_total[15m]) > 0.1
         for: 5m
         annotations:
           summary: "Pod {{ $labels.pod }} is crash looping"

       # Disk Usage
       - alert: HighDiskUsage
         expr: (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) > 0.85
         for: 10m
         annotations:
           summary: "Disk usage for PVC {{ $labels.persistentvolumeclaim }} > 85%"

       # Database Connection Pool
       - alert: DatabaseConnectionPoolNearMax
         expr: |
           pg_stat_activity_count / max_connections > 0.8
         for: 5m
         annotations:
           summary: "Database {{ $labels.instance }} connection pool at 80%"

       # Memory Pressure
       - alert: HighMemoryUsage
         expr: |
           (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.85
         for: 5m
         annotations:
           summary: "Container {{ $labels.container }} memory > 85%"
   ```

2. **Apply Rules**
   ```bash
   kubectl apply -f k8s/infrastructure/prometheus-rules.yaml
   kubectl rollout restart deployment prometheus-operator -n monitoring
   ```

3. **Configure AlertManager**
   ```yaml
   # k8s/infrastructure/alertmanager-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: alertmanager
     namespace: monitoring
   data:
     alertmanager.yml: |
       global:
         resolve_timeout: 5m
       route:
         receiver: 'default'
         group_by: ['alertname', 'cluster', 'service']
         group_wait: 30s
         group_interval: 5m
         repeat_interval: 4h
         routes:
         - match:
             severity: critical
           receiver: 'pagerduty'
           continue: true
         - match:
             severity: warning
           receiver: 'slack'
       receivers:
       - name: 'default'
         slack_configs:
         - api_url: '${SLACK_WEBHOOK}'
           channel: '#alerts-dev'
       - name: 'pagerduty'
         pagerduty_configs:
         - service_key: '${PAGERDUTY_KEY}'
       inhibit_rules:
       - source_match:
           severity: 'critical'
         target_match:
           severity: 'warning'
   ```

4. **Test Alert Firing**
   ```bash
   # Trigger a test alert
   kubectl exec -n monitoring prometheus-0 -- promtool query instant \
     'http_requests_total{status="500"}' \
     --start="5m"

   # Check AlertManager
   kubectl logs -n monitoring alertmanager-0 -f
   ```

---

## Phase 2: Deployment Strategy (Weeks 3-4)

### 2.1 Implement Blue-Green Deployment

**Owner**: DevOps Lead
**Time**: 3-4 days
**Risk**: Medium

**Steps**:

1. **Create Blue-Green Deployment Manifests**
   ```yaml
   # k8s/overlays/staging/deployment-blue-green.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: graphql-gateway-blue
     labels:
       app: graphql-gateway
       version: blue
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: graphql-gateway
         version: blue
     template:
       metadata:
         labels:
           app: graphql-gateway
           version: blue
       spec:
         containers:
         - name: graphql-gateway
           image: {{ BLUE_IMAGE }}
           ports:
           - containerPort: 8080
           livenessProbe:
             httpGet:
               path: /health
               port: 8080
             initialDelaySeconds: 30
             periodSeconds: 10
           readinessProbe:
             httpGet:
               path: /health
               port: 8080
             initialDelaySeconds: 5
             periodSeconds: 5
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: graphql-gateway-green
     labels:
       app: graphql-gateway
       version: green
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: graphql-gateway
         version: green
     template:
       metadata:
         labels:
           app: graphql-gateway
           version: green
       spec:
         containers:
         - name: graphql-gateway
           image: {{ GREEN_IMAGE }}
           ports:
           - containerPort: 8080
           livenessProbe:
             httpGet:
               path: /health
               port: 8080
             initialDelaySeconds: 30
             periodSeconds: 10
           readinessProbe:
             httpGet:
               path: /health
               port: 8080
             initialDelaySeconds: 5
             periodSeconds: 5
   ---
   # Service points to BLUE or GREEN via selector
   apiVersion: v1
   kind: Service
   metadata:
     name: graphql-gateway
   spec:
     selector:
       app: graphql-gateway
       version: blue  # Change to 'green' to switch traffic
     ports:
     - protocol: TCP
       port: 8080
       targetPort: 8080
   ```

2. **Create Switching Script**
   ```bash
   #!/bin/bash
   # scripts/switch-traffic.sh

   SERVICE=$1
   TARGET_VERSION=${2:-green}
   NAMESPACE=${3:-nova-staging}

   if [ -z "$SERVICE" ]; then
     echo "Usage: $0 <service> [blue|green] [namespace]"
     exit 1
   fi

   echo "Switching $SERVICE to $TARGET_VERSION"

   kubectl patch svc $SERVICE -n $NAMESPACE -p \
     '{"spec":{"selector":{"version":"'$TARGET_VERSION'"}}}'

   echo "Traffic switched. Current active version:"
   kubectl get svc $SERVICE -n $NAMESPACE -o jsonpath='{.spec.selector.version}'
   ```

3. **Smoke Test Script**
   ```bash
   #!/bin/bash
   # scripts/smoke-test-blue-green.sh

   SERVICE=$1
   NAMESPACE=${2:-nova-staging}
   HEALTH_URL="http://$SERVICE.$NAMESPACE.svc.cluster.local:8080/health"

   echo "Testing $SERVICE health..."

   for i in {1..30}; do
     RESPONSE=$(kubectl run -i --rm test-$$ \
       --image=curlimages/curl:latest \
       --restart=Never \
       -- curl -s "$HEALTH_URL" || echo "Failed")

     if echo "$RESPONSE" | grep -q "ok"; then
       echo "✅ Health check passed"
       exit 0
     fi

     echo "Attempt $i/30: Health check failed, retrying..."
     sleep 5
   done

   echo "❌ Health check failed after 30 attempts"
   exit 1
   ```

4. **GitHub Actions Workflow**
   ```yaml
   # .github/workflows/blue-green-deploy.yml
   name: Blue-Green Deployment

   on:
     workflow_dispatch:
       inputs:
         service:
           description: 'Service to deploy'
           required: true
           type: choice
           options:
           - graphql-gateway
           - identity-service
           - feed-service
         switch_traffic:
           description: 'Switch traffic after deploy?'
           type: boolean
           default: false

   jobs:
     deploy:
       runs-on: ubuntu-latest
       steps:
       - uses: actions/checkout@v4

       - name: Get current active version
         id: current
         run: |
           ACTIVE=$(kubectl get svc ${{ inputs.service }} -n nova-staging \
             -o jsonpath='{.spec.selector.version}')
           INACTIVE=$([ "$ACTIVE" = "blue" ] && echo "green" || echo "blue")
           echo "current=$ACTIVE" >> $GITHUB_OUTPUT
           echo "target=$INACTIVE" >> $GITHUB_OUTPUT

       - name: Deploy to inactive version
         run: |
           kubectl set image deployment/${{ inputs.service }}-${{ steps.current.outputs.target }} \
             -n nova-staging \
             ${{ inputs.service }}=${{ env.ECR_REGISTRY }}/nova/${{ inputs.service }}:${{ github.sha }}

       - name: Wait for rollout
         run: |
           kubectl rollout status deployment/${{ inputs.service }}-${{ steps.current.outputs.target }} \
             -n nova-staging \
             --timeout=5m

       - name: Smoke test inactive version
         run: |
           bash scripts/smoke-test-blue-green.sh ${{ inputs.service }} nova-staging

       - name: Switch traffic (manual approval)
         if: ${{ inputs.switch_traffic }}
         run: |
           bash scripts/switch-traffic.sh ${{ inputs.service }} ${{ steps.current.outputs.target }} nova-staging
           echo "✅ Traffic switched to ${{ steps.current.outputs.target }}"
   ```

### 2.2 Define SLO Framework

**Owner**: Observability Engineer
**Time**: 2-3 days
**Risk**: Low

**Steps**:

1. **Create SLO Definition**
   ```yaml
   # k8s/infrastructure/slo-framework.yaml
   apiVersion: slo.unstable.kyverno.io/v1alpha1
   kind: ServiceLevelObjective
   metadata:
     name: graphql-gateway-slo
     namespace: monitoring
   spec:
     service: graphql-gateway
     objectives:
     - name: availability
       target: 0.995  # 99.5% uptime
       description: "Service availability target"
       indicator:
         type: "latency"
         thresholds:
         - value: 0.99
           threshold: 500ms  # 99% of requests under 500ms
         - value: 0.95
           threshold: 1000ms # 95% of requests under 1s

     - name: error_budget
       target: 0.001  # 0.1% error rate allowed
       description: "Error budget for month"
       indicator:
         type: "error_rate"
         query: |
           rate(http_requests_total{status=~"5.."}[5m])

     # Error budget tracking
     errorBudget:
       period: monthly
       exhaustionAlert: 0.5  # Alert at 50% budget consumed

     # Review schedule
     review:
       interval: weekly
       slackChannel: "#reliability"
   ```

2. **Create SLO Dashboard**
   ```json
   {
     "dashboard": {
       "title": "Nova SLO Dashboard",
       "panels": [
         {
           "title": "Monthly Error Budget Remaining",
           "targets": [
             {
               "expr": "100 * (1 - rate(http_requests_total{status=~'5..'}[30d]) / 0.001)"
             }
           ]
         },
         {
           "title": "Service Availability (30d)",
           "targets": [
             {
               "expr": "100 * (1 - rate(http_requests_total{status=~'5..'}[30d]))"
             }
           ]
         }
       ]
     }
   }
   ```

---

## Phase 3: Observability (Weeks 5-6)

### 3.1 Log Aggregation with Loki

**Owner**: Observability Engineer
**Time**: 2-3 days

**Steps**:

```bash
# Install Loki stack
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set loki.enabled=true \
  --set promtail.enabled=true \
  --set grafana.enabled=false \
  --set prometheus.enabled=false

# Verify
kubectl rollout status daemonset/loki-promtail -n monitoring
```

### 3.2 Distributed Tracing

**Owner**: Observability Engineer
**Time**: 2-3 days

```bash
# Add OpenTelemetry collector
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install opentelemetry-collector open-telemetry/opentelemetry-collector \
  --namespace monitoring \
  -f k8s/infrastructure/otel-collector-values.yaml
```

---

## Phase 4: Testing & Quality (Weeks 7-8)

### 4.1 Performance Benchmarking

**Owner**: Platform Engineer
**Time**: 3-4 days

**Steps**:

1. **Create Benchmark Job**
   ```bash
   # .github/workflows/performance-baseline.yml
   # Runs on main branch and stores baseline
   # PR comparisons fail if regression > 10%
   ```

2. **Store Historical Data**
   ```bash
   # k8s/infrastructure/influxdb/deployment.yaml
   # Store metrics in time-series DB for trending
   ```

---

## Team Assignments

### Week 1-2
- **Backend Lead**: unwrap() enforcement (2-3 engineers)
- **DevOps Lead**: ArgoCD setup (1 engineer)
- **Observability Engineer**: Alert rules (1 engineer)

### Week 3-4
- **DevOps Lead**: Blue-green deployment (1-2 engineers)
- **Observability Engineer**: SLO framework (1 engineer)

### Week 5-6
- **Observability Engineer**: Loki + tracing (1 engineer)
- **Backend Engineers**: Service instrumentation (2-3 engineers)

### Week 7-8
- **Platform Engineer**: Performance benchmarking (1 engineer)
- **QA Engineers**: Test framework updates (1-2 engineers)

---

## Success Criteria

### Phase 1 (End of Week 2)
- [ ] All unwrap() violations documented
- [ ] ArgoCD managing staging deployments
- [ ] Alert rules firing correctly
- [ ] No manual kubectl calls in pipeline

### Phase 2 (End of Week 4)
- [ ] Blue-green deployment tested
- [ ] Traffic switching automated
- [ ] SLO targets defined
- [ ] Error budget calculation working

### Phase 3 (End of Week 6)
- [ ] All logs aggregated in Loki
- [ ] Distributed tracing active
- [ ] Service instrumentation complete

### Phase 4 (End of Week 8)
- [ ] Performance baselines established
- [ ] Regressions detected automatically
- [ ] Pre-commit hooks enforced
- [ ] DevOps maturity: 4.2/5

---

## Risk Mitigation

### Rollback Plan
- Keep old ci-cd-pipeline.yml workflow as backup
- Manual kubectl access always available
- Staging environment isolated from production
- Canary deployments start with 1 pod

### Monitoring
- All changes logged and auditable
- Alerting on deployment failures
- Slack notifications for all deployments
- Daily reliability reviews

---

## Budget & Timeline

**Total Effort**: ~400 engineer-hours
**Timeline**: 8 weeks (Nov 26 - Jan 20)
**Team Size**: 5-6 engineers

| Phase | Effort | Timeline | Cost |
|-------|--------|----------|------|
| Foundation | 100 hrs | Weeks 1-2 | $15K |
| Deployment | 80 hrs | Weeks 3-4 | $12K |
| Observability | 100 hrs | Weeks 5-6 | $15K |
| Quality | 80 hrs | Weeks 7-8 | $12K |
| **Total** | **360 hrs** | **8 weeks** | **$54K** |

**Expected ROI**:
- 40% reduction in MTTR (mean time to recovery)
- 90% increase in deployment frequency
- 25% fewer incidents
- Estimated annual savings: $200K (reduced incidents + faster recovery)

---

## Appendix: Command Reference

### Quick Start Commands

```bash
# Phase 1 verification
cd backend && cargo clippy --all-targets -- -D clippy::unwrap_used

# ArgoCD access
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Check alert rules
kubectl get prometheusrule -n monitoring

# List active alerts
kubectl exec -n monitoring prometheus-0 -- promtool query instant 'ALERTS{severity="critical"}'

# Switch traffic (manual)
bash scripts/switch-traffic.sh graphql-gateway green nova-staging

# Check pod health
kubectl get pods -n nova-staging -l app=graphql-gateway

# View logs
kubectl logs -n nova-staging -l app=graphql-gateway -f

# Check deployment status
kubectl rollout status deployment/graphql-gateway-blue -n nova-staging
```

---

**Document Version**: 1.0
**Last Updated**: November 26, 2025
**Next Review**: January 15, 2026
