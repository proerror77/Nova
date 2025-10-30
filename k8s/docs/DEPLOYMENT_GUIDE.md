# Kubernetes Deployment Guide for Nova Messaging Service

## Overview

This guide provides complete instructions for deploying the Nova Messaging Service to a Kubernetes cluster. The messaging service handles real-time messaging, WebSocket connections, and video call signaling for the Nova Social Platform.

## Prerequisites

### Required Tools
- `kubectl` (v1.24+)
- Kubernetes cluster (v1.24+)
- Helm 3.0+ (optional, for templating)

### Cluster Requirements
- Minimum 3 worker nodes (for pod affinity)
- 4GB memory per node minimum
- 2 CPU cores per node minimum
- Persistent Volume support (for databases)

### External Dependencies
- PostgreSQL database (separate deployment or managed service)
- Redis (separate deployment or managed service)
- Kafka cluster (separate deployment or managed service)

## Architecture

```
┌─────────────────────────────────────────────┐
│         Kubernetes Cluster                  │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │    nova-messaging Namespace          │  │
│  │                                      │  │
│  │  ┌──────────────────────────────┐   │  │
│  │  │  Deployment (3 replicas)     │   │  │
│  │  │  - Running messaging-service │   │  │
│  │  │  - Database migrations       │   │  │
│  │  │  - Health checks enabled     │   │  │
│  │  └──────────────────────────────┘   │  │
│  │                 ↕                    │  │
│  │  ┌──────────────────────────────┐   │  │
│  │  │  Service (ClusterIP)         │   │  │
│  │  │  - Port 3000: HTTP/WebSocket │   │  │
│  │  │  - Port 9090: Metrics        │   │  │
│  │  └──────────────────────────────┘   │  │
│  │                 ↕                    │  │
│  │  ┌──────────────────────────────┐   │  │
│  │  │  Service (LoadBalancer)      │   │  │
│  │  │  - External access to API    │   │  │
│  │  └──────────────────────────────┘   │  │
│  │                 ↕                    │  │
│  │  ┌──────────────────────────────┐   │  │
│  │  │  HPA                         │   │  │
│  │  │  - CPU: 70% threshold        │   │  │
│  │  │  - Memory: 80% threshold     │   │  │
│  │  │  - Min: 3, Max: 10 replicas  │   │  │
│  │  └──────────────────────────────┘   │  │
│  │                 ↕                    │  │
│  │  ┌──────────────────────────────┐   │  │
│  │  │  PDB (Pod Disruption Budget) │   │  │
│  │  │  - Min Available: 2          │   │  │
│  │  └──────────────────────────────┘   │  │
│  │                                      │  │
│  └──────────────────────────────────────┘  │
│                                             │
└─────────────────────────────────────────────┘
         ↓         ↓         ↓
    PostgreSQL   Redis    Kafka
```

## Manifests

The following Kubernetes manifests are provided:

| File | Purpose |
|------|---------|
| `messaging-service-namespace.yaml` | Namespace isolation |
| `messaging-service-configmap.yaml` | Non-sensitive configuration |
| `messaging-service-secret.yaml` | Sensitive data (credentials, keys) |
| `messaging-service-serviceaccount.yaml` | RBAC service account and roles |
| `messaging-service-deployment.yaml` | Deployment specification |
| `messaging-service-service.yaml` | Internal and external services |
| `messaging-service-hpa.yaml` | Horizontal Pod Autoscaler |
| `messaging-service-pdb.yaml` | Pod Disruption Budget |

## Deployment Steps

### 1. Prepare the Cluster

```bash
# Create namespace
kubectl create namespace nova-messaging

# Set default namespace (optional)
kubectl config set-context --current --namespace=nova-messaging
```

### 2. Configure Secrets

**IMPORTANT**: Update sensitive values in `messaging-service-secret.yaml` before deployment.

```bash
# Edit the secret file with production values
vim messaging-service-secret.yaml
```

**Required updates:**
- `POSTGRES_PASSWORD`: Set secure database password
- `POSTGRES_DB`: Set database name (default: nova_messaging)
- `DATABASE_URL`: Update with actual PostgreSQL connection details
- `REDIS_PASSWORD`: Set Redis authentication password
- `REDIS_URL`: Update with actual Redis connection details
- `SECRETBOX_KEY_B64`: Generate 32-byte base64 key: `openssl rand -base64 32`
- `JWT_PUBLIC_KEY_PEM`: Copy public key from your JWT issuer
- `KAFKA_BROKERS`: Set Kafka broker addresses

### 3. Configure ConfigMap (Optional)

Edit `messaging-service-configmap.yaml` to adjust:
- `DATABASE_MAX_CONNECTIONS`: Connection pool size (default: 10)
- `REDIS_POOL_SIZE`: Redis connection pool (default: 20)
- `WS_MAX_FRAME_SIZE`: WebSocket frame size (default: 1MB)
- `VIDEO_CALL_MAX_DURATION_HOURS`: Max call duration (default: 12 hours)
- `MESSAGE_MAX_LENGTH`: Maximum message size (default: 4096 chars)

### 4. Deploy Manifests

```bash
# Apply in order (order matters for dependencies)

# 1. Namespace first
kubectl apply -f messaging-service-namespace.yaml

# 2. RBAC (service account must exist before deployment)
kubectl apply -f messaging-service-serviceaccount.yaml

# 3. ConfigMap and Secret
kubectl apply -f messaging-service-configmap.yaml
kubectl apply -f messaging-service-secret.yaml

# 4. Main deployment
kubectl apply -f messaging-service-deployment.yaml

# 5. Services
kubectl apply -f messaging-service-service.yaml

# 6. Autoscaling and availability
kubectl apply -f messaging-service-hpa.yaml
kubectl apply -f messaging-service-pdb.yaml
```

Or apply all at once:
```bash
kubectl apply -f . --namespace nova-messaging
```

### 5. Verify Deployment

```bash
# Check namespace
kubectl get namespace nova-messaging

# Check deployment status
kubectl get deployment messaging-service -n nova-messaging

# Check pods
kubectl get pods -n nova-messaging

# Check services
kubectl get svc -n nova-messaging

# Check HPA status
kubectl get hpa messaging-service-hpa -n nova-messaging

# Check events
kubectl get events -n nova-messaging --sort-by='.lastTimestamp'
```

### 6. Monitor Rollout

```bash
# Watch deployment progress
kubectl rollout status deployment/messaging-service -n nova-messaging

# Check replica status
kubectl get rs -n nova-messaging

# View pod logs
kubectl logs -n nova-messaging -l component=messaging-service -f --all-containers=true

# Check specific pod
kubectl logs <pod-name> -n nova-messaging
```

## Health Checks

The messaging service implements three types of health checks:

### Startup Probe
- **Path**: `/health`
- **Initial Delay**: 0s
- **Period**: 5s
- **Timeout**: 3s
- **Failure Threshold**: 30 (allows 150 seconds for startup)

### Readiness Probe
- **Path**: `/health`
- **Initial Delay**: 10s
- **Period**: 5s
- **Timeout**: 3s
- **Failure Threshold**: 2

### Liveness Probe
- **Path**: `/health`
- **Initial Delay**: 30s
- **Period**: 10s
- **Timeout**: 5s
- **Failure Threshold**: 3

## Resource Management

### Requests (Guaranteed)
```yaml
cpu: 500m
memory: 512Mi
```

### Limits (Maximum)
```yaml
cpu: 2000m
memory: 2Gi
```

### Auto-scaling Triggers
- **CPU**: 70% utilization → scale up
- **Memory**: 80% utilization → scale up
- **Min Replicas**: 3
- **Max Replicas**: 10

## Database Migrations

Database migrations run automatically via the init container before the service starts.

```bash
# Monitor migration progress
kubectl logs <pod-name> -n nova-messaging -c db-migrate

# Manual migration (if needed)
kubectl exec -it <pod-name> -n nova-messaging -- \
  migrate -path /migrations \
          -database "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME" \
          up
```

## Networking

### Internal Access
```bash
# Within cluster
http://messaging-service.nova-messaging:3000

# From other namespaces
http://messaging-service.nova-messaging.svc.cluster.local:3000
```

### External Access
```bash
# Get LoadBalancer IP
kubectl get svc messaging-service-external -n nova-messaging

# Connect via external IP
http://<EXTERNAL-IP>:3000
```

### Session Affinity
The service uses `ClientIP` session affinity with 3-hour timeout to ensure WebSocket clients connect to the same pod.

## Scaling

### Manual Scaling
```bash
# Scale to specific number of replicas
kubectl scale deployment messaging-service --replicas=5 -n nova-messaging

# View current replicas
kubectl get deployment messaging-service -n nova-messaging
```

### Auto-scaling Status
```bash
# Monitor HPA
kubectl describe hpa messaging-service-hpa -n nova-messaging

# Watch HPA decisions
kubectl get hpa messaging-service-hpa -n nova-messaging -w
```

## Updates and Rolling Deployment

### Update Image
```bash
# Update image
kubectl set image deployment/messaging-service \
  messaging-service=nova/messaging-service:v1.1.0 \
  -n nova-messaging

# Watch rollout
kubectl rollout status deployment/messaging-service -n nova-messaging

# Rollback if needed
kubectl rollout undo deployment/messaging-service -n nova-messaging
```

### Update Configuration
```bash
# Edit ConfigMap
kubectl edit configmap messaging-service-config -n nova-messaging

# Edit Secret
kubectl patch secret messaging-service-secret -n nova-messaging \
  -p='{"stringData":{"POSTGRES_PASSWORD":"new-password"}}'

# Restart pods to apply changes
kubectl rollout restart deployment/messaging-service -n nova-messaging
```

## Troubleshooting

### Pods not starting
```bash
# Check pod status
kubectl describe pod <pod-name> -n nova-messaging

# Check logs
kubectl logs <pod-name> -n nova-messaging --all-containers=true
```

### Database connection failures
```bash
# Verify secret is correct
kubectl get secret messaging-service-secret -n nova-messaging -o yaml

# Test database connectivity from pod
kubectl exec -it <pod-name> -n nova-messaging -- \
  psql -h postgres.nova-db -U postgres -d nova_messaging
```

### High memory usage
```bash
# Check memory usage
kubectl top pods -n nova-messaging

# Check if HPA is scaling
kubectl describe hpa messaging-service-hpa -n nova-messaging

# Increase limits if needed
kubectl edit deployment messaging-service -n nova-messaging
```

### WebSocket connection issues
```bash
# Check logs for WebSocket errors
kubectl logs <pod-name> -n nova-messaging | grep -i websocket

# Verify LoadBalancer service
kubectl get svc messaging-service-external -n nova-messaging

# Test connectivity
curl -i http://<EXTERNAL-IP>:3000/health
```

## Monitoring

### Prometheus Metrics
The service exposes Prometheus metrics on port 9090:

```bash
# Port-forward to local machine
kubectl port-forward svc/messaging-service 9090:9090 -n nova-messaging

# Access metrics at http://localhost:9090/metrics
```

### Key metrics
- `http_requests_total`: Total HTTP requests
- `http_request_duration_seconds`: Request latency
- `websocket_connections_active`: Active WebSocket connections
- `database_query_duration_seconds`: Database query latency
- `message_queue_length`: Pending messages in queue

## Security Considerations

### Pod Security
- ✅ Runs as non-root user (UID: 1001)
- ✅ Read-only root filesystem
- ✅ All Linux capabilities dropped
- ✅ No privilege escalation allowed

### Network Security
- ✅ Service accounts with minimal RBAC
- ✅ ConfigMaps for non-sensitive data
- ✅ Secrets (opaque) for sensitive data
- ✅ Session affinity prevents session hijacking

### Data Protection
- ✅ Database password in Secret
- ✅ Redis password in Secret
- ✅ JWT public key in Secret
- ✅ Encryption key (SECRETBOX_KEY_B64) in Secret

## Disaster Recovery

### Backup ConfigMap and Secret
```bash
# Backup current configuration
kubectl get configmap messaging-service-config -n nova-messaging -o yaml > backup-configmap.yaml
kubectl get secret messaging-service-secret -n nova-messaging -o yaml > backup-secret.yaml

# Restore if needed
kubectl apply -f backup-configmap.yaml
kubectl apply -f backup-secret.yaml
```

### Database Backup
```bash
# Backup PostgreSQL database
kubectl exec -it postgres-pod -n nova-db -- \
  pg_dump nova_messaging > nova_messaging_backup.sql

# Restore from backup
kubectl exec -i postgres-pod -n nova-db -- \
  psql nova_messaging < nova_messaging_backup.sql
```

## Performance Tuning

### Database Connection Pool
Adjust in ConfigMap:
```yaml
DATABASE_MAX_CONNECTIONS: "10"
DATABASE_POOL_TIMEOUT: "30"
DATABASE_IDLE_TIMEOUT: "600"
```

### Redis Connection Pool
```yaml
REDIS_POOL_SIZE: "20"
REDIS_CONNECT_TIMEOUT: "5"
REDIS_POOL_TIMEOUT: "10"
```

### WebSocket Settings
```yaml
WS_MAX_FRAME_SIZE: "1048576"  # 1MB
WS_MESSAGE_BUFFER_SIZE: "256"
```

### Kafka Settings
```yaml
KAFKA_COMPRESSION_TYPE: "snappy"
KAFKA_REQUEST_TIMEOUT_MS: "30000"
KAFKA_CONSUMER_GROUP: "messaging-service"
```

## Production Checklist

- [ ] Database credentials updated in Secret
- [ ] Redis password set securely
- [ ] JWT public key configured
- [ ] SECRETBOX_KEY_B64 generated (32 bytes)
- [ ] Kafka brokers configured correctly
- [ ] LoadBalancer IP/hostname configured in client apps
- [ ] Database backups configured
- [ ] Monitoring and alerting set up
- [ ] Log aggregation configured (e.g., ELK, Loki)
- [ ] Backup and recovery procedures tested
- [ ] Cluster backup policy defined
- [ ] Network policies configured (if required)

## Next Steps

1. **TURN Server Setup** (Optional but recommended for video calls)
   - Deploy coturn or similar TURN server
   - Configure TURN credentials in messaging service
   - Update WebRTC configuration in iOS client

2. **Ingress Configuration**
   - Configure ingress for API access
   - Set up TLS/SSL certificates
   - Configure domain names

3. **Monitoring Setup**
   - Install Prometheus
   - Configure Grafana dashboards
   - Set up alerting rules

4. **CI/CD Integration**
   - Configure GitOps (ArgoCD, Flux)
   - Set up automated deployments
   - Configure image registries

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubectl Cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Deployment Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [Pod Disruption Budgets](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
