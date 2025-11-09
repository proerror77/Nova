# Chaos Engineering Implementation Guide

**Status**: ✅ Ready for Implementation
**Technology**: Chaos Mesh v2.6.3
**Date**: 2025-11-09

---

## Overview

This document describes the implementation of chaos engineering across the Nova backend microservices using Chaos Mesh. Chaos engineering proactively tests system resilience by injecting controlled failures.

### Benefits

- **Proactive Resilience**: Discover weaknesses before they cause outages
- **Confidence in Changes**: Validate that new deployments are resilient
- **Better Incident Response**: Practice failure scenarios in controlled environment
- **Improved SLAs**: Ensure system meets uptime guarantees
- **Cost Reduction**: Prevent expensive production incidents

### Integration with Distributed Tracing

Chaos Mesh works seamlessly with OpenTelemetry/Jaeger distributed tracing:

1. **Before chaos**: Establish baseline trace patterns
2. **During chaos**: Observe how traces change under failure
3. **After chaos**: Verify system recovery and trace continuity

Use Jaeger UI to analyze:
- Which services failed during chaos
- How long recovery took
- Whether circuit breakers activated
- If timeouts were respected

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Chaos Mesh Dashboard (Web UI)                          │
│  - Schedule experiments                                 │
│  - Monitor experiment status                            │
│  - View experiment history                              │
│  - Analyze failure patterns                             │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Chaos Controller Manager                               │
│  - Validates experiment CRDs                            │
│  - Schedules chaos experiments                          │
│  - Coordinates with daemons                             │
│  - Records experiment results                           │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Chaos Daemon (DaemonSet - runs on each node)          │
│  - Injects network chaos (latency, loss, partition)    │
│  - Kills/restarts pods                                  │
│  - Stresses CPU/memory                                  │
│  - Injects I/O errors                                   │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Target Services (auth, user, messaging, etc.)         │
│  - Experiences injected failures                        │
│  - Demonstrates resilience patterns                     │
│  - Generates traces showing failure behavior            │
└─────────────────────────────────────────────────────────┘
```

---

## Deployment

### Prerequisites

1. **Kubernetes cluster** (v1.20+)
2. **kubectl** configured
3. **Distributed tracing** deployed (OpenTelemetry + Jaeger)
4. **Prometheus** (optional, for metrics)

### 1. Deploy Chaos Mesh Operator

#### Development/Staging
```bash
kubectl apply -k k8s/overlays/staging/chaos-mesh/
```

This deploys:
- Chaos Mesh controller manager (1 replica)
- Chaos Daemon (DaemonSet on all nodes)
- Chaos Dashboard (Web UI)
- All experiment CRDs
- Scheduled chaos experiments (frequent)

#### Production
```bash
kubectl apply -k k8s/overlays/production/chaos-mesh/
```

This deploys:
- Chaos Mesh controller manager (2 replicas for HA)
- Chaos Daemon (DaemonSet with lower resource limits)
- Chaos Dashboard (2 replicas for HA)
- Only safe, approved experiments
- Scheduled chaos (infrequent, during maintenance windows)

### 2. Verify Deployment

```bash
# Check Chaos Mesh pods
kubectl get pods -n chaos-mesh

# Expected output:
# NAME                                       READY   STATUS
# chaos-controller-manager-xxx              1/1     Running
# chaos-daemon-xxx                          1/1     Running (on each node)
# chaos-dashboard-xxx                       1/1     Running

# Check services
kubectl get svc -n chaos-mesh

# Access dashboard
kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333
# Open http://localhost:2333
```

### 3. Create Basic Auth for Dashboard (Production)

```bash
# Create htpasswd file
htpasswd -c auth chaos-admin

# Create secret
kubectl create secret generic chaos-dashboard-auth \
  --from-file=auth -n chaos-mesh

# Update ingress to use auth (already configured in service.yaml)
```

---

## Chaos Experiment Types

### 1. Network Chaos

Simulates network issues: latency, packet loss, bandwidth limits, partitions.

#### Network Latency
```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-delay-test
  namespace: default
spec:
  action: delay
  mode: one  # Affects one random pod
  selector:
    namespaces:
      - default
    labelSelectors:
      app: auth-service
  delay:
    latency: "100ms"    # Add 100ms latency
    jitter: "10ms"      # ±10ms variation
    correlation: "50"   # 50% correlation between packets
  duration: "30s"
```

**Use Cases**:
- Test timeout handling
- Validate retry logic
- Test circuit breaker activation

#### Network Partition
```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: partition-test
spec:
  action: partition
  mode: all
  selector:
    namespaces:
      - default
    labelSelectors:
      app: messaging-service
  direction: to
  target:
    mode: all
    selector:
      labelSelectors:
        app: notification-service
  duration: "1m"
```

**Use Cases**:
- Test service mesh resilience
- Validate fallback mechanisms
- Test split-brain scenarios

### 2. Pod Chaos

Simulates pod failures: kill, delete, failure.

#### Pod Kill
```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill-test
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - default
    labelSelectors:
      app: user-service
  gracePeriod: 0  # Force kill (no graceful shutdown)
  duration: "30s"
```

**Use Cases**:
- Test Kubernetes auto-recovery
- Validate StatefulSet/Deployment resilience
- Test rolling update behavior

### 3. Stress Chaos

Simulates resource exhaustion: CPU, memory, I/O.

#### CPU Stress
```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress-test
spec:
  mode: one
  selector:
    namespaces:
      - default
    labelSelectors:
      app: auth-service
  stressors:
    cpu:
      workers: 2
      load: 80  # 80% CPU load
  duration: "2m"
```

**Use Cases**:
- Test rate limiting
- Validate autoscaling (HPA)
- Test performance degradation

#### Memory Stress
```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: memory-stress-test
spec:
  mode: one
  selector:
    namespaces:
      - default
    labelSelectors:
      app: user-service
  stressors:
    memory:
      workers: 1
      size: "512Mi"
  duration: "1m"
```

**Use Cases**:
- Test OOM (Out of Memory) killer
- Validate memory leak detection
- Test memory limits

### 4. I/O Chaos

Simulates disk I/O issues: latency, errors.

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: IOChaos
metadata:
  name: io-delay-test
spec:
  action: latency
  mode: one
  selector:
    labelSelectors:
      app: content-service
  volumePath: /var/lib/postgresql/data
  path: "/var/lib/postgresql/data/**/*"
  delay: "100ms"
  percent: 50  # 50% of I/O operations
  duration: "1m"
```

**Use Cases**:
- Test database timeout handling
- Validate connection pool resilience
- Test disk failure recovery

---

## Chaos Workflows

Workflows orchestrate multiple chaos experiments in sequence or parallel, simulating complex failure scenarios.

### Example: Production Incident Simulation

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: Workflow
metadata:
  name: incident-simulation
spec:
  entry: network-delay-phase
  templates:
    # Phase 1: Network issues
    - name: network-delay-phase
      templateType: NetworkChaos
      deadline: 2m
      networkChaos:
        action: delay
        mode: all
        selector:
          labelSelectors:
            tier: backend
        delay:
          latency: "200ms"
        duration: "1m"

    # Phase 2: Pod failure
    - name: pod-failure-phase
      templateType: PodChaos
      deadline: 2m
      podChaos:
        action: pod-kill
        mode: one
        selector:
          labelSelectors:
            tier: backend

    # Phase 3: Resource stress
    - name: stress-phase
      templateType: StressChaos
      deadline: 3m
      stressChaos:
        mode: one
        stressors:
          cpu:
            workers: 2
            load: 70

  entrypoint:
    - network-delay-phase
    - pod-failure-phase
    - stress-phase
```

**This simulates**:
1. Upstream service slowing down (network delay)
2. Cascading pod failure
3. Resource exhaustion under load

**Use with distributed tracing** to observe:
- How latency propagates through services
- Which services fail first
- Whether circuit breakers activate
- How long recovery takes

---

## Scheduled Chaos

Automate chaos experiments to run on a schedule using cron syntax.

### Example: Daily Network Latency Test

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: Schedule
metadata:
  name: daily-network-test
spec:
  schedule: "0 2 * * *"  # 2 AM every day
  historyLimit: 10
  concurrencyPolicy: Forbid
  type: NetworkChaos
  networkChaos:
    action: delay
    mode: one
    selector:
      labelSelectors:
        app: auth-service
    delay:
      latency: "150ms"
    duration: "5m"
```

### Recommended Schedules

| Environment | Network Chaos | Pod Chaos | Stress Chaos |
|-------------|---------------|-----------|--------------|
| Development | Every 30min | Every 1h | Every 2h |
| Staging | Every 2h | Every 4h | Every 6h |
| Production | Weekly (Sun 3AM) | Monthly (1st Sun) | Weekly (Sun 5AM) |

---

## Best Practices

### 1. Start Small

✅ **Do**:
```yaml
# Start with single pod, short duration
mode: one
duration: "30s"
```

❌ **Don't**:
```yaml
# Don't start with all pods, long duration
mode: all
duration: "10m"
```

### 2. Label Targets Explicitly

✅ **Do**:
```yaml
selector:
  labelSelectors:
    app: auth-service
    chaos.mesh/safe: "true"  # Explicit opt-in
```

❌ **Don't**:
```yaml
selector:
  labelSelectors:
    tier: backend  # Too broad, affects all services
```

### 3. Use Distributed Tracing for Analysis

**Before experiment**:
```bash
# Baseline: Check normal trace patterns
kubectl port-forward -n observability svc/jaeger-query 16686:16686
# Open http://localhost:16686, search for "auth-service"
```

**During experiment**:
```bash
# Run chaos
kubectl apply -f k8s/base/chaos-mesh/experiments/network-chaos.yaml

# Observe traces in Jaeger UI
# Look for: timeout errors, circuit breaker activation, retry attempts
```

**After experiment**:
```bash
# Verify recovery
# Check that traces return to normal
# No orphaned spans
# All services healthy
```

### 4. Implement Circuit Breakers

**Before chaos**:
```rust
// Ensure circuit breakers are implemented
use tower::retry::RetryLayer;
use tower::timeout::TimeoutLayer;

ServiceBuilder::new()
    .layer(TimeoutLayer::new(Duration::from_secs(5)))
    .layer(RetryLayer::new(retry_policy))
    .service(my_service)
```

**Validate with chaos**:
- Network latency chaos should trigger timeouts
- Pod kill chaos should trigger circuit breaker open state
- Verify fallback mechanisms activate

### 5. Monitor Metrics During Chaos

```bash
# Prometheus queries to run during chaos
# Request error rate
rate(http_requests_total{status=~"5.."}[1m])

# Request latency (P99)
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[1m]))

# Circuit breaker state
circuit_breaker_state{service="auth-service"}
```

### 6. Production Safety

**Production checklist**:
- [ ] Chaos approved by SRE team
- [ ] Scheduled during maintenance window
- [ ] Affects only canary pods (labeled `chaos.mesh/canary: "true"`)
- [ ] Duration < 1 minute
- [ ] Concurrent experiments forbidden
- [ ] Rollback plan documented
- [ ] On-call engineer notified

**Production-safe experiment**:
```yaml
metadata:
  annotations:
    chaos.approved-by: "sre-team"
    chaos.approved-date: "2025-11-09"
spec:
  mode: one
  selector:
    labelSelectors:
      chaos.mesh/canary: "true"  # Only canary pods
  duration: "30s"  # Short duration
  gracePeriod: 30  # Allow graceful shutdown
  scheduler:
    cron: "0 3 * * 0"  # Sunday 3 AM only
```

---

## Troubleshooting

### Issue: Experiment Not Starting

**Check 1**: Verify selector matches pods
```bash
kubectl get pods -l app=auth-service
```

**Check 2**: Check controller logs
```bash
kubectl logs -n chaos-mesh deployment/chaos-controller-manager
```

**Check 3**: Verify RBAC permissions
```bash
kubectl auth can-i create podchaos.chaos-mesh.org --as=system:serviceaccount:chaos-mesh:chaos-controller-manager
```

### Issue: Experiment Not Stopping

**Immediate stop**:
```bash
# Delete experiment
kubectl delete networkchaos network-delay-test

# Force delete if stuck
kubectl delete networkchaos network-delay-test --force --grace-period=0
```

**Check daemon logs**:
```bash
kubectl logs -n chaos-mesh daemonset/chaos-daemon
```

### Issue: Target Service Not Affected

**Check 1**: Verify chaos daemon is running on target node
```bash
kubectl get pods -n chaos-mesh -o wide
# Ensure chaos-daemon is running on node where target pod is
```

**Check 2**: Check target pod logs
```bash
kubectl logs <target-pod>
# Look for chaos-related errors
```

**Check 3**: Verify container runtime
```bash
# Chaos daemon must match cluster runtime
# Edit daemon env: RUNTIME=containerd or RUNTIME=docker
kubectl edit daemonset -n chaos-mesh chaos-daemon
```

---

## Security Considerations

### 1. RBAC Restrictions

Limit chaos to specific namespaces:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: chaos-operator
  namespace: default  # Only default namespace
rules:
  - apiGroups: ["chaos-mesh.org"]
    resources: ["*"]
    verbs: ["create", "update", "delete"]
```

### 2. Namespace Filtering

```yaml
# In controller manager deployment
env:
  - name: ENABLE_FILTER_NAMESPACE
    value: "true"
  - name: ALLOWED_NAMESPACES
    value: "default,staging"  # Explicit allowlist
```

### 3. Security Mode

```yaml
# Enable security mode in production
env:
  - name: SECURITY_MODE
    value: "true"
```

Security mode prevents:
- Cluster-wide chaos (requires namespace)
- Privileged chaos experiments
- Accessing chaos-mesh namespace

### 4. Audit Logging

Enable audit logging for compliance:

```yaml
# In dashboard deployment
env:
  - name: ENABLE_AUDIT
    value: "true"
  - name: AUDIT_LOG_PATH
    value: "/var/log/chaos-mesh/audit.log"
```

---

## Monitoring & Alerts

### Key Metrics

Monitor Chaos Mesh health:

```yaml
# Prometheus ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: chaos-mesh
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: chaos-mesh
  endpoints:
    - port: metrics
      interval: 30s
```

**Metrics to track**:
- `chaos_mesh_experiments_total` - Total experiments run
- `chaos_mesh_experiments_failed_total` - Failed experiments
- `chaos_mesh_experiment_duration_seconds` - Experiment duration

### Recommended Alerts

```yaml
# Alert if chaos experiment fails
- alert: ChaosExperimentFailed
  expr: rate(chaos_mesh_experiments_failed_total[5m]) > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Chaos experiment failed"

# Alert if too many experiments running
- alert: TooManyChaosExperiments
  expr: chaos_mesh_experiments_running > 5
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Too many chaos experiments running concurrently"
```

---

## Integration with CI/CD

### Pre-Production Chaos Testing

Add chaos experiments to CI/CD pipeline:

```yaml
# .github/workflows/chaos-test.yml
name: Chaos Engineering Tests

on:
  pull_request:
    branches: [main]

jobs:
  chaos-test:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to staging
        run: kubectl apply -k k8s/overlays/staging/

      - name: Run chaos experiments
        run: |
          kubectl apply -f k8s/base/chaos-mesh/experiments/network-chaos.yaml
          kubectl apply -f k8s/base/chaos-mesh/experiments/pod-chaos.yaml

      - name: Wait for experiments to complete
        run: sleep 180

      - name: Verify system health
        run: |
          kubectl get pods --field-selector=status.phase!=Running
          # Fail if any pods are not running

      - name: Check distributed traces
        run: |
          # Use Jaeger API to verify traces show proper recovery
          curl http://jaeger-query:16686/api/traces?service=auth-service
```

---

## Next Steps

After implementing chaos engineering:

1. **✅ Use with Distributed Tracing** - Analyze chaos impact in Jaeger UI
2. **Implement GameDays** - Schedule monthly "chaos drills" with entire team
3. **Chaos as Code** - Store experiments in Git, version control
4. **Expand Coverage** - Add chaos experiments for each new service
5. **Integrate with Alerting** - Ensure alerts fire during chaos (test alert fatigue)

---

## References

- Chaos Mesh Documentation: https://chaos-mesh.org/docs/
- Principles of Chaos Engineering: https://principlesofchaos.org/
- OpenTelemetry Integration: https://opentelemetry.io/docs/
- Jaeger Distributed Tracing: https://www.jaegertracing.io/docs/

---

**Document Version**: 1.0
**Last Updated**: 2025-11-09
**Status**: Ready for Implementation
