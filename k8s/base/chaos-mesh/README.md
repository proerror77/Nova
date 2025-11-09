# Chaos Mesh Quick Reference

## Quick Start

### Deploy to Staging
```bash
kubectl apply -k k8s/overlays/staging/chaos-mesh/
```

### Deploy to Production
```bash
kubectl apply -k k8s/overlays/production/chaos-mesh/
```

### Access Dashboard
```bash
kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333
# Open http://localhost:2333
```

## Run Experiments Manually

### Network Latency (100ms)
```bash
kubectl apply -f experiments/network-chaos.yaml
```

### Pod Kill
```bash
kubectl apply -f experiments/pod-chaos.yaml
```

### CPU Stress
```bash
kubectl apply -f experiments/stress-chaos.yaml
```

### Full Workflow (Network → Pod → Stress)
```bash
kubectl apply -f experiments/workflow-chaos.yaml
```

## Check Experiment Status

```bash
# List all chaos experiments
kubectl get networkchaos,podchaos,stresschaos,iochaos -A

# Check specific experiment
kubectl describe networkchaos network-delay-auth-service

# View experiment events
kubectl get events --field-selector involvedObject.kind=NetworkChaos
```

## Stop Experiment

```bash
# Delete experiment (stops immediately)
kubectl delete networkchaos network-delay-auth-service

# Force delete if stuck
kubectl delete networkchaos network-delay-auth-service --force --grace-period=0
```

## Monitor with Distributed Tracing

1. **Start Jaeger UI**:
   ```bash
   kubectl port-forward -n observability svc/jaeger-query 16686:16686
   # Open http://localhost:16686
   ```

2. **Run chaos experiment**

3. **Search traces** in Jaeger:
   - Service: Select affected service (e.g., auth-service)
   - Tags: `http.status_code=500` (find errors)
   - Duration: `> 1000ms` (find slow requests)

4. **Analyze impact**:
   - Look for timeout errors
   - Check circuit breaker activation
   - Verify retry attempts
   - Confirm graceful degradation

## Common Experiments

### Test Timeout Handling
```bash
kubectl apply -f - <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: timeout-test
spec:
  action: delay
  mode: one
  selector:
    labelSelectors:
      app: auth-service
  delay:
    latency: "5s"  # Longer than timeout
  duration: "1m"
EOF
```

### Test Auto-Recovery
```bash
kubectl apply -f - <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: recovery-test
spec:
  action: pod-kill
  mode: one
  selector:
    labelSelectors:
      app: user-service
  duration: "30s"
EOF
```

### Test Rate Limiting
```bash
kubectl apply -f - <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: ratelimit-test
spec:
  mode: one
  selector:
    labelSelectors:
      app: auth-service
  stressors:
    cpu:
      workers: 2
      load: 80
  duration: "2m"
EOF
```

## Environment Differences

| Feature | Staging | Production |
|---------|---------|------------|
| Schedule | Every 30min - 6h | Weekly only |
| Experiments | All types | Safe only |
| Duration | 1-5 minutes | 30s - 1min |
| Mode | `one`, `all`, `fixed` | `one` only |
| Security | Disabled | Strict |
| Target | All pods | Canary pods only |

## Troubleshooting

### Experiment not starting?
```bash
# Check controller logs
kubectl logs -n chaos-mesh deployment/chaos-controller-manager

# Check daemon logs
kubectl logs -n chaos-mesh daemonset/chaos-daemon

# Verify selector matches
kubectl get pods -l app=auth-service
```

### Experiment not stopping?
```bash
# Force delete
kubectl delete <chaos-type> <name> --force --grace-period=0

# Restart controller if needed
kubectl rollout restart -n chaos-mesh deployment/chaos-controller-manager
```

## Safety Guidelines

### ✅ Safe for Staging
- Any experiment type
- Any duration < 10 minutes
- Any mode (one, all, fixed)
- Concurrent experiments OK

### ⚠️ Production - Requires Approval
- Only safe experiments (labeled `chaos.approved-by`)
- Duration < 1 minute only
- Mode: `one` only (single pod)
- Target canary pods only (`chaos.mesh/canary: "true"`)
- No concurrent experiments
- Scheduled during maintenance windows only

## Further Reading

See [docs/CHAOS_ENGINEERING_GUIDE.md](../../../docs/CHAOS_ENGINEERING_GUIDE.md) for:
- Complete deployment instructions
- Detailed experiment examples
- Best practices
- Integration with distributed tracing
- Security considerations
- Monitoring and alerting
