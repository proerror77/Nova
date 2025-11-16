# Nova CI/CD Architecture Patterns & Design Reference

This document defines recommended architecture patterns for operationalizing Nova's CI/CD pipeline.

---

## 1. Build Pipeline Architecture

### Current (Problematic)

```
Code Commit
    ↓
[GitHub Actions] or [AWS CodeBuild]
    ↓
Compile (debug) ❌
    ↓
Build Docker image (Dockerfile)
    ↓
Push to ECR
    ↓
Deploy to EKS ❌ (no validation)
```

### Recommended (Proper)

```
Code Commit
    ↓
[GitHub Actions - Unified Entry Point]
    ├─ Lint & Format (parallel)
    ├─ Unit Tests (parallel per service)
    ├─ Security Scans (parallel)
    └─ Integration Tests
    ↓
✅ All checks pass
    ↓
Build (release mode)
    ↓
Scan image for vulnerabilities
    ↓
Generate SBOM
    ↓
Sign image
    ↓
Push to ECR (immutable)
    ↓
[Pre-deployment validation]
    ├─ Cluster health
    ├─ Dependencies ready
    ├─ Images available
    └─ Manifests valid
    ↓
[Canary deployment] (10% traffic)
    ├─ Monitor error rate
    ├─ Monitor latency
    └─ Auto-rollback if threshold breached
    ↓
[Complete rollout] (100% traffic)
    ↓
[Post-deployment validation]
    ├─ Smoke tests
    ├─ E2E tests
    └─ Health checks
```

---

## 2. Deployment Strategy: Canary Pattern

### Architecture

```
                     ┌─────────────────────────────┐
                     │   Service Mesh / Ingress    │
                     │  (traffic control 0-100%)   │
                     └──────────────┬──────────────┘
                                    │
                  ┌─────────────────┼─────────────────┐
                  │                 │                 │
            ┌─────▼────┐      ┌─────▼────┐      ┌────▼─────┐
            │  Old Pod  │      │  Canary  │      │  Old Pod  │
            │ v1.2.1    │      │ v1.2.2   │      │ v1.2.1    │
            │ 90%       │      │ 10%      │      │           │
            │ traffic   │      │ traffic  │      │           │
            └───────────┘      └──────────┘      └───────────┘

Phase 1: Deploy canary with 10% traffic
→ Monitor for 5 minutes
→ Check error rate < 1%, latency < 200ms

Phase 2: Increase to 50%
→ Monitor for 5 minutes
→ Same checks

Phase 3: Complete rollout to 100%
→ Kill old pods
→ Complete deployment
```

### Implementation with Argo Rollouts

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: identity-service
  namespace: nova
spec:
  replicas: 3
  selector:
    matchLabels:
      app: identity-service

  template:
    metadata:
      labels:
        app: identity-service
    spec:
      containers:
      - name: identity-service
        image: $ECR_REGISTRY/nova/identity-service:$TAG

  strategy:
    canary:
      steps:
      # Step 1: 10% traffic
      - setWeight: 10
      - pause:
          duration: 5m

      # Step 2: 50% traffic
      - setWeight: 50
      - pause:
          duration: 5m

      # Step 3: Complete
      - setWeight: 100

      # Analysis configuration
      analysis:
        interval: 1m
        threshold: 3
        metrics:
        - name: error-rate
          query: |
            rate(http_requests_total{
              status=~"5..",
              service="identity-service"
            }[1m])
          thresholdValue: "0.01"  # 1% error rate = rollback

        - name: latency-p95
          query: |
            histogram_quantile(0.95,
              rate(http_request_duration_seconds_bucket{
                service="identity-service"
              }[1m])
            )
          thresholdValue: "0.2"  # 200ms P95 = rollback
```

---

## 3. Multi-Environment Architecture

### Environments & Promotion

```
Development (Local/Docker Compose)
    ↓
    ├─ Code + tests run locally
    ├─ Integration tests with local services
    └─ Manual testing

Staging (AWS EKS - feature branch)
    ↓
    ├─ Feature branches auto-deploy
    ├─ Automated E2E tests
    ├─ Load testing
    └─ Canary testing

Production (AWS EKS - main branch)
    ↓
    ├─ Only stable releases
    ├─ Canary deployment mandatory
    ├─ Blue-green fallback available
    └─ Manual approval gates for critical changes
```

### Configuration Management with Kustomize

```
k8s/
├── base/
│   ├── identity-service/
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   └── messaging-service/
│
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   ├── patches/
│   │   └── secrets/
│   │
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   ├── patches/
│   │   │   └── replica-counts.yaml
│   │   └── secrets/
│   │
│   └── prod/
│       ├── kustomization.yaml
│       ├── patches/
│       │   ├── replica-counts.yaml (replicas: 3-5)
│       │   └── resources.yaml (high requests/limits)
│       └── secrets/
│
└── monitoring/
    └── prometheus-rules.yaml
```

### Base Configuration

```yaml
# k8s/base/identity-service/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

commonLabels:
  app: identity-service
  managed-by: kustomize

resources:
- deployment.yaml
- service.yaml
- configmap.yaml

configMapGenerator:
- name: identity-service-config
  literals:
  - LOG_LEVEL=info
  - ENABLE_METRICS=true

replicas:
- name: identity-service
  count: 1

images:
- name: identity-service
  newTag: latest
```

### Production Overlay

```yaml
# k8s/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- ../../base/identity-service

namespace: nova-prod

replicas:
- name: identity-service
  count: 3

images:
- name: identity-service
  newTag: v1.2.3  # Semantic version

patchesStrategicMerge:
- patch-resources-prod.yaml
- patch-hpa-prod.yaml

configMapGenerator:
- name: identity-service-config
  behavior: merge
  literals:
  - LOG_LEVEL=warn
  - ENABLE_TRACING=true
  - ENABLE_PROFILING=false

# Network policies
patchesJson6902:
- target:
    group: networking.k8s.io
    version: v1
    kind: NetworkPolicy
  patch: |-
    - op: add
      path: /spec/policyTypes
      value: ["Ingress", "Egress"]
```

---

## 4. Testing Strategy Pyramid

```
                          E2E Tests
                       (Full journey)
                      /            \
                    /                \
               Contract Tests       Smoke Tests
              (Service boundaries)  (Critical path)
                    \                /
                      \            /
                    Integration Tests
                  (Databases, APIs)
                          │
                          │
                    Unit Tests
                (Fast, deterministic)
```

### Pipeline Integration

```yaml
test-pyramid:
  unit-tests:
    duration: 2 min
    parallelization: per-service (6 parallel)
    coverage: Required 80%
    failure: Block merge

  integration-tests:
    duration: 5 min
    services: PostgreSQL, Redis
    scope: Database queries, caching
    failure: Block merge

  contract-tests:
    duration: 3 min
    scope: gRPC service contracts
    failure: Block merge

  smoke-tests:
    duration: 2 min
    scope: Health checks, basic endpoints
    failure: Warn, don't block

  e2e-tests:
    duration: 10 min
    scope: Full user journeys
    failure: Alert, allow re-run
```

---

## 5. Observability Stack

### Three Pillars

```
┌────────────────────────────────────────────────────────┐
│                   OBSERVABILITY                         │
├────────────┬────────────────────┬──────────────────────┤
│   METRICS  │    LOGS            │      TRACES          │
├────────────┼────────────────────┼──────────────────────┤
│ Prometheus │ Loki / ELK         │ Jaeger               │
│ Grafana    │ Kibana             │ Tempo                │
│            │ LogQL queries      │ Distributed tracing  │
│            │                    │ Span correlation     │
└────────────┴────────────────────┴──────────────────────┘

┌────────────────────────────────────────────────────────┐
│              ALERTING & INCIDENT RESPONSE              │
├────────────┬────────────────────┬──────────────────────┤
│ AlertMgr   │ Pagerduty          │ Runbooks             │
│ Prometheus │ On-call routing    │ Automated playbooks  │
│ Threshold  │ Escalation policy  │ Rollback triggers    │
└────────────┴────────────────────┴──────────────────────┘
```

### Metrics to Track (DORA)

```
1. Deployment Frequency
   → How often code reaches production
   → Target: Daily or on-demand
   → Query: rate(deployments_total[1d])

2. Lead Time for Changes
   → Time from commit to production
   → Target: < 1 hour
   → Query: deployment_lead_time_seconds

3. Change Failure Rate
   → % of deployments that cause incidents
   → Target: < 15%
   → Query: deployment_failures_total / deployments_total

4. Mean Time to Recovery
   → Time to resolve incidents
   → Target: < 1 hour
   → Query: incident_resolution_seconds
```

---

## 6. Security Architecture

### Defense in Depth

```
┌─────────────────────────────────────────────────────────┐
│ 1. CODE LEVEL SECURITY                                  │
│    ├─ Clippy (linting)                                  │
│    ├─ cargo-audit (dependency vulnerabilities)          │
│    ├─ cargo-deny (license compliance)                   │
│    └─ Code review (manual)                              │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 2. BUILD TIME SECURITY                                  │
│    ├─ Secret scanning (gitleaks)                        │
│    ├─ SBOM generation (Syft)                            │
│    ├─ Container scanning (Trivy)                        │
│    └─ Image signing (Cosign)                            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 3. DEPLOYMENT SECURITY                                  │
│    ├─ Network policies (ingress/egress)                 │
│    ├─ Pod security policies                             │
│    ├─ RBAC (role-based access control)                  │
│    └─ Secret management (sealed secrets)                │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 4. RUNTIME SECURITY                                     │
│    ├─ Falco (anomaly detection)                         │
│    ├─ AppArmor / SELinux                                │
│    ├─ Audit logging                                     │
│    └─ Threat monitoring                                 │
└─────────────────────────────────────────────────────────┘
```

---

## 7. Infrastructure as Code (IaC) Architecture

### State Management

```
Terraform Code (Git Repository)
    ↓
[Terraform Workspace per Environment]
    ├─ Development
    ├─ Staging
    └─ Production
    ↓
[S3 Remote Backend]
    ├─ State file (encrypted)
    ├─ Version history
    └─ DynamoDB locking
    ↓
[AWS Resources]
    ├─ EKS clusters
    ├─ RDS databases
    ├─ VPCs & networking
    ├─ ECR registries
    └─ IAM roles
```

### Module Structure

```
terraform/
├── modules/
│   ├── eks/
│   │   ├── cluster.tf
│   │   ├── node_groups.tf
│   │   ├── addons.tf
│   │   └── variables.tf
│   ├── rds/
│   │   ├── postgres.tf
│   │   ├── backup.tf
│   │   └── variables.tf
│   ├── networking/
│   │   ├── vpc.tf
│   │   ├── subnets.tf
│   │   ├── security_groups.tf
│   │   └── variables.tf
│   └── security/
│       ├── iam_roles.tf
│       ├── kms.tf
│       └── secrets.tf
│
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   ├── staging/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   └── prod/
│       ├── main.tf
│       ├── terraform.tfvars
│       └── backend.tf
│
└── scripts/
    ├── bootstrap-backend.sh
    ├── plan-changes.sh
    └── apply-changes.sh
```

---

## 8. GitOps Architecture

### Recommended: ArgoCD Pattern

```
Developer
    ↓
Git Commit (k8s manifests + code)
    ↓
GitHub Actions (validate, scan)
    ↓
Merge to main
    ↓
[ArgoCD Controller in Kubernetes]
    ├─ Watches Git repository
    ├─ Detects configuration drift
    ├─ Auto-syncs desired ← actual state
    └─ Reconciliation every 3 minutes
    ↓
EKS Cluster
    ├─ Latest manifests deployed
    ├─ History of all changes
    └─ Rollback by reverting Git
```

### ArgoCD Application Example

```yaml
# k8s/argocd/nova-staging-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nova-staging
  namespace: argocd

spec:
  project: nova

  # Source of truth: Git
  source:
    repoURL: https://github.com/prover/nova
    targetRevision: feature/phase1-grpc-migration
    path: k8s/overlays/staging

  # Destination: EKS cluster
  destination:
    server: https://kubernetes.default.svc
    namespace: nova

  # Sync policy
  syncPolicy:
    automated:
      prune: true      # Delete resources not in Git
      selfHeal: true   # Sync if cluster drifts
      allowEmpty: false

    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground

    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

---

## 9. Cost Optimization Patterns

### Image Size Optimization

```
Debug Build (before):      200-300 MB
  └─ Unstripped binary: 150 MB
  └─ Debug symbols: 50-100 MB
  └─ Runtime dependencies: 50 MB

Release Build (after):     50-80 MB
  └─ Stripped binary: 20-40 MB
  └─ Runtime dependencies: 30-40 MB

Cost impact:
  ECR storage: $0.10/GB/month
  Per image per month: $20/month (250MB debug) vs $8/month (80MB release)
  For 15 services: $300/month → $120/month savings
```

### Compute Optimization

```
Node types by workload:

Development:    t3.small (1vCPU, 2GB RAM)
  └─ Cost: $0.023/hour
  └─ Suitable for: Individual services, testing

Staging:        t3.large (2vCPU, 8GB RAM)
  └─ Cost: $0.093/hour
  └─ Suitable for: Full stack, E2E testing

Production:     t3.xlarge (4vCPU, 16GB RAM) or r6g.xlarge
  └─ Cost: $0.186/hour (t3) or $0.198/hour (r6g)
  └─ Suitable for: Production workloads, HA setup
```

---

## 10. Disaster Recovery & Business Continuity

### RTO & RPO Targets

```
Service Tier          RTO (Recovery Time)    RPO (Recovery Point)
──────────────────────────────────────────────────────────────
Tier 1 (Critical)     < 1 hour               < 5 minutes
Tier 2 (Important)    < 4 hours              < 1 hour
Tier 3 (Standard)     < 24 hours             < 6 hours

RTO Implementation:
├─ Automated failover (database multi-AZ)
├─ Blue-green deployments
├─ Regular disaster drills
└─ On-call rotation

RPO Implementation:
├─ Continuous database backups
├─ WAL archiving (PostgreSQL)
├─ Cross-AZ replication
└─ Backup testing (weekly restore drills)
```

### Backup Strategy

```
PostgreSQL:
  ├─ Full backup: Daily at 02:00 UTC
  ├─ Incremental: Every 6 hours
  ├─ WAL archiving: Continuous to S3
  ├─ Retention: 30 days
  └─ Test: Weekly restore drills

Application State (Redis):
  ├─ RDB snapshots: Every hour
  ├─ AOF (Append-Only File): Real-time
  ├─ Replication: Master-slave
  └─ Backup to S3: Daily

EKS Configuration:
  ├─ Git as source of truth
  ├─ Helm charts versioned
  ├─ Manifests in Git history
  └─ Rollback by reverting commit
```

---

## Conclusion

This architecture provides:

- ✅ **Safety**: Pre-deployment validation, automated rollback
- ✅ **Speed**: Parallel testing, cached builds, canary deployments
- ✅ **Reliability**: Multi-environment testing, disaster recovery
- ✅ **Cost**: Optimized images, right-sized compute
- ✅ **Observability**: Metrics, logs, traces, DORA metrics
- ✅ **Security**: Defense in depth, signed images, SBOM

Implementation follows the principle: **"Fail fast, fix automatically, recover quickly."**

