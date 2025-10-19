# Deployment Quick Reference

**All 4 production fixes are fully compatible with Docker and Kubernetes deployments!**

---

## 🐳 Docker Deployment

### Quick Start (Local Development)

```bash
# Build image
docker build -t nova-api:latest backend/

# Run with environment variables
docker run -p 8080:8080 \
  -e APP_ENV=development \
  -e DATABASE_URL=postgres://user:pass@postgres:5432/nova \
  -e REDIS_URL=redis://redis:6379 \
  -e JWT_PRIVATE_KEY_PEM="$(cat private.pem | base64)" \
  -e JWT_PUBLIC_KEY_PEM="$(cat public.pem | base64)" \
  -e CORS_ALLOWED_ORIGINS="http://localhost:3000" \
  nova-api:latest
```

### Docker Compose (Full Stack)

```bash
# All environment variables are in docker-compose.yml
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f nova-api

# Stop everything
docker-compose down
```

### Environment Variables for Docker

All 4 fixes use environment variables - no code changes needed:

```bash
# 1. JWT Keys (FIXED: no longer hardcoded)
JWT_PRIVATE_KEY_PEM="base64-encoded-private-key"
JWT_PUBLIC_KEY_PEM="base64-encoded-public-key"
JWT_SECRET="your-secret-key"

# 2. JWT Middleware (FIXED: now enforces authentication)
# Automatically applied to /posts endpoints
# No configuration needed

# 3. CORS Configuration (FIXED: now configurable)
CORS_ALLOWED_ORIGINS="https://nova.app,https://www.nova.app"
CORS_MAX_AGE="3600"

# 4. All environment variables for testing
DATABASE_URL="postgres://postgres:postgres@localhost:5432/nova_test"
REDIS_URL="redis://localhost:6379"
# ... other vars
```

---

## ☸️ Kubernetes Deployment

### Prerequisites

```bash
# 1. Ensure kubectl is configured
kubectl cluster-info

# 2. Create namespace
kubectl apply -f k8s/namespace.yaml

# 3. Deploy all resources with Kustomize
kubectl apply -k k8s/
```

### Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n nova

# Check services
kubectl get svc -n nova

# Check ingress (for DNS)
kubectl get ingress -n nova

# Check HPA (autoscaling)
kubectl get hpa -n nova
```

### File Structure

```
nova/
├── k8s/
│   ├── namespace.yaml          # Isolated namespace
│   ├── secret.yaml             # 🔐 Secrets (JWT keys, passwords)
│   ├── configmap.yaml          # 📋 Config (non-sensitive)
│   ├── redis.yaml              # Cache layer
│   ├── postgres.yaml           # Database with persistence
│   ├── deployment.yaml         # Application (3 replicas + HPA)
│   ├── ingress.yaml            # HTTPS endpoint
│   ├── rbac.yaml               # Service account & roles
│   ├── hpa.yaml                # Auto-scaling
│   ├── kustomization.yaml      # Deploy all at once
│   └── DEPLOYMENT_GUIDE.md     # Full guide
├── docker-compose.yml          # Local development stack
├── backend/Dockerfile          # Multi-stage build
└── DEPLOYMENT_QUICK_REFERENCE.md  # This file
```

---

## 🔐 Secret Management Comparison

| Aspect | Docker | K8s |
|--------|--------|-----|
| **Storage** | Environment vars | Secret objects |
| **Encryption at Rest** | ❌ Not default | ✅ Configurable |
| **Rotation** | Manual | Automated |
| **Audit** | ❌ Limited | ✅ Full audit trail |
| **Best For** | Development | Production |

### Docker: Use `.env` Files

```bash
# Create .env.local
DATABASE_URL=postgres://...
JWT_PRIVATE_KEY_PEM=...
CORS_ALLOWED_ORIGINS=http://localhost:3000
```

```bash
# Run with env file
docker run --env-file .env.local nova-api:latest
```

### K8s: Use Secret Objects

```bash
# Create secret from file
kubectl create secret generic nova-secrets \
  --from-literal=JWT_PRIVATE_KEY_PEM="$(cat private.pem | base64)" \
  --from-literal=JWT_PUBLIC_KEY_PEM="$(cat public.pem | base64)" \
  -n nova
```

---

## 📋 Configuration Checklist

### Before Docker Deployment

- [ ] **JWT Keys**: Generate RSA keypair
  ```bash
  openssl genpkey -algorithm RSA -out private.pem -pkeyopt rsa_keygen_bits:2048
  openssl pkey -in private.pem -pubout -out public.pem
  ```

- [ ] **Environment Variables**: Create `.env` file
  ```bash
  cp backend/.env.example backend/.env.local
  # Edit with your values
  ```

- [ ] **Database**: Configure PostgreSQL connection
  ```bash
  DATABASE_URL=postgres://user:pass@localhost:5432/nova
  ```

- [ ] **Redis**: Configure Redis connection
  ```bash
  REDIS_URL=redis://localhost:6379
  ```

- [ ] **CORS**: Set allowed origins
  ```bash
  CORS_ALLOWED_ORIGINS="http://localhost:3000,http://localhost:3001"
  ```

### Before K8s Deployment

- [ ] **Secrets**: Update `k8s/secret.yaml` with production values
- [ ] **ConfigMap**: Update `k8s/configmap.yaml` with your domains
- [ ] **Ingress**: Set correct hostnames in `k8s/ingress.yaml`
- [ ] **Registry**: Update image name in `k8s/kustomization.yaml`
- [ ] **Replicas**: Adjust `replicas: 3` in `k8s/deployment.yaml` if needed
- [ ] **Storage**: Configure PVC size in `k8s/postgres.yaml`

---

## 🚀 Common Commands

### Docker Commands

```bash
# Build image
docker build -t nova-api:v1.0 backend/

# Run container
docker run -p 8080:8080 --env-file .env.local nova-api:v1.0

# View logs
docker logs -f <container-id>

# Execute command in container
docker exec -it <container-id> /app/user-service healthcheck

# Stop container
docker stop <container-id>
```

### Docker Compose Commands

```bash
# Start all services
docker-compose up -d

# View logs for specific service
docker-compose logs -f nova-api

# Stop specific service
docker-compose stop nova-api

# Remove all containers and volumes
docker-compose down -v

# Execute command in running container
docker-compose exec nova-api /app/user-service healthcheck
```

### K8s Commands

```bash
# Deploy
kubectl apply -k k8s/

# Check status
kubectl get all -n nova

# View logs
kubectl logs -f deployment/nova-api -n nova

# Execute command in pod
kubectl exec -it <pod-name> -n nova -- /app/user-service healthcheck

# Port forward for local testing
kubectl port-forward svc/nova-api 8080:8080 -n nova

# Check resource usage
kubectl top pods -n nova

# Update deployment
kubectl set image deployment/nova-api nova-api=registry/nova-api:v1.1 -n nova

# Rollback
kubectl rollout undo deployment/nova-api -n nova
```

---

## 🔄 Environment-Specific Configs

### Development

```bash
# docker-compose.yml
APP_ENV: development
RUST_LOG: debug
CORS_ALLOWED_ORIGINS: "http://localhost:*"

# Tests can connect directly
DATABASE_URL: postgres://postgres:postgres@postgres:5432/nova_test
```

### Staging

```bash
# k8s/configmap.yaml
APP_ENV: staging
RUST_LOG: info
CORS_ALLOWED_ORIGINS: "https://staging.nova.app"

# Replicas for HA
replicas: 2
```

### Production

```bash
# k8s/secret.yaml + k8s/configmap.yaml
APP_ENV: production
RUST_LOG: warn
CORS_ALLOWED_ORIGINS: "https://nova.app,https://www.nova.app"

# Full redundancy
replicas: 5-10 (auto-scaled)
maxReplicas: 20
```

---

## 📊 Scaling Examples

### Docker Compose: Manual Scaling

```bash
# Scale service to 3 instances
docker-compose up --scale nova-api=3 -d

# Note: Requires load balancer (use Traefik or nginx)
```

### K8s: Automatic Scaling

```bash
# Automatically scales 3-10 replicas based on:
# - CPU > 70%
# - Memory > 80%

# Manually scale
kubectl scale deployment nova-api --replicas=5 -n nova

# Check current scaling
kubectl get hpa -n nova
```

---

## 🧪 Testing Deployments

### Health Check

```bash
# Docker
curl http://localhost:8080/api/v1/health

# K8s (port forward)
kubectl port-forward svc/nova-api 8080:8080 -n nova
curl http://localhost:8080/api/v1/health
```

### JWT Authentication (All fixed!)

```bash
# 1. Login (get token)
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password"}'

# Response: { "access_token": "...", "refresh_token": "..." }

# 2. Use token (middleware will verify)
curl -X GET http://localhost:8080/api/v1/posts \
  -H "Authorization: Bearer <token>"

# 3. Invalid token returns 401 (middleware protection)
curl -X GET http://localhost:8080/api/v1/posts \
  -H "Authorization: Bearer invalid"
# Returns: 401 Unauthorized
```

### CORS Testing

```bash
# Development (allows localhost)
curl -X OPTIONS http://localhost:8080/api/v1/posts \
  -H "Origin: http://localhost:3000" \
  -v

# Production (whitelist only)
curl -X OPTIONS https://api.nova.app/api/v1/posts \
  -H "Origin: https://nova.app" \
  -v

# Invalid origin returns no CORS headers
curl -X OPTIONS https://api.nova.app/api/v1/posts \
  -H "Origin: https://attacker.com" \
  -v
```

---

## 📈 Performance & Monitoring

### Docker: View Metrics

```bash
# CPU and memory usage
docker stats

# Inspect container
docker inspect <container-id>

# View resource limits
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.MemoryLimit}}\t{{.CPUs}}"
```

### K8s: View Metrics

```bash
# Pod resource usage (requires metrics-server)
kubectl top pods -n nova

# Node resource usage
kubectl top nodes

# Watch pod auto-scaling
kubectl get hpa -n nova -w

# View pod logs over time
kubectl logs deployment/nova-api -n nova --all-containers=true -f
```

---

## 🔄 Updates & Deployments

### Docker: Rolling Update

```bash
# Build new version
docker build -t nova-api:v1.1 backend/

# Update docker-compose.yml
# Change image: nova-api:v1.0 → nova-api:v1.1

# Restart
docker-compose up -d

# Verify
docker-compose ps
```

### K8s: Rolling Update

```bash
# Update image in kustomization.yaml
# newTag: v1.0 → v1.1

# Apply
kubectl apply -k k8s/

# Monitor rollout
kubectl rollout status deployment/nova-api -n nova -w

# Rollback if needed
kubectl rollout undo deployment/nova-api -n nova
```

---

## ✅ All 4 Fixes Are Deployment-Ready

| Fix | Docker | K8s | Notes |
|-----|--------|-----|-------|
| **1. JWT Keys → Env Vars** | ✅ | ✅ | Set `JWT_*` env vars |
| **2. JWT Middleware** | ✅ | ✅ | No config needed (automatic) |
| **3. CORS Whitelist** | ✅ | ✅ | Set `CORS_ALLOWED_ORIGINS` |
| **4. Test Environment** | ✅ | ✅ | Use `TESTING_SETUP.md` |

**No code changes required** - all fixes use environment variables!

---

## 📞 Deployment Support

- **Docker Issues**: Check `docker-compose.yml` and `.env` files
- **K8s Issues**: Check pod logs with `kubectl logs`
- **Network Issues**: Verify DNS and ingress configuration
- **Performance Issues**: Check resource requests/limits

---

**Status**: ✅ PRODUCTION READY
**Generated**: October 17, 2024
**Compatibility**: ✅ All 4 fixes fully compatible
