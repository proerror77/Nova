# Phase 4 Deployment Progress Monitoring - Claude Code Integration

**Purpose**: Monitor Phase 4 GraphQL Gateway staging deployment directly within Claude Code without external tools.

## Quick Start

### Check Deployment Status (Single Check)
```bash
./.claude/monitor-deployment.sh
```

This will show:
- Current deployment run ID
- Overall status (queued/in progress/completed)
- Individual job status (Build & Push, Deploy to K8s, Smoke Tests, Load Tests)
- Last update timestamp

### Watch Deployment Live (Continuous Monitoring)
```bash
./.claude/monitor-deployment.sh --watch 5
```

This continuously updates every 5 seconds until deployment completes.

Options:
- `--watch 5`: Update every 5 seconds
- `--watch 10`: Update every 10 seconds
- `--watch 30`: Update every 30 seconds (default)

## How It Works

The monitor script:
1. Queries GitHub Actions API via `gh` CLI
2. Gets the latest "Phase 4 - GraphQL Gateway Staging Deployment" run
3. Extracts job status (build, deploy, smoke tests, load tests)
4. Displays color-coded output:
   - 🟢 `✓ COMPLETED` (green)
   - 🔵 `⟳ IN PROGRESS` (blue)
   - 🟡 `◐ QUEUED` or pending (yellow)
   - 🔴 `✗ FAILED` (red)

## Deployment Stages

The Phase 4 deployment runs 5 jobs in sequence:

### 1. Build & Push GraphQL Gateway
- **Duration**: ~5-10 minutes
- **Task**: Compiles Rust code, builds Docker image, pushes to AWS ECR
- **Watches for**: Rust compilation, Docker build completion

### 2. Deploy to Kubernetes
- **Duration**: ~2-3 minutes
- **Task**: Applies K8s manifests, updates deployment, waits for rollout
- **Depends on**: Build & Push completion
- **Watches for**: Pod startup, readiness probes passing

### 3. Run Smoke Tests
- **Duration**: ~1-2 minutes
- **Task**: Tests health endpoints, verifies pod readiness
- **Depends on**: Deploy completion
- **Watches for**: Pod health check endpoints responding

### 4. Run k6 Load Tests (Optional)
- **Duration**: ~1-2 minutes
- **Task**: Runs performance tests against deployed GraphQL gateway
- **Condition**: Only runs if `run_load_tests=true` (default enabled)
- **Watches for**: k6 test completion, performance metrics

### 5. Deployment Summary
- **Duration**: <1 minute
- **Task**: Generates GitHub Actions summary with status
- **Depends on**: All other jobs
- **Output**: Available in GitHub Actions job summary

## Exit Codes

```bash
$? = 0  → Deployment SUCCESS (all stages completed)
$? = 1  → Deployment IN PROGRESS (check again later)
$? = 2  → Deployment FAILED (needs investigation)
```

Use in scripts:
```bash
if ./.claude/monitor-deployment.sh; then
  echo "✓ Deployment succeeded"
else
  code=$?
  if [ $code -eq 1 ]; then
    echo "Deployment still running..."
  else
    echo "Deployment failed!"
  fi
fi
```

## Troubleshooting

### "No deployment runs found"
- Workflow hasn't been triggered yet
- Check: `gh run list --repo proerror77/Nova --workflow phase4-staging-deployment.yml`
- Trigger: Use `gh workflow run phase4-staging-deployment.yml --ref main`

### "Logs not yet available"
- Job is still queued or running
- Wait a few seconds and check again
- Logs become available once job starts executing

### "gh command not found"
- GitHub CLI not installed
- Install: `brew install gh` (macOS) or see https://cli.github.com
- Authenticate: `gh auth login`

## Integration with Claude Code

### Option 1: Direct Monitoring
```bash
# Check status directly in Claude Code
./.claude/monitor-deployment.sh

# Get more details
./.claude/monitor-deployment.sh --watch 10
```

### Option 2: Background Process
Claude Code can start monitoring in background and periodically check:
```bash
# Start continuous monitoring (returns immediately)
./.claude/monitor-deployment.sh --watch 5 > /tmp/deployment.log 2>&1 &

# Later: Check the log
tail /tmp/deployment.log

# Get current status
./.claude/monitor-deployment.sh
```

### Option 3: Scripted Integration
```bash
#!/bin/bash
# Example script for automated checks

while true; do
  status=$(./.claude/monitor-deployment.sh 2>&1)

  # Parse status
  if echo "$status" | grep -q "COMPLETED.*SUCCESS"; then
    echo "✓ Deployment successful!"
    break
  elif echo "$status" | grep -q "FAILED"; then
    echo "✗ Deployment failed!"
    break
  fi

  echo "Status check at $(date)"
  echo "$status"
  sleep 30
done
```

## Key Deployment Information

### Kubernetes Resources
- **Namespace**: `nova-staging`
- **Deployment**: `graphql-gateway`
- **Replicas**: 2 initial (scales to 4 with HPA)
- **Service**: `graphql-gateway` (port 80)

### Configuration
- **Image Registry**: AWS ECR (025434362120.dkr.ecr.ap-northeast-1.amazonaws.com)
- **Tag Format**: `phase4-staging-<commit-sha>`
- **Region**: ap-northeast-1 (Tokyo)

### Health Checks
After deployment completes, verify:
```bash
# Port-forward to the service
kubectl port-forward -n nova-staging svc/graphql-gateway 8080:80

# Test endpoints
curl http://localhost:8080/health          # Health check
curl http://localhost:8080/graphql         # GraphQL endpoint
curl http://localhost:8080/schema          # Schema endpoint
```

## What's Monitored

The deployment workflow validates:

✅ **Build Phase**
- Rust compilation (cargo build)
- Docker image creation
- ECR push success

✅ **Deployment Phase**
- K8s manifests validation
- ConfigMap/Secret creation
- Deployment creation
- Pod startup

✅ **Smoke Tests**
- Pod readiness probes
- Health endpoint response
- Service availability

✅ **Performance Tests** (optional)
- GraphQL query performance
- WebSocket subscription load
- Rate limiting enforcement
- Latency percentiles (p95, p99)

## Next Steps After Successful Deployment

1. **Port-forward to the service**
   ```bash
   kubectl port-forward -n nova-staging svc/graphql-gateway 8080:80
   ```

2. **Test GraphQL endpoint**
   ```bash
   curl -X POST http://localhost:8080/graphql \
     -H "Content-Type: application/json" \
     -d '{"query":"query { __typename }"}'
   ```

3. **Check logs**
   ```bash
   kubectl logs -n nova-staging -l app=graphql-gateway -f
   ```

4. **Verify Kafka integration**
   ```bash
   kubectl exec -it <pod-name> -n nova-staging -- \
     sh -c "echo 'Kafka check' | nc kafka-broker:9092"
   ```

## References

- `.github/workflows/phase4-staging-deployment.yml` - Deployment workflow
- `k8s/staging/graphql-gateway-deployment.yaml` - Kubernetes deployment
- `k8s/staging/DEPLOYMENT_GUIDE.md` - Detailed K8s deployment guide
- `PHASE_4_COMPLETION_SUMMARY.md` - Phase 4 implementation summary
