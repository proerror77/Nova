# Kubernetes Configuration Migration Plan - V1 to V2

**Date**: 2025-11-11
**Status**: In Progress
**Purpose**: Update K8s configurations for V2 architecture migration

## Architecture Changes Summary

### Services to Remove (V1 → Archived)
- `auth-service` → replaced by `identity-service`
- `feed-service` → merged into `social-service`
- `messaging-service` → merged into `communication-service`
- `notification-service` → merged into `communication-service`
- `video-service` → merged into `media-service`
- `streaming-service` → merged into `media-service`
- `cdn-service` → merged into `media-service`

### Services to Update
- `graphql-gateway` (V2 version, stateless)
- `user-service` (reduced scope - profiles only)
- `content-service` (unchanged)
- `media-service` (expanded scope)
- `search-service` (unchanged)
- `events-service` (new - if not exists)

### New Services to Add
- `identity-service` (complete auth domain)
- `social-service` (feed + follows + likes)
- `communication-service` (messaging + notifications + email)

## File Changes Required

### 1. Delete V1 Service Files
```bash
# Auth Service (replaced by identity-service)
k8s/microservices/auth-service-*.yaml
k8s/infrastructure/base/auth-service.yaml
k8s/base/auth-service-deployment-externalsecrets.yaml

# Feed Service (merged into social-service)
k8s/microservices/feed-service-*.yaml
k8s/infrastructure/base/feed-service.yaml
k8s/infrastructure/overlays/staging/feed-service-env-patch.yaml

# Messaging Service (merged into communication-service)
k8s/microservices/messaging-service-*.yaml
k8s/infrastructure/base/messaging-service.yaml
k8s/infrastructure/overlays/staging/messaging-service-*.yaml

# Streaming Service (merged into media-service)
k8s/infrastructure/base/streaming-service.yaml
k8s/infrastructure/overlays/staging/streaming-service-env-patch.yaml

# Note: notification-service, video-service, cdn-service files not found (may already be removed)
```

### 2. Update Existing Services

#### GraphQL Gateway
- Update to V2 stateless version
- Remove any database connection configurations
- Update environment variables for new service endpoints

Files to update:
- `k8s/graphql-gateway/deployment.yaml`
- `k8s/staging/graphql-gateway-deployment.yaml`
- `k8s/staging/graphql-gateway-configmap.yaml`
- `k8s/microservices/api-gateway/deployment.yaml`

#### User Service
- Update scope documentation
- Ensure only profile-related environment variables
- Remove auth-related configurations

Files to update:
- `k8s/microservices/user-service-deployment.yaml`
- `k8s/infrastructure/base/user-service.yaml`
- `k8s/microservices/user-service-configmap.yaml`

#### Media Service
- Expand configuration for video/streaming/CDN functionality
- Add additional storage configurations
- Update resource limits

Files to update:
- `k8s/microservices/media-service-deployment.yaml`
- `k8s/infrastructure/base/media-service.yaml`

### 3. Create New V2 Services

#### Identity Service (NEW)
Create files:
- `k8s/microservices/identity-service-deployment.yaml`
- `k8s/microservices/identity-service-service.yaml`
- `k8s/microservices/identity-service-configmap.yaml`
- `k8s/microservices/identity-service-secret.yaml`
- `k8s/microservices/identity-service-hpa.yaml`
- `k8s/microservices/identity-service-pdb.yaml`
- `k8s/microservices/identity-service-networkpolicy.yaml`
- `k8s/microservices/identity-service-serviceaccount.yaml`

#### Social Service (NEW)
Create files:
- `k8s/microservices/social-service-deployment.yaml`
- `k8s/microservices/social-service-service.yaml`
- `k8s/microservices/social-service-configmap.yaml`
- `k8s/microservices/social-service-secret.yaml`
- `k8s/microservices/social-service-hpa.yaml`
- `k8s/microservices/social-service-pdb.yaml`
- `k8s/microservices/social-service-networkpolicy.yaml`
- `k8s/microservices/social-service-serviceaccount.yaml`

#### Communication Service (NEW)
Create files:
- `k8s/microservices/communication-service-deployment.yaml`
- `k8s/microservices/communication-service-service.yaml`
- `k8s/microservices/communication-service-configmap.yaml`
- `k8s/microservices/communication-service-secret.yaml`
- `k8s/microservices/communication-service-hpa.yaml`
- `k8s/microservices/communication-service-pdb.yaml`
- `k8s/microservices/communication-service-networkpolicy.yaml`
- `k8s/microservices/communication-service-serviceaccount.yaml`

#### Events Service (if not exists)
Check and create if needed:
- `k8s/microservices/events-service-deployment.yaml`
- `k8s/microservices/events-service-service.yaml`
- `k8s/microservices/events-service-configmap.yaml`

### 4. Update Kustomization Files

#### Base Kustomization
File: `k8s/infrastructure/base/kustomization.yaml`
- Remove references to deleted services
- Add new V2 services

#### Staging Overlays
File: `k8s/infrastructure/overlays/staging/kustomization.yaml`
- Update patches for new services
- Remove patches for deleted services

### 5. Update Ingress and Network Policies

#### Ingress Rules
Files to update:
- `k8s/infrastructure/base/ingress.yaml`
- `k8s/staging/graphql-gateway-ingress.yaml`

Changes:
- Update service endpoints
- Add routes for new services if needed

#### Network Policies
- Update inter-service communication rules
- Add policies for new services
- Remove policies for deleted services

### 6. Update ConfigMaps and Secrets

#### Service Discovery
Update service endpoints in ConfigMaps:
- GraphQL Gateway needs new service URLs
- Update gRPC endpoints for inter-service communication

#### Database Connections
- Identity Service needs user table access
- Social Service needs social tables access
- Communication Service needs messaging tables access

### 7. Update CI/CD Pipelines

#### GitHub Actions
Check and update:
- `.github/workflows/deploy-*.yaml`
- Build and push new service images
- Update deployment scripts

#### ArgoCD Applications
Update ArgoCD application manifests:
- `k8s/argocd/nova-staging-application.yaml`
- Add new services to sync

## Migration Steps

### Phase 1: Preparation
1. ✅ Create this migration plan
2. Backup existing K8s configurations
3. Create new service Docker images

### Phase 2: Create New Services
1. Create identity-service K8s resources
2. Create social-service K8s resources
3. Create communication-service K8s resources
4. Test new services in isolation

### Phase 3: Update Existing Services
1. Update graphql-gateway configuration
2. Update user-service scope
3. Update media-service configuration
4. Update content-service if needed

### Phase 4: Migration Execution
1. Deploy new services to staging
2. Update service discovery
3. Test inter-service communication
4. Update ingress rules
5. Verify health checks

### Phase 5: Cleanup
1. Remove old service deployments
2. Clean up unused ConfigMaps/Secrets
3. Update monitoring/alerting
4. Update documentation

## Resource Specifications

### Identity Service (Suggested)
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
replicas: 2 (min), 5 (max)
```

### Social Service (Suggested)
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
replicas: 2 (min), 10 (max)
```

### Communication Service (Suggested)
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
replicas: 2 (min), 8 (max)
```

## Environment Variables Mapping

### Identity Service
```
DATABASE_URL: postgresql://...
REDIS_URL: redis://...
JWT_SECRET: ${JWT_SECRET}
GRPC_PORT: 50051
HTTP_PORT: 8080
```

### Social Service
```
DATABASE_URL: postgresql://...
REDIS_URL: redis://...
KAFKA_BROKERS: kafka:9092
GRPC_PORT: 50052
HTTP_PORT: 8081
```

### Communication Service
```
DATABASE_URL: postgresql://...
REDIS_URL: redis://...
KAFKA_BROKERS: kafka:9092
SMTP_HOST: ${SMTP_HOST}
SMTP_PORT: ${SMTP_PORT}
GRPC_PORT: 50053
HTTP_PORT: 8082
```

## Validation Checklist

- [ ] All V1 service deployments removed
- [ ] New V2 service deployments created
- [ ] Service discovery updated
- [ ] Ingress rules updated
- [ ] Network policies configured
- [ ] ConfigMaps/Secrets updated
- [ ] Health checks passing
- [ ] Inter-service communication working
- [ ] GraphQL Gateway connecting to all services
- [ ] Monitoring/metrics working
- [ ] Logs aggregating correctly
- [ ] Staging environment tested
- [ ] Rollback plan documented

## Rollback Plan

If issues occur:
1. Keep V1 service YAML files in `k8s/archived-v1/`
2. Re-apply V1 configurations if needed
3. Update ingress to route back to V1
4. Document issues for retry

## Next Steps

1. Review and approve this plan
2. Start with Phase 2: Create new service K8s configurations
3. Test in local K8s cluster first
4. Deploy to staging for integration testing
5. Plan production migration