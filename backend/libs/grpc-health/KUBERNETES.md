# Kubernetes Health Check Configuration

Complete guide for configuring gRPC health probes in Kubernetes.

## Prerequisites

- Kubernetes 1.24+ (native gRPC probe support)
- Service implementing grpc.health.v1.Health

## Probe Types

### 1. Startup Probe
**Purpose**: Allow slow-starting services to initialize without being killed

```yaml
startupProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 0
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 30  # 30 × 5s = 150s max startup time
```

**When to use**:
- Services with slow initialization (loading models, warming caches)
- Database migrations during startup
- First-time setup operations

**Behavior**:
- Other probes disabled until this succeeds
- Pod killed if it fails
- Only runs once at startup

### 2. Liveness Probe
**Purpose**: Detect and restart unhealthy/deadlocked services

```yaml
livenessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 15
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3  # Restart after 3 consecutive failures (30s)
```

**When to use**:
- Detect deadlocks
- Detect memory leaks
- Detect unrecoverable errors

**Behavior**:
- Pod restarted if it fails
- Should be conservative (avoid false positives)

### 3. Readiness Probe
**Purpose**: Control traffic routing to healthy pods

```yaml
readinessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 2  # Remove from service after 2 consecutive failures (10s)
```

**When to use**:
- Dependency health checks
- Temporary overload conditions
- Graceful shutdown

**Behavior**:
- Pod removed from Service endpoints if it fails
- Pod NOT restarted
- Can recover without restart

## Complete Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: nova
  labels:
    app: user-service
    version: v2.0.0
spec:
  replicas: 3
  revisionHistoryLimit: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Zero-downtime deployment

  selector:
    matchLabels:
      app: user-service

  template:
    metadata:
      labels:
        app: user-service
        version: v2.0.0
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
        prometheus.io/path: "/metrics"

    spec:
      # Service account for RBAC
      serviceAccountName: user-service

      # Security context
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000

      # Termination grace period
      terminationGracePeriodSeconds: 30

      containers:
      - name: user-service
        image: nova/user-service:v2.0.0
        imagePullPolicy: IfNotPresent

        ports:
        - containerPort: 50051
          name: grpc
          protocol: TCP
        - containerPort: 9090
          name: metrics
          protocol: TCP

        env:
        - name: RUST_LOG
          value: "info,user_service=debug"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: database-secrets
              key: postgres-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: cache-secrets
              key: redis-url
        - name: KAFKA_BROKERS
          value: "kafka-0.kafka-headless:9092,kafka-1.kafka-headless:9092"
        - name: GRPC_PORT
          value: "50051"
        - name: METRICS_PORT
          value: "9090"

        # Resource limits
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"

        # Startup Probe
        startupProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 30
          successThreshold: 1

        # Liveness Probe
        livenessProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 15
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
          successThreshold: 1

        # Readiness Probe
        readinessProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2
          successThreshold: 1

        # Security context
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL

        # Volume mounts
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /app/cache

      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}

---
apiVersion: v1
kind: Service
metadata:
  name: user-service
  namespace: nova
  labels:
    app: user-service
spec:
  type: ClusterIP
  selector:
    app: user-service
  ports:
  - name: grpc
    port: 50051
    targetPort: 50051
    protocol: TCP
  - name: metrics
    port: 9090
    targetPort: 9090
    protocol: TCP
  sessionAffinity: None

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: user-service
  namespace: nova
```

## Probe Configuration Guidelines

### Startup Probe

| Parameter | Recommended | Why |
|-----------|-------------|-----|
| `initialDelaySeconds` | 0 | Start checking immediately |
| `periodSeconds` | 5-10 | Balance between responsiveness and overhead |
| `timeoutSeconds` | 3-5 | Allow for network latency |
| `failureThreshold` | 20-60 | Total time = period × threshold |

**Formula**: `maxStartupTime = periodSeconds × failureThreshold`

### Liveness Probe

| Parameter | Recommended | Why |
|-----------|-------------|-----|
| `initialDelaySeconds` | 10-30 | Wait for startup probe to succeed |
| `periodSeconds` | 10-30 | Avoid unnecessary restarts |
| `timeoutSeconds` | 5-10 | Account for slow health checks |
| `failureThreshold` | 3-5 | Multiple failures before restart |

**Formula**: `restartDelay = periodSeconds × failureThreshold`

### Readiness Probe

| Parameter | Recommended | Why |
|-----------|-------------|-----|
| `initialDelaySeconds` | 0-10 | Can start after startup probe |
| `periodSeconds` | 5-10 | Quick traffic routing decisions |
| `timeoutSeconds` | 3-5 | Fast failure detection |
| `failureThreshold` | 2-3 | Quick removal from endpoints |

**Formula**: `trafficRemovalDelay = periodSeconds × failureThreshold`

## Service-Specific Checks

By default, gRPC health probes check the overall service health (empty string).
You can check specific services:

```yaml
readinessProbe:
  grpc:
    port: 50051
    service: "user_service.UserService"  # Specific service
```

## Troubleshooting

### Pods Keep Restarting

**Symptoms**:
```bash
$ kubectl get pods
NAME                            READY   STATUS    RESTARTS   AGE
user-service-5d8f7b9c4d-abc12   0/1     Running   5          2m
```

**Diagnosis**:
```bash
# Check probe failures
kubectl describe pod user-service-5d8f7b9c4d-abc12 | grep -A 10 "Liveness\|Readiness"

# Check logs
kubectl logs user-service-5d8f7b9c4d-abc12

# Previous container logs (before restart)
kubectl logs user-service-5d8f7b9c4d-abc12 --previous
```

**Solutions**:
1. Increase `failureThreshold`
2. Increase `timeoutSeconds`
3. Increase `periodSeconds`
4. Check dependency availability (DB, Redis, Kafka)

### Pods Not Ready

**Symptoms**:
```bash
$ kubectl get pods
NAME                            READY   STATUS    RESTARTS   AGE
user-service-5d8f7b9c4d-abc12   0/1     Running   0          5m
```

**Diagnosis**:
```bash
# Check readiness probe
kubectl describe pod user-service-5d8f7b9c4d-abc12 | grep -A 10 "Readiness"

# Check service endpoints
kubectl get endpoints user-service

# Test health manually
kubectl exec -it user-service-5d8f7b9c4d-abc12 -- \
  grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check
```

**Solutions**:
1. Check dependency health (DB, Redis, Kafka)
2. Verify network connectivity
3. Check resource limits (CPU/memory throttling)
4. Review application logs

### Slow Rollouts

**Symptoms**:
```bash
$ kubectl rollout status deployment/user-service
Waiting for deployment "user-service" rollout to finish: 1 out of 3 new replicas have been updated...
```

**Diagnosis**:
```bash
# Check pod status
kubectl get pods -l app=user-service -w

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp
```

**Solutions**:
1. Reduce `startupProbe.failureThreshold` if startup is fast
2. Adjust `rollingUpdate.maxSurge` and `maxUnavailable`
3. Ensure sufficient cluster resources

## Monitoring

### Prometheus Queries

```promql
# Probe success rate
rate(kube_pod_status_ready{pod=~"user-service.*"}[5m])

# Restart count
kube_pod_container_status_restarts_total{pod=~"user-service.*"}

# Time in not-ready state
kube_pod_status_ready{pod=~"user-service.*", condition="false"}
```

### Alerts

```yaml
groups:
- name: health_checks
  rules:
  - alert: PodNotReady
    expr: kube_pod_status_ready{condition="false"} > 0
    for: 5m
    annotations:
      summary: "Pod {{ $labels.pod }} not ready for 5 minutes"

  - alert: HighRestartRate
    expr: rate(kube_pod_container_status_restarts_total[15m]) > 0.1
    for: 5m
    annotations:
      summary: "Pod {{ $labels.pod }} restarting frequently"
```

## Best Practices

### 1. Use All Three Probes

- **Startup**: For slow initialization
- **Liveness**: For deadlock detection
- **Readiness**: For traffic routing

### 2. Set Realistic Timeouts

```yaml
# BAD: Too aggressive
livenessProbe:
  periodSeconds: 5
  failureThreshold: 1  # Will restart on any hiccup

# GOOD: Conservative
livenessProbe:
  periodSeconds: 10
  failureThreshold: 3  # Allows temporary issues
```

### 3. Separate Liveness and Readiness Logic

- **Liveness**: Check if process is alive (should always succeed unless deadlocked)
- **Readiness**: Check if dependencies are healthy (can fail temporarily)

### 4. Test Probes Before Production

```bash
# Local testing with kind
kind create cluster
kubectl apply -f deployment.yaml
kubectl get pods -w
```

### 5. Monitor Probe Success Rates

Set up dashboards to track:
- Probe success/failure rates
- Pod restart counts
- Time to ready
- Deployment rollout duration

## Migration from TCP Probes

### Before (TCP)

```yaml
livenessProbe:
  tcpSocket:
    port: 50051
  initialDelaySeconds: 30
  periodSeconds: 10
```

### After (gRPC)

```yaml
startupProbe:
  grpc:
    port: 50051
  periodSeconds: 5
  failureThreshold: 30

livenessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 15
  periodSeconds: 10

readinessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 5
  periodSeconds: 5
```

**Benefits**:
- ✅ Accurate health status (not just port open)
- ✅ Dependency health checks
- ✅ Faster failure detection
- ✅ Separate startup/liveness/readiness logic

## Advanced Configuration

### Custom Service Health

```rust
// In your service code
health_manager.lock().await.reporter.set_service_status(
    "user_service.UserService",
    tonic_health::ServingStatus::NotServing,
).await;
```

```yaml
# In Kubernetes
readinessProbe:
  grpc:
    port: 50051
    service: "user_service.UserService"
```

### Multiple Services in One Pod

```yaml
# Check different services for different probes
livenessProbe:
  grpc:
    port: 50051
    service: ""  # Overall health

readinessProbe:
  grpc:
    port: 50051
    service: "user_service.UserService"  # Specific service
```

## References

- [Kubernetes gRPC Health Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-grpc-liveness-probe)
- [gRPC Health Checking Protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md)
- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
