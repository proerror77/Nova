---
description: Deploy microservices to Kubernetes with production-grade configurations
---

## User Input

```text
$ARGUMENTS
```

Expected format: `<action> <service-name> [environment]`

Actions:
- `generate` - Generate K8s manifests for service
- `apply` - Deploy service to cluster
- `update` - Update existing deployment
- `rollback` - Rollback to previous version
- `status` - Check deployment status
- `logs` - Tail service logs
- `scale` - Scale replicas manually

Environments:
- `dev` - Development cluster
- `staging` - Staging cluster
- `production` - Production cluster (default)

Examples:
- `/k8s.deploy generate user-service`
- `/k8s.deploy apply user-service staging`
- `/k8s.deploy status user-service`
- `/k8s.deploy rollback user-service production`
- `/k8s.deploy scale user-service 5`

## Execution Flow

### 1. Parse Arguments

Extract:
- **Action**: generate | apply | update | rollback | status | logs | scale
- **Service name**: Target microservice
- **Environment**: dev | staging | production (default: production)
- **Extra args**: Scale count, tag version, etc.

### 2. Route to Action Handler

#### Action: generate

Invoke **k8s-deployment-engineer** agent:

```
Task: Generate production-ready K8s manifests
Agent: k8s-deployment-engineer
Prompt: |
  Generate complete Kubernetes manifests for {service-name}:

  Create the following files in k8s/microservices/:

  1. {service-name}-deployment.yaml
     - Deployment with resource management
     - Requests: CPU 100m, Memory 128Mi
     - Limits: CPU 500m, Memory 512Mi
     - Health probes (liveness, readiness, startup)
     - Environment variables from ConfigMap/Secret
     - Anti-affinity to spread pods across nodes
     - Graceful shutdown (preStop hook with 15s delay)

  2. {service-name}-service.yaml
     - ClusterIP Service
     - gRPC port: 50051
     - Metrics port: 9090
     - Prometheus scraping annotations

  3. {service-name}-hpa.yaml
     - HorizontalPodAutoscaler
     - Min replicas: 3, Max replicas: 10
     - CPU target: 70%
     - Memory target: 80%
     - Scale-down stabilization: 300s

  4. {service-name}-configmap.yaml
     - Non-sensitive configuration
     - RUST_LOG level
     - Feature flags
     - Service URLs (from cluster DNS)

  5. {service-name}-secret.yaml (template only)
     - DATABASE_URL placeholder
     - REDIS_URL placeholder
     - KAFKA_BROKERS placeholder
     - JWT_SECRET placeholder
     - NOTE: Actual secrets managed by sealed-secrets or external secrets operator

  6. {service-name}-pdb.yaml
     - Pod Disruption Budget
     - minAvailable: 2 (ensure 2 pods always running during disruptions)

  Use skill: k8s-deployment-patterns

  Follow production best practices:
  - Never run as root (runAsUser: 1000)
  - Read-only root filesystem
  - Drop all capabilities
  - Resource quotas aligned with service tier
```

Save generated manifests and display file paths.

#### Action: apply

**Deployment workflow:**

1. **Pre-deployment validation**:
   ```bash
   # Verify manifests are valid
   kubectl --dry-run=client -f k8s/microservices/{service-name}-*.yaml

   # Check if namespace exists
   kubectl get namespace {environment}

   # Verify image exists in registry
   docker pull {registry}/{service-name}:{tag}
   ```

2. **Create namespace if missing**:
   ```bash
   kubectl create namespace {environment} --dry-run=client -o yaml | kubectl apply -f -
   ```

3. **Apply manifests in order**:
   ```bash
   # 1. ConfigMap and Secrets first
   kubectl apply -f k8s/microservices/{service-name}-configmap.yaml -n {environment}
   kubectl apply -f k8s/microservices/{service-name}-secret.yaml -n {environment}

   # 2. Service (before Deployment for DNS)
   kubectl apply -f k8s/microservices/{service-name}-service.yaml -n {environment}

   # 3. Pod Disruption Budget
   kubectl apply -f k8s/microservices/{service-name}-pdb.yaml -n {environment}

   # 4. Deployment
   kubectl apply -f k8s/microservices/{service-name}-deployment.yaml -n {environment}

   # 5. HorizontalPodAutoscaler
   kubectl apply -f k8s/microservices/{service-name}-hpa.yaml -n {environment}
   ```

4. **Wait for rollout completion**:
   ```bash
   kubectl rollout status deployment/{service-name} -n {environment} --timeout=5m
   ```

5. **Verify deployment health**:
   ```bash
   # Check pod status
   kubectl get pods -l app={service-name} -n {environment}

   # Check readiness
   kubectl get deployment {service-name} -n {environment}

   # Check HPA status
   kubectl get hpa {service-name} -n {environment}
   ```

6. **Smoke tests** (if production):
   ```bash
   # Port-forward to service
   kubectl port-forward -n {environment} svc/{service-name} 50051:50051 &

   # Test gRPC health check
   grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check

   # Kill port-forward
   kill %1
   ```

#### Action: update

**Rolling update workflow:**

1. **Confirm current version**:
   ```bash
   kubectl get deployment {service-name} -n {environment} -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

2. **Update image tag** (if specified):
   ```bash
   kubectl set image deployment/{service-name} {service-name}={registry}/{service-name}:{new-tag} -n {environment}
   ```

3. **Monitor rollout**:
   ```bash
   kubectl rollout status deployment/{service-name} -n {environment} --watch
   ```

4. **Verify health after update**:
   - Check pod logs for errors
   - Verify metrics endpoint responding
   - Check dependent services still functional

#### Action: rollback

**Rollback workflow:**

1. **Show rollout history**:
   ```bash
   kubectl rollout history deployment/{service-name} -n {environment}
   ```

2. **Confirm rollback with user**:
   ```
   ⚠️  WARNING: Rollback will revert to previous version

   Current revision: {current-revision}
   Previous revision: {previous-revision}
   Service: {service-name}
   Environment: {environment}

   Proceed with rollback? (yes/no)
   ```

3. **If confirmed**:
   ```bash
   kubectl rollout undo deployment/{service-name} -n {environment}
   ```

4. **Monitor rollback**:
   ```bash
   kubectl rollout status deployment/{service-name} -n {environment} --watch
   ```

5. **Verify service health**:
   - Check pod status
   - Verify logs
   - Test critical endpoints

#### Action: status

**Comprehensive status check:**

```bash
# Deployment status
kubectl get deployment {service-name} -n {environment}

# Pod status with details
kubectl get pods -l app={service-name} -n {environment} -o wide

# HPA status
kubectl get hpa {service-name} -n {environment}

# Service endpoints
kubectl get endpoints {service-name} -n {environment}

# Recent events
kubectl get events -n {environment} --field-selector involvedObject.name={service-name} --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top pods -l app={service-name} -n {environment}
```

Display formatted status report:

```markdown
## Deployment Status: {service-name}

**Environment**: {environment}
**Replicas**: {current}/{desired} ready
**Image**: {image}:{tag}
**Status**: ✅ Healthy | ⚠️  Degraded | ❌ Unhealthy

### Pods
| Name | Status | Restarts | Age | Node |
|------|--------|----------|-----|------|
| ... | ... | ... | ... | ... |

### HPA
- Current replicas: {current}
- Desired replicas: {desired}
- CPU usage: {cpu}%
- Memory usage: {memory}%

### Recent Events
{events}
```

#### Action: logs

**Log streaming:**

```bash
# Tail logs from all pods
kubectl logs -f -l app={service-name} -n {environment} --all-containers=true --max-log-requests=10

# Or specific pod if provided
kubectl logs -f {pod-name} -n {environment}
```

**Log filtering options**:
- `--since=5m` - Last 5 minutes
- `--tail=100` - Last 100 lines
- `--previous` - Logs from crashed container

#### Action: scale

**Manual scaling:**

1. **Validate scale count**:
   - Minimum: 2 (for availability)
   - Maximum: Check HPA max replicas
   - Warn if overriding HPA

2. **Execute scaling**:
   ```bash
   kubectl scale deployment {service-name} --replicas={count} -n {environment}
   ```

3. **Monitor scaling**:
   ```bash
   kubectl get deployment {service-name} -n {environment} --watch
   ```

4. **Verify new replicas healthy**:
   ```bash
   kubectl get pods -l app={service-name} -n {environment}
   ```

### 3. Production Safety Checks

**Before deploying to production:**

1. **Invoke k8s-deployment-engineer for review**:
   ```
   Task: Review deployment readiness
   Agent: k8s-deployment-engineer
   Prompt: |
     Review {service-name} deployment to production:

     Checklist:
     1. Resource limits set appropriately
     2. All three health probes configured
     3. HPA enabled with correct targets
     4. Pod Disruption Budget allows disruptions
     5. Anti-affinity prevents single-node deployment
     6. Secrets not in plain text
     7. Image tag is not 'latest'
     8. Graceful shutdown configured

     Recommendation: APPROVED | REQUIRES_CHANGES | BLOCKED
   ```

2. **If REQUIRES_CHANGES or BLOCKED**:
   - Display issues
   - Halt deployment
   - Suggest fixes

3. **If APPROVED**:
   - Proceed with deployment
   - Monitor closely

### 4. Integration with Observability

After deployment:

1. **Verify Prometheus scraping**:
   ```bash
   kubectl get servicemonitor {service-name} -n {environment}
   ```

2. **Check Grafana dashboard**:
   - Display link to service dashboard
   - Show key metrics (request rate, error rate, latency)

3. **Set up alerts** (if first deployment):
   - High error rate
   - High memory usage
   - Pod crash loop

### 5. Output Summary

```markdown
## Deployment Complete: {service-name}

**Environment**: {environment}
**Action**: {action}
**Status**: ✅ SUCCESS | ⚠️  WARNING | ❌ ERROR

### Deployment Details
- Replicas: {replicas}
- Image: {image}:{tag}
- Rollout duration: {duration}

### Health Status
- Pods ready: {ready}/{desired}
- HPA active: {hpa-status}
- Last restart: {last-restart}

### Access Information
- Internal URL: http://{service-name}.{environment}.svc.cluster.local:50051
- Metrics: http://{service-name}.{environment}.svc.cluster.local:9090/metrics

### Next Steps
1. Monitor logs: `/k8s.deploy logs {service-name}`
2. Check metrics in Grafana: {dashboard-url}
3. Run smoke tests against service
4. Monitor error rates for 15 minutes

### Rollback Command
If issues occur:
```bash
/k8s.deploy rollback {service-name} {environment}
```
```

## Error Handling

- **Manifest validation errors**: Display kubectl validation output
- **Image pull errors**: Check image exists in registry
- **Resource quota exceeded**: Display current quota usage
- **Rollout timeout**: Suggest checking pod events and logs
- **Health probe failures**: Display probe configuration and recent failures

## Integration with Skills

This command automatically leverages:
- **k8s-deployment-patterns**: Production manifest templates
- **microservices-architecture**: Service mesh integration
- **rust-async-patterns**: Graceful shutdown best practices
