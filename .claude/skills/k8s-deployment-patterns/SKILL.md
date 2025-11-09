---
name: k8s-deployment-patterns
description: Master Kubernetes deployment patterns for production microservices including resource management, auto-scaling, and health checks. Use when creating K8s manifests, optimizing deployments, or troubleshooting production issues.
---

# Kubernetes Deployment Patterns

Production-ready Kubernetes configurations for Rust microservices.

## When to Use This Skill

- Creating Deployment manifests
- Configuring resource limits and requests
- Setting up health probes
- Implementing auto-scaling (HPA)
- Managing ConfigMaps and Secrets
- Troubleshooting deployment issues

## Essential Patterns

### Pattern 1: Production Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: production
  labels:
    app: user-service
    version: v1.0.0
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Zero-downtime
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
        version: v1.0.0
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: user-service
        image: registry.example.com/user-service:v1.0.0
        ports:
        - name: grpc
          containerPort: 50051
          protocol: TCP
        - name: metrics
          containerPort: 9090
          protocol: TCP

        # Resource Management
        resources:
          requests:
            cpu: 100m        # Minimum CPU
            memory: 128Mi    # Minimum memory
          limits:
            cpu: 500m        # Maximum CPU
            memory: 512Mi    # Maximum memory

        # Health Checks
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2

        startupProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 30

        # Environment Variables
        env:
        - name: RUST_LOG
          value: "info"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: user-service-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            configMapKeyRef:
              name: user-service-config
              key: redis-url

        # Graceful Shutdown
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 15"]

      # Security Context
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000

      # Node Scheduling
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: user-service
              topologyKey: kubernetes.io/hostname
```

### Pattern 2: Horizontal Pod Autoscaling

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: user-service-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: user-service
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
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 60
      selectPolicy: Max
```

### Pattern 3: Service Configuration

```yaml
apiVersion: v1
kind: Service
metadata:
  name: user-service
  namespace: production
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
```

### Pattern 4: ConfigMap & Secrets

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: user-service-config
  namespace: production
data:
  redis-url: "redis://redis-master:6379"
  log-level: "info"
  max-connections: "100"

---
apiVersion: v1
kind: Secret
metadata:
  name: user-service-secrets
  namespace: production
type: Opaque
data:
  database-url: <base64-encoded>
  jwt-secret: <base64-encoded>
```

### Pattern 5: Pod Disruption Budget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: user-service-pdb
  namespace: production
spec:
  minAvailable: 2  # At least 2 pods must be available
  selector:
    matchLabels:
      app: user-service
```

### Pattern 6: Resource Quotas

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    pods: "50"
```

## Best Practices

1. **Always set resource requests and limits**
2. **Implement all three health probes** (liveness, readiness, startup)
3. **Use HPA for production** workloads
4. **Enable Pod Disruption Budgets** for high availability
5. **Use anti-affinity** to spread pods across nodes
6. **Set graceful termination** period (30-60s)
7. **Never run as root**
8. **Use immutable tags** for images (not `:latest`)
9. **Enable Prometheus scraping** annotations
10. **Implement circuit breakers** in application code

## Sizing Guidelines

| Service Load | Requests (CPU/Mem) | Limits (CPU/Mem) |
|-------------|-------------------|------------------|
| Low | 50m / 64Mi | 200m / 256Mi |
| Medium | 100m / 128Mi | 500m / 512Mi |
| High | 200m / 256Mi | 1000m / 1Gi |

## Troubleshooting Commands

```bash
# Check pod status
kubectl get pods -n production

# View pod logs
kubectl logs -f user-service-xxx -n production

# Describe pod for events
kubectl describe pod user-service-xxx -n production

# Check resource usage
kubectl top pods -n production

# View HPA status
kubectl get hpa -n production

# Force pod deletion
kubectl delete pod user-service-xxx --force --grace-period=0
```

## Resources

- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Health Checks](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
