# GraphQL Gateway Staging Deployment Guide

**Status**: ✅ Complete (P0-5)
**Environment**: Staging
**Replicas**: 2 (scales to 4)
**Load Balancer**: Ingress + NGINX

## Overview

This guide covers deploying the GraphQL Gateway to Kubernetes staging environment with:
- ✅ Kafka subscriptions integration
- ✅ Redis caching layer
- ✅ Rate limiting (100 req/sec per IP)
- ✅ Query complexity analysis
- ✅ Backpressure handling for subscriptions
- ✅ Horizontal Pod Autoscaling
- ✅ Network policies
- ✅ Prometheus monitoring

## Prerequisites

### Cluster Requirements
- Kubernetes 1.20+
- NGINX Ingress Controller
- Prometheus Operator (for monitoring)
- cert-manager (for TLS certificates)

### Services Required
- Kafka cluster (3 brokers)
- Redis (standalone or cluster)
- PostgreSQL database
- gRPC microservices (user-service, content-service, etc.)

### Configuration Files
```
k8s/staging/
├── graphql-gateway-namespace.yaml
├── graphql-gateway-deployment.yaml
├── graphql-gateway-service.yaml
├── graphql-gateway-configmap.yaml
├── graphql-gateway-hpa.yaml
├── graphql-gateway-networkpolicy.yaml
├── graphql-gateway-ingress.yaml
├── graphql-gateway-monitoring.yaml
└── DEPLOYMENT_GUIDE.md (this file)
```

## Deployment Steps

### 1. Prepare Secrets

First, create the base64-encoded secrets:

```bash
# Database URL
echo -n "postgres://user:password@postgres-db.cluster.local:5432/nova" | base64

# JWT secret (use a strong random value in production)
echo -n "your-staging-jwt-secret" | base64
```

Update the secret in `graphql-gateway-configmap.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: graphql-gateway-secrets
  namespace: nova-staging
data:
  database-url: <base64-encoded-value>
  jwt-secret: <base64-encoded-value>
```

### 2. Create Namespace and Resources

```bash
# Create namespace
kubectl apply -f k8s/staging/graphql-gateway-namespace.yaml

# Apply ConfigMap and Secrets
kubectl apply -f k8s/staging/graphql-gateway-configmap.yaml

# Apply RBAC (ServiceAccount, Role, RoleBinding)
kubectl apply -f k8s/staging/graphql-gateway-service.yaml

# Apply Deployment
kubectl apply -f k8s/staging/graphql-gateway-deployment.yaml

# Apply Service
kubectl apply -f k8s/staging/graphql-gateway-service.yaml

# Apply Network Policy
kubectl apply -f k8s/staging/graphql-gateway-networkpolicy.yaml

# Apply HPA and PDB
kubectl apply -f k8s/staging/graphql-gateway-hpa.yaml

# Apply Ingress
kubectl apply -f k8s/staging/graphql-gateway-ingress.yaml

# Apply Monitoring (if Prometheus Operator is available)
kubectl apply -f k8s/staging/graphql-gateway-monitoring.yaml
```

### 3. Verify Deployment

```bash
# Check namespace
kubectl get namespace nova-staging

# Check pods
kubectl get pods -n nova-staging -l app=graphql-gateway

# Check pod status
kubectl describe pod <pod-name> -n nova-staging

# Check logs
kubectl logs -n nova-staging -l app=graphql-gateway --tail=50 -f

# Check service
kubectl get svc -n nova-staging graphql-gateway

# Check ingress
kubectl get ingress -n nova-staging
```

### 4. Test Connectivity

```bash
# Port-forward to test
kubectl port-forward -n nova-staging svc/graphql-gateway 8000:80

# Test GraphQL endpoint
curl http://localhost:8000/graphql -X GET

# Test health check
curl http://localhost:8000/health

# Test schema endpoint
curl http://localhost:8000/schema
```

### 5. Verify Kafka Integration

```bash
# Get pod name
POD=$(kubectl get pod -n nova-staging -l app=graphql-gateway -o jsonpath='{.items[0].metadata.name}')

# Check logs for Kafka initialization
kubectl logs -n nova-staging $POD | grep -i kafka

# Expected output:
# "Subscribed to Kafka topics: ["feed.events", "messaging.events", "notification.events"]"
```

### 6. Test Subscriptions

```bash
# WebSocket connection
wscat -c "ws://localhost:8000/graphql"

# Send subscription
{"type":"start","payload":{"query":"subscription { feedUpdated { id content } }"}}
```

## Configuration

### Environment Variables

All configuration is managed via ConfigMap. Key settings:

```yaml
# Kafka
KAFKA_BROKERS: kafka broker addresses (comma-separated)
KAFKA_GROUP_ID: graphql-gateway-staging
KAFKA_TIMEOUT_MS: 5000
KAFKA_AUTO_OFFSET_RESET: earliest

# Redis
REDIS_URL: redis://redis:6379

# Rate Limiting
RATE_LIMIT_RPS: 200      # Requests per second
RATE_LIMIT_BURST: 20     # Burst size

# Query Complexity
MAX_QUERY_COMPLEXITY: 1000
MAX_QUERY_DEPTH: 10
MAX_QUERY_WIDTH: 50

# Subscriptions
SUBSCRIPTION_BACKPRESSURE_QUEUE_SIZE: 10000
SUBSCRIPTION_WARNING_THRESHOLD: 75  # %
SUBSCRIPTION_CRITICAL_THRESHOLD: 95 # %
```

### Resource Limits

```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 1Gi
```

Adjust based on load testing results.

## Scaling

### Horizontal Scaling

The HPA automatically scales 2-4 replicas based on:
- CPU usage > 70%
- Memory usage > 80%

```bash
# Check HPA status
kubectl get hpa -n nova-staging graphql-gateway

# Manual scaling if needed
kubectl scale deployment graphql-gateway --replicas=3 -n nova-staging
```

### Vertical Scaling

If pods are consistently hitting limits:

1. Increase resource requests/limits in deployment
2. Restart deployment

```bash
kubectl rollout restart deployment/graphql-gateway -n nova-staging
```

## Monitoring

### View Metrics

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring prometheus-0 9090:9090

# Visit http://localhost:9090
# Query: graphql_request_duration_seconds
```

### Check Alerts

```bash
# View Prometheus alerts
kubectl get prometheusrules -n nova-staging

# Describe alert rule
kubectl describe prometheusrule graphql-gateway -n nova-staging
```

### Common Metrics

```
# Request rate (per minute)
rate(graphql_requests_total[1m])

# Error rate
rate(graphql_errors_total[1m]) / rate(graphql_requests_total[1m])

# p95 latency
histogram_quantile(0.95, rate(graphql_request_duration_seconds_bucket[5m]))

# Rate limit violations
rate(rate_limit_exceeded_total[5m])

# Kafka consumer lag
kafka_consumer_lag

# Active subscriptions
ws_active_connections
```

## Troubleshooting

### Pods Not Starting

```bash
kubectl describe pod <pod-name> -n nova-staging

# Check for:
# - Image pull errors
# - Resource constraints
# - Init container failures
# - Kubernetes node resources
```

### Kafka Connection Issues

```bash
# Check pod logs
kubectl logs -n nova-staging <pod-name> | grep -i kafka

# Verify Kafka brokers are reachable
kubectl exec -it <pod-name> -n nova-staging -- \
  nc -zv kafka-broker-0.kafka-headless.nova-staging.svc.cluster.local 9092
```

### Redis Connection Issues

```bash
# Check Redis connectivity
kubectl exec -it <pod-name> -n nova-staging -- \
  redis-cli -h redis.nova-staging.svc.cluster.local ping

# Check Redis resources
kubectl get pod -n nova-staging -l app=redis -o wide
```

### High Latency

1. Check resource usage:
```bash
kubectl top pod -n nova-staging -l app=graphql-gateway
```

2. Check query complexity:
```bash
kubectl logs -n nova-staging <pod-name> | grep -i "complexity"
```

3. Check Kafka consumer lag:
```bash
# In pod
kafka-consumer-groups --bootstrap-server kafka:9092 \
  --group graphql-gateway-staging --describe
```

### Memory Leaks

```bash
# Monitor memory growth
kubectl top pod -n nova-staging -l app=graphql-gateway --use-protocol-buffers

# Check for subscription memory leaks
kubectl logs -n nova-staging <pod-name> | grep -i "memory\|leak"
```

## Updates & Rollout

### Rolling Update

```bash
# Update image
kubectl set image deployment/graphql-gateway \
  graphql-gateway=nova/graphql-gateway:v0.2.0 \
  -n nova-staging

# Monitor rollout
kubectl rollout status deployment/graphql-gateway -n nova-staging

# Undo if needed
kubectl rollout undo deployment/graphql-gateway -n nova-staging
```

### Configuration Update

```bash
# Update ConfigMap
kubectl edit configmap graphql-gateway-config -n nova-staging

# Restart deployment to apply changes
kubectl rollout restart deployment/graphql-gateway -n nova-staging

# Monitor restart
kubectl get pods -n nova-staging -l app=graphql-gateway -w
```

## Security

### Network Policies

Defined in `graphql-gateway-networkpolicy.yaml`:
- Ingress: Allow from Ingress controller, Prometheus, Jaeger
- Egress: Allow to Kafka, Redis, PostgreSQL, DNS

Verify:
```bash
kubectl get networkpolicy -n nova-staging

kubectl describe networkpolicy graphql-gateway -n nova-staging
```

### RBAC

Service Account with minimal permissions:
- Read ConfigMaps
- Read Secrets

```bash
kubectl get role,rolebinding -n nova-staging -l app=graphql-gateway
```

### Secrets

Store sensitive data in Kubernetes Secrets:
- Database URL
- JWT secret
- API keys

Never commit secrets to Git.

## Performance Tuning

### Load Testing

Use k6 to validate staging deployment:

```bash
# Run load test against staging
BASE_URL=https://api.staging.example.com k6 run k6/load-test-graphql.js

# Run subscription test
WS_ENDPOINT=wss://api.staging.example.com k6 run k6/load-test-subscriptions.js
```

### Optimization Checklist

- [ ] Kafka consumer lag < 1000 messages
- [ ] p95 latency < 500ms
- [ ] Error rate < 1%
- [ ] Rate limiting working (test with >100 req/sec)
- [ ] Subscription backpressure functioning
- [ ] Cache hit rate > 50% for feed
- [ ] Memory usage stable (no leaks)
- [ ] CPU usage < 70% at baseline load

## Cleanup

To completely remove deployment:

```bash
# Delete all resources
kubectl delete namespace nova-staging

# Or selectively
kubectl delete deployment graphql-gateway -n nova-staging
kubectl delete service graphql-gateway -n nova-staging
kubectl delete ingress graphql-gateway -n nova-staging
kubectl delete configmap graphql-gateway-config -n nova-staging
kubectl delete secret graphql-gateway-secrets -n nova-staging
```

## Next Steps

After successful staging deployment:

1. **Load Testing**: Run comprehensive k6 tests
2. **Chaos Testing**: Test failure scenarios
3. **Security Audit**: Review network policies, RBAC, secrets
4. **Documentation**: Update runbooks for operations
5. **Production Deployment**: Adapt manifests for production (higher replicas, limits)

## References

- [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Ingress Configuration](https://kubernetes.io/docs/concepts/services-networking/ingress/)
