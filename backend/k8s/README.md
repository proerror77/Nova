# Nova Backend - Kubernetes Manifests

This directory contains Kubernetes manifests for deploying all 11 Nova microservices to production.

## Directory Structure

```
k8s/
├── base/                           # Base manifests (shared across environments)
│   ├── namespace.yaml              # nova-backend namespace
│   ├── configmap.yaml              # Shared configuration
│   ├── auth-service.yaml           # Auth service deployment + service
│   ├── user-service.yaml           # User service deployment + service
│   ├── content-service.yaml        # Content service deployment + service
│   ├── feed-service.yaml           # Feed service deployment + service
│   ├── media-service.yaml          # Media service deployment + service
│   ├── messaging-service.yaml      # Messaging service deployment + service
│   ├── search-service.yaml         # Search service deployment + service
│   ├── streaming-service.yaml      # Streaming service deployment + service
│   ├── notification-service.yaml   # Notification service deployment + service
│   ├── cdn-service.yaml            # CDN service deployment + service
│   ├── events-service.yaml         # Events service deployment + service
│   └── kustomization.yaml          # Kustomize base configuration
├── overlays/                       # Environment-specific overrides
│   ├── dev/                        # Development environment
│   ├── staging/                    # Staging environment
│   └── prod/                       # Production environment
│       └── kustomization.yaml      # Production-specific config
└── generate-manifests.sh           # Script to generate all service manifests

README.md                           # This file
```

## Quick Start

### 1. Generate Service Manifests

All 11 services follow the same pattern. Use the generator script to avoid duplication:

```bash
cd k8s
./generate-manifests.sh
```

This will create Kubernetes manifests for all services in the `base/` directory.

### 2. Create Secrets

**IMPORTANT:** Never commit secrets to git. Create them manually:

```bash
# Create from .env file (recommended)
kubectl create secret generic nova-backend-secrets \
  -n nova-backend \
  --from-env-file=../.env.prod \
  --dry-run=client -o yaml | kubectl apply -f -

# Or create interactively
kubectl create secret generic nova-backend-secrets \
  -n nova-backend \
  --from-literal=DATABASE_URL="postgresql://..." \
  --from-literal=JWT_PRIVATE_KEY_PEM="..." \
  --from-literal=AWS_ACCESS_KEY_ID="..." \
  --from-literal=AWS_SECRET_ACCESS_KEY="..."
```

### 3. Deploy to Kubernetes

**Development:**

```bash
kubectl apply -k overlays/dev/
```

**Staging:**

```bash
kubectl apply -k overlays/staging/
```

**Production:**

```bash
# Use kustomize to preview changes
kubectl kustomize overlays/prod/

# Apply production deployment
kubectl apply -k overlays/prod/

# Wait for rollout
kubectl rollout status deployment -n nova-backend --timeout=5m
```

## Service Configuration

### Port Convention

**Rule:** gRPC port = HTTP port + 1000

| Service | HTTP Port | gRPC Port |
|---------|-----------|-----------|
| auth-service | 8083 | 9083 |
| user-service | 8080 | 9080 |
| content-service | 8081 | 9081 |
| feed-service | 8084 | 9084 |
| media-service | 8082 | 9082 |
| messaging-service | 8085 | 9085 |
| search-service | 8086 | 9086 |
| streaming-service | 8087 | 9087 |
| notification-service | 8088 | 9088 |
| cdn-service | 8089 | 9089 |
| events-service | 8090 | 9090 |

### Resource Limits

**Base (Development/Staging):**
- Requests: 256Mi memory, 100m CPU
- Limits: 512Mi memory, 500m CPU

**Production (overlays/prod):**
- Requests: 512Mi memory, 200m CPU
- Limits: 1Gi memory, 1000m CPU

### Health Probes

All services expose three health check endpoints:

- **Liveness:** `GET /api/v1/health/live` (30s interval, 5s timeout, 3 failures → restart)
- **Readiness:** `GET /api/v1/health/ready` (5s interval, 3s timeout, 3 failures → remove from LB)
- **Startup:** `GET /api/v1/health` (5s interval, 3s timeout, 30 failures → restart)

## Deployment Patterns

### Rolling Update (Default)

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # 1 extra pod during update
    maxUnavailable: 0  # Keep all replicas available
```

### Canary Deployment

For gradual rollout with traffic splitting:

1. Deploy new version alongside old version
2. Route 5% traffic to new version (15 min monitoring)
3. Route 50% traffic to new version (30 min monitoring)
4. Route 100% traffic to new version
5. Terminate old version

See [DEPLOYMENT_CHECKLIST.md](../DEPLOYMENT_CHECKLIST.md) for detailed steps.

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n nova-backend

# View logs
kubectl logs -n nova-backend <pod-name>

# Describe pod for events
kubectl describe pod -n nova-backend <pod-name>
```

Common issues:
- Missing secrets → Check `nova-backend-secrets` exists
- Image pull errors → Verify image exists in registry
- Health check failures → Check database/redis connectivity

### Configuration Issues

```bash
# View applied ConfigMap
kubectl get configmap -n nova-backend nova-backend-config -o yaml

# View secrets (values are base64 encoded)
kubectl get secret -n nova-backend nova-backend-secrets -o yaml

# Edit ConfigMap (triggers pod restart)
kubectl edit configmap -n nova-backend nova-backend-config
```

### Service Connectivity

```bash
# Test service DNS
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://auth-service.nova-backend.svc.cluster.local:8083/api/v1/health

# Check service endpoints
kubectl get endpoints -n nova-backend auth-service
```

## Monitoring

### Metrics Endpoint

All services expose Prometheus metrics at `/metrics`:

```bash
# Port-forward and scrape metrics
kubectl port-forward -n nova-backend svc/auth-service 8083:8083
curl http://localhost:8083/metrics
```

### Logs

```bash
# Tail logs from all pods of a service
kubectl logs -f -n nova-backend -l app=auth-service

# Tail logs from all services
kubectl logs -f -n nova-backend -l component=backend
```

## Scaling

### Manual Scaling

```bash
# Scale single service
kubectl scale deployment -n nova-backend auth-service --replicas=5

# Scale all services
kubectl scale deployment -n nova-backend --all --replicas=3
```

### Horizontal Pod Autoscaler (HPA)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: auth-service-hpa
  namespace: nova-backend
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: auth-service
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

## Cleanup

```bash
# Delete all services
kubectl delete -k overlays/prod/

# Delete namespace (WARNING: deletes everything)
kubectl delete namespace nova-backend
```

## Next Steps

1. Review [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md) for complete deployment workflow
2. Follow [DEPLOYMENT_CHECKLIST.md](../DEPLOYMENT_CHECKLIST.md) before deploying to production
3. Set up monitoring dashboards (see `monitoring/` directory)
4. Configure alerts in AlertManager

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kustomize](https://kustomize.io/)
- [Nova Backend Architecture](../../docs/architecture/)
