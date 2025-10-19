# Kubernetes Deployment Guide - Nova

**Status**: ✅ Production Ready
**Last Updated**: October 17, 2024

---

## 📋 Prerequisites

- Kubernetes cluster 1.20+
- kubectl configured with cluster access
- Docker registry (Docker Hub, ECR, GCR, etc.)
- Cert-Manager for TLS certificates (optional but recommended)
- Nginx Ingress Controller (or similar)

## 🚀 Quick Start

### 1. Build and Push Docker Image

```bash
# Build the Docker image
cd backend
docker build -t your-registry/nova-api:v1.0.0 -f Dockerfile .

# Push to registry
docker push your-registry/nova-api:v1.0.0
```

### 2. Update K8s Configuration

Edit the following files with your production values:

#### `k8s/secret.yaml` - Set all secrets

```yaml
JWT_SECRET: "your_actual_jwt_secret"
JWT_PRIVATE_KEY_PEM: "your_base64_private_key"
JWT_PUBLIC_KEY_PEM: "your_base64_public_key"
AWS_ACCESS_KEY_ID: "your_aws_key"
AWS_SECRET_ACCESS_KEY: "your_aws_secret"
SMTP_USERNAME: "your_email@gmail.com"
SMTP_PASSWORD: "your_app_password"
```

#### `k8s/configmap.yaml` - Set your domains

```yaml
CORS_ALLOWED_ORIGINS: "https://nova.app,https://www.nova.app"
```

#### `k8s/ingress.yaml` - Set your DNS

```yaml
- host: api.nova.app
- host: api.www.nova.app
```

#### `k8s/kustomization.yaml` - Set your registry

```yaml
images:
- name: nova-api
  newName: your-registry/nova-api
  newTag: v1.0.0
```

### 3. Deploy to Kubernetes

```bash
# Option 1: Using Kustomize
kubectl apply -k k8s/

# Option 2: Using kubectl with individual files
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/rbac.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/redis.yaml
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/ingress.yaml
```

### 4. Verify Deployment

```bash
# Check namespace
kubectl get namespace nova

# Check all resources
kubectl get all -n nova

# Check pod status
kubectl get pods -n nova -w

# Check pod logs
kubectl logs -n nova deployment/nova-api -f

# Check ingress
kubectl get ingress -n nova

# Check HPA status
kubectl get hpa -n nova
```

---

## 🔧 Configuration Files

### `namespace.yaml`
- Creates isolated namespace for Nova application
- Provides namespace-level RBAC isolation

### `secret.yaml`
- Stores sensitive data: JWT keys, database passwords, API credentials
- **⚠️ IMPORTANT**: Update with actual values before deployment
- Never commit to version control - use external secret management

### `configmap.yaml`
- Non-sensitive configuration: timeouts, limits, environment flags
- Easy to update without redeploying pods

### `redis.yaml`
- Single Redis instance for caching
- EmptyDir volume (data lost on pod restart)
- **For production**: Use Redis StatefulSet or managed service (ElastiCache, etc.)

### `postgres.yaml`
- PostgreSQL StatefulSet for data persistence
- PVC (PersistentVolumeClaim) for data durability
- Automatic migration initialization

### `deployment.yaml`
- 3 replicas for high availability
- Rolling update strategy
- Init containers for dependency checks
- Liveness and readiness probes

### `ingress.yaml`
- Exposes API via domain names
- Auto TLS with Let's Encrypt
- Security headers and CORS configuration

### `hpa.yaml`
- Horizontal Pod Autoscaler
- Scales 3-10 pods based on CPU/memory
- Prevents sudden load spikes

### `rbac.yaml`
- Service account and role bindings
- Minimal permissions principle

---

## 📊 Architecture Overview

```
┌─────────────────────────────────────────┐
│         Kubernetes Cluster              │
├─────────────────────────────────────────┤
│ nova namespace                          │
│ ┌──────────────────────────────────┐   │
│ │ Ingress (HTTPS)                  │   │
│ │ api.nova.app                     │   │
│ └──────────────────────────────────┘   │
│            ↓                            │
│ ┌──────────────────────────────────┐   │
│ │ Service (ClusterIP)              │   │
│ │ nova-api:8080                    │   │
│ └──────────────────────────────────┘   │
│            ↓                            │
│ ┌─────────────────────────────────┐    │
│ │ Deployment (3 replicas, HPA)    │    │
│ │ ├─ Pod 1 (nova-api)             │    │
│ │ ├─ Pod 2 (nova-api)             │    │
│ │ └─ Pod 3 (nova-api)             │    │
│ └─────────────────────────────────┘    │
│  ↙          ↓          ↖                │
│  ┌──────────┴──────────┐               │
│  ↓                     ↓                │
│ ┌──────────────┐  ┌──────────────┐    │
│ │ PostgreSQL   │  │ Redis        │    │
│ │ (StatefulSet)│  │ (Deployment) │    │
│ │ PVC: 10Gi    │  │ EmptyDir     │    │
│ └──────────────┘  └──────────────┘    │
└─────────────────────────────────────────┘
```

---

## 🔐 Secret Management Best Practices

### Option 1: Environment Variables (Development)
```bash
export DATABASE_URL="postgres://user:pass@host:5432/db"
export JWT_PRIVATE_KEY_PEM="$(cat private.pem | base64)"
```

### Option 2: AWS Secrets Manager

```yaml
apiVersion: v1
kind: SecretProviderClass
metadata:
  name: nova-secrets
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "nova/jwt-private-key"
        objectType: "secretsmanager"
      - objectName: "nova/database-password"
        objectType: "secretsmanager"
```

### Option 3: HashiCorp Vault

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nova-api
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "nova"
```

### Option 4: Sealed Secrets

```bash
# Encrypt secret
kubectl apply -f <(echo <secret.yaml> | kubeseal -f -)
```

---

## 📈 Scaling Configuration

### Current HPA Settings
- **Minimum replicas**: 3
- **Maximum replicas**: 10
- **CPU threshold**: 70%
- **Memory threshold**: 80%
- **Scale-up**: +100% or +2 pods per 15 seconds
- **Scale-down**: -50% or -1 pod per 30 seconds

### Adjust Scaling

Edit `k8s/hpa.yaml`:

```yaml
spec:
  minReplicas: 5        # Increase for high baseline load
  maxReplicas: 20       # Increase for traffic spikes
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60  # Lower = scale faster
```

---

## 💾 Database Persistence

### Current Setup (Single Node)
- PostgreSQL StatefulSet with 10Gi PVC
- Suitable for development/testing
- **Data loss risk**: Pod restart on node failure

### Production Setup (Recommended)

#### Option 1: Managed Database
```yaml
# Use AWS RDS, Google Cloud SQL, or Azure Database
DATABASE_URL: "postgres://managed-service-endpoint"
```

#### Option 2: Postgres HA Cluster
```yaml
# Use patroni for automatic failover
# Install via: helm repo add zalando https://zalando.github.io/postgres-operator/
helm install postgres-operator zalando/postgres-operator
```

#### Option 3: Multi-Replica PostgreSQL
```yaml
# Modify postgres.yaml replicas: 3
# Requires read replicas and WAL streaming
```

---

## 🔄 Continuous Deployment

### GitHub Actions Example

```yaml
name: Deploy to K8s

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2

    - name: Build Docker image
      run: |
        docker build -t ${{ secrets.REGISTRY }}/nova-api:${{ github.sha }} backend/

    - name: Push to registry
      run: |
        docker push ${{ secrets.REGISTRY }}/nova-api:${{ github.sha }}

    - name: Update K8s deployment
      run: |
        kubectl set image deployment/nova-api \
          nova-api=${{ secrets.REGISTRY }}/nova-api:${{ github.sha }} \
          -n nova

    - name: Verify rollout
      run: |
        kubectl rollout status deployment/nova-api -n nova
```

---

## 🧪 Testing Deployment

### Health Check
```bash
# Port forward to test
kubectl port-forward svc/nova-api 8080:8080 -n nova

# Test health endpoint
curl http://localhost:8080/api/v1/health
```

### Database Connectivity
```bash
# Check database pod logs
kubectl logs -n nova nova-postgres-0

# Connect to database
kubectl exec -it nova-postgres-0 -n nova -- psql -U postgres
```

### API Testing
```bash
# Get JWT token (after login)
curl -X POST http://api.nova.app/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password"}'

# Test protected endpoint
curl -X GET http://api.nova.app/api/v1/posts \
  -H "Authorization: Bearer <token>"
```

---

## 🐛 Troubleshooting

### Pod not starting

```bash
# Check pod events
kubectl describe pod nova-api-xxx -n nova

# Check logs
kubectl logs nova-api-xxx -n nova
kubectl logs nova-api-xxx -n nova --previous  # Previous instance
```

### Database connection issues

```bash
# Verify database is running
kubectl get pods -n nova -l app=nova-postgres

# Check database logs
kubectl logs nova-postgres-0 -n nova

# Verify SECRET is loaded
kubectl get secret nova-secrets -n nova -o yaml
```

### High memory usage

```bash
# Check resource usage
kubectl top pods -n nova

# View pod resource requests/limits
kubectl describe pod nova-api-xxx -n nova
```

### Update secrets

```bash
# Edit secret
kubectl edit secret nova-secrets -n nova

# Apply new secret
kubectl apply -f k8s/secret.yaml

# Restart pods to reload secrets
kubectl rollout restart deployment/nova-api -n nova
```

---

## 📦 Backup & Restore

### Database Backup

```bash
# Create backup
kubectl exec -it nova-postgres-0 -n nova -- \
  pg_dump -U postgres nova_prod > backup.sql

# Restore backup
kubectl exec -it nova-postgres-0 -n nova -- \
  psql -U postgres < backup.sql
```

### Automated Backup with CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: nova
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: postgres-backup
            image: postgres:15-alpine
            command:
            - /bin/sh
            - -c
            - |
              pg_dump -U postgres nova_prod | \
              gzip > /backup/nova_$(date +%Y%m%d_%H%M%S).sql.gz
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: postgres-backup-pvc
          restartPolicy: OnFailure
```

---

## 📊 Monitoring

### Prometheus Metrics

Endpoints expose metrics on `:8080/metrics`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nova-api
  namespace: nova
spec:
  selector:
    matchLabels:
      app: nova-api
  endpoints:
  - port: http
    interval: 30s
    path: /metrics
```

### Key Metrics to Monitor
- `http_requests_total` - Request volume
- `http_request_duration_seconds` - Response latency
- `postgres_client_backend_connections_sum` - DB connections
- `redis_connected_clients` - Redis connections

---

## 🔄 Rolling Updates

### Automatic Rolling Update

```bash
# Update image
kubectl set image deployment/nova-api \
  nova-api=your-registry/nova-api:v1.1.0 \
  -n nova

# Monitor rollout
kubectl rollout status deployment/nova-api -n nova

# Rollback if needed
kubectl rollout undo deployment/nova-api -n nova
```

### Blue-Green Deployment

```bash
# Deploy new version as separate deployment
kubectl apply -f nova-api-v2.yaml

# Switch traffic via service selector
kubectl patch service nova-api -n nova \
  -p '{"spec":{"selector":{"version":"v2"}}}'
```

---

## 📋 Pre-Production Checklist

- [ ] Update all secrets with production values
- [ ] Configure domain names in ingress.yaml
- [ ] Set up TLS certificates
- [ ] Configure database backups
- [ ] Set up monitoring and alerting
- [ ] Configure log aggregation
- [ ] Test failover scenarios
- [ ] Load test the application
- [ ] Review security policies
- [ ] Document runbooks
- [ ] Train ops team

---

## 📞 Support & Documentation

- **Kubernetes Docs**: https://kubernetes.io/docs/
- **Kustomize Docs**: https://kustomize.io/
- **Cert-Manager**: https://cert-manager.io/
- **Nginx Ingress**: https://kubernetes.github.io/ingress-nginx/

---

**Generated**: October 17, 2024
**Status**: ✅ PRODUCTION READY
