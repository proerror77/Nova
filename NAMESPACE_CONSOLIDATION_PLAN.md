# Nova Backend Namespace Consolidation Plan

**Created**: 2025-11-11
**Status**: Proposal
**Priority**: P0 - Critical (Blocking user-service startup)
**Author**: Infrastructure Team

---

## Executive Summary

Nova backend currently has **8 separate namespaces** causing cross-namespace connectivity failures and operational complexity. **IMMEDIATE BLOCKER**: user-service cannot connect to content-service across namespace boundaries, causing CrashLoopBackOff.

**Key Issue**: Services like `user-service` (nova-backend) trying to connect to `content-service` (nova-content) using short DNS names fail because Kubernetes DNS requires fully qualified names for cross-namespace communication.

**Recommended Action**: Consolidate to 2 namespaces (nova-prod, nova-staging) with zero-downtime migration.

---

## Current State Analysis

### 🔴 Critical Problems

1. **P0 Blocker: Cross-Namespace DNS Failures**
   - user-service (nova-backend) → content-service (nova-content): **FAILING**
   - Code expects: `content-service:9081`
   - Required: `content-service.nova-content.svc.cluster.local:9081`
   - Impact: 4 pods in CrashLoopBackOff

2. **Infrastructure Fragmentation**
   - Redis in `nova-media`
   - Kafka in `kafka` namespace
   - PostgreSQL in `nova` namespace
   - Services scattered across 8 namespaces

3. **Operational Complexity**
   - 8 namespaces to monitor
   - 34 total pods across namespaces
   - Complex RBAC and network policies
   - Difficult troubleshooting

### 📊 Current Namespace Distribution

| Namespace | Pods | Services | Key Components |
|-----------|------|----------|----------------|
| **nova-backend** | 16 | 6 | user-service, messaging-service, notification-service, events-service, cdn-service, postgres |
| **nova-gateway** | 4 | 1 | graphql-gateway (production) |
| **nova-content** | 3 | 1 | content-service |
| **nova-feed** | 3 | 1 | feed-service |
| **nova-auth** | 3 | 1 | auth-service |
| **nova-staging** | 2 | 1 | graphql-gateway (staging) |
| **nova-media** | 2 | 2 | media-service, redis |
| **nova** | 1 | 2 | postgres (legacy) |
| **kafka** | 2 | - | kafka-0, zookeeper-0 |

**Total**: 8 namespaces, 36 pods (34 Nova + 2 Kafka)

### 🧩 Service Dependency Map

```
graphql-gateway (nova-gateway)
    ↓ needs
user-service (nova-backend)
    ↓ needs
content-service (nova-content)     ← **BROKEN** (cross-namespace)
feed-service (nova-feed)           ← **BROKEN** (cross-namespace)
auth-service (nova-auth)           ← **BROKEN** (cross-namespace)
media-service (nova-media)         ← **BROKEN** (cross-namespace)

messaging-service (nova-backend)
    ↓ needs
postgres (nova-backend + nova)     ← **DUPLICATE** (2 instances)
redis (nova-media)                 ← cross-namespace
kafka (kafka namespace)            ← cross-namespace
```

**Key Finding**: Most services in `nova-backend` depend on services in other namespaces, causing widespread connectivity issues.

---

## Proposed Solution: 2-Namespace Architecture

### 🎯 Target Architecture

```
┌─────────────────────────────────────────────────────────┐
│  nova-prod (Production Environment)                    │
│  ────────────────────────────────────────────────────   │
│                                                         │
│  Backend Services:                                       │
│    • user-service                                       │
│    • content-service                                    │
│    • feed-service                                       │
│    • auth-service                                       │
│    • media-service                                      │
│    • messaging-service                                  │
│    • notification-service                               │
│    • events-service                                     │
│    • cdn-service                                        │
│                                                         │
│  API Gateway:                                           │
│    • graphql-gateway                                    │
│                                                         │
│  Infrastructure:                                        │
│    • postgres                                           │
│    • redis                                              │
│    • kafka (kept in separate kafka namespace)           │
│                                                         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  nova-staging (Staging/Development Environment)        │
│  ────────────────────────────────────────────────────   │
│                                                         │
│    • graphql-gateway (staging)                          │
│    • [Future: other staging services]                   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### ✅ Benefits

1. **Immediate Problem Resolution**
   - ✓ All services in same namespace can use short DNS names
   - ✓ No cross-namespace connectivity issues
   - ✓ user-service can find content-service at `content-service:9081`

2. **Simplified Operations**
   - ✓ Single namespace to monitor for production
   - ✓ Unified RBAC policies
   - ✓ Simpler network policies
   - ✓ Faster troubleshooting

3. **Clear Environment Separation**
   - ✓ Production vs Staging clearly separated
   - ✓ Easy to apply environment-specific policies
   - ✓ Resource quotas per environment

4. **No Code Changes Required**
   - ✓ Existing service discovery code works (short names)
   - ✓ No application redeployment needed
   - ✓ Zero downtime migration possible

### 📋 Migration Checklist

#### Phase 1: Immediate Fix (15 minutes)
**Goal**: Unblock user-service CrashLoopBackOff

- [ ] Option A: Update user-service environment variable
  ```yaml
  env:
    - name: CONTENT_SERVICE_URL
      value: "content-service.nova-content.svc.cluster.local:9081"
  ```

- [ ] Option B: Move content-service to nova-backend namespace
  ```bash
  kubectl get deploy content-service -n nova-content -o yaml | \
    sed 's/namespace: nova-content/namespace: nova-backend/' | \
    kubectl apply -f -
  ```

**Recommendation**: Option B (move content-service) as temporary fix, then proceed with full consolidation.

#### Phase 2: Full Consolidation (2-3 hours)

**Step 1: Pre-Migration Validation** (30 minutes)
- [ ] List all services in each namespace
- [ ] Document all ConfigMaps and Secrets
- [ ] Document all PVCs (Persistent Volume Claims)
- [ ] Export all service configurations
- [ ] Backup current state

**Step 2: Create Target Namespace** (15 minutes)
- [ ] Create `nova-prod` namespace
- [ ] Apply resource quotas
- [ ] Apply network policies
- [ ] Configure RBAC

**Step 3: Migrate Infrastructure** (45 minutes)
- [ ] Migrate postgres from nova/nova-backend to nova-prod
- [ ] Migrate redis from nova-media to nova-prod
- [ ] Update connection strings
- [ ] Verify connectivity

**Step 4: Migrate Services** (60 minutes)
- [ ] Migrate in dependency order:
  1. content-service (nova-content → nova-prod)
  2. feed-service (nova-feed → nova-prod)
  3. auth-service (nova-auth → nova-prod)
  4. media-service (nova-media → nova-prod)
  5. user-service (nova-backend → nova-prod)
  6. messaging-service (nova-backend → nova-prod)
  7. notification-service (nova-backend → nova-prod)
  8. events-service (nova-backend → nova-prod)
  9. cdn-service (nova-backend → nova-prod)
  10. graphql-gateway (nova-gateway → nova-prod)

**Step 5: Validation** (30 minutes)
- [ ] Verify all pods Running
- [ ] Test service-to-service communication
- [ ] Check logs for errors
- [ ] Test graphql-gateway endpoints
- [ ] Verify database connections

**Step 6: Cleanup** (15 minutes)
- [ ] Delete old namespaces (after 24h grace period):
  - nova-backend
  - nova-gateway
  - nova-content
  - nova-feed
  - nova-auth
  - nova-media
  - nova (keep postgres if needed)

---

## Migration Script Template

```bash
#!/bin/bash
# migrate-to-nova-prod.sh

TARGET_NS="nova-prod"

# Create target namespace
kubectl create namespace $TARGET_NS

# Function to migrate deployment
migrate_deployment() {
  local service=$1
  local source_ns=$2

  echo "Migrating $service from $source_ns to $TARGET_NS"

  # Export deployment
  kubectl get deploy $service -n $source_ns -o yaml | \
    sed "s/namespace: $source_ns/namespace: $TARGET_NS/" | \
    kubectl apply -f -

  # Export service
  kubectl get svc $service -n $source_ns -o yaml | \
    sed "s/namespace: $source_ns/namespace: $TARGET_NS/" | \
    kubectl apply -f -

  # Wait for rollout
  kubectl rollout status deploy/$service -n $TARGET_NS

  # Verify
  kubectl get pods -n $TARGET_NS -l app=$service
}

# Migrate in order
migrate_deployment "content-service" "nova-content"
migrate_deployment "feed-service" "nova-feed"
migrate_deployment "auth-service" "nova-auth"
migrate_deployment "media-service" "nova-media"
migrate_deployment "redis" "nova-media"

# Continue with other services...
```

---

## Risk Assessment

### 🟢 Low Risk (Recommended Approach)

**Using Blue-Green Deployment Strategy**:
1. Create nova-prod namespace
2. Deploy all services to nova-prod (parallel to existing)
3. Test nova-prod services
4. Update graphql-gateway to point to nova-prod
5. Monitor for 24 hours
6. Delete old namespaces

**Rollback**: Simple - revert graphql-gateway configuration

### 🟡 Medium Risk

**In-Place Migration**:
1. Migrate services one by one
2. Update DNS as you go

**Risk**: Potential downtime between migrations

### 🔴 High Risk (Not Recommended)

**Big-Bang Migration**:
- Delete all old namespaces
- Deploy everything to nova-prod
- Hope nothing breaks

**Risk**: Complete service outage if issues occur

---

## Alternative Approaches Considered

### ❌ Option 1: Keep Current 8 Namespaces
**Pros**: No migration work
**Cons**:
- Doesn't fix CrashLoopBackOff
- Requires updating all service discovery code
- Complex ongoing operations

### ❌ Option 2: Single Namespace (nova)
**Pros**: Simplest possible
**Cons**:
- No environment separation (prod/staging)
- Difficult to apply environment-specific policies
- Resource quota management harder

### ✅ Option 3: 2 Namespaces (Recommended)
**Pros**:
- Fixes all connectivity issues
- Clear environment separation
- Manageable complexity
**Cons**:
- Requires 2-3 hour migration

### ❌ Option 4: 3 Namespaces (nova-backend, nova-gateway, nova-infrastructure)
**Pros**: Logical service grouping
**Cons**:
- Still has cross-namespace issues
- More complex than 2 namespaces

---

## Implementation Timeline

### ⚡ Emergency Fix (Today - 15 minutes)
Move content-service to nova-backend to unblock user-service

### 📅 Full Migration (This Week - 3 hours)
**Day 1**: Preparation and planning
**Day 2**: Create nova-prod, migrate infrastructure
**Day 3**: Migrate services, validation
**Day 4**: Monitoring and adjustment
**Day 5**: Cleanup old namespaces

---

## Success Criteria

- [ ] Zero pods in CrashLoopBackOff
- [ ] All services can communicate using short DNS names
- [ ] graphql-gateway responds to queries
- [ ] 95% reduction in cross-namespace traffic
- [ ] Single production namespace to monitor
- [ ] Clear staging environment separation

---

## Open Questions

1. **Kafka Namespace**: Should we move kafka to nova-prod or keep separate?
   - **Recommendation**: Keep separate - Kafka is infrastructure that may serve multiple applications

2. **PostgreSQL Duplication**: We have postgres in both `nova` and `nova-backend` namespaces
   - **Recommendation**: Consolidate to single postgres in nova-prod

3. **nova-staging**: Should we populate with full staging environment?
   - **Recommendation**: Start minimal, expand as needed

---

## References

- P0_CRITICAL_FIXES_GUIDE.md (P0-3, P0-4)
- user-service/src/main.rs:285-307 (content-service dependency)
- Kubernetes DNS: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/

---

## Approval

- [ ] Infrastructure Team Lead
- [ ] Backend Team Lead
- [ ] DevOps Engineer
- [ ] Security Review

---

**Next Steps**:
1. Review and approve this plan
2. Execute Phase 1 immediate fix
3. Schedule Phase 2 migration window
