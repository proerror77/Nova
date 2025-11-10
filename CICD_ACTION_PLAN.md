# CI/CD & DevOps - Action Plan

**Status**: Ready for Implementation
**Priority**: CRITICAL
**Timeline**: 4 weeks to production readiness

---

## Quick Summary

Nova's CI/CD pipeline is **structurally sound** (12-stage workflow, Kubernetes, GitOps) but has **3 critical blockers** preventing production deployment:

1. ❌ **No container security scanning** - CVEs will reach production
2. ❌ **Hardcoded secrets in git** - Credentials exposed
3. ❌ **Auth tests missing** - Security bugs undetected

## What Was Generated

### Files Created

1. **`CICD_DEVOPS_ASSESSMENT.md`** (Comprehensive 500-line review)
   - Detailed findings per category
   - Maturity scoring
   - All recommendations with code examples

2. **`.github/workflows/security-scanning.yml`** (Ready to deploy)
   - Container scanning (Trivy)
   - Secrets detection (gitleaks)
   - SBOM generation
   - Artifact signing (Cosign)
   - K8s configuration scanning

3. **`k8s/infrastructure/base/external-secrets.yaml`** (Ready to deploy)
   - External Secrets Operator setup
   - AWS Secrets Manager integration
   - Secret rotation automation
   - All services configured

4. **`backend/libs/actix-middleware/tests/security_auth_tests.rs`** (Ready to run)
   - 15 authentication tests
   - Validates JWT enforcement
   - GraphQL-specific tests
   - Expired/malformed token handling

---

## Implementation Roadmap

### Week 1: CRITICAL (Blocks Production)

#### Day 1-2: Security Scanning Pipeline
**Effort**: 4 hours | **Risk**: LOW
```bash
# Deploy security scanning
git add .github/workflows/security-scanning.yml
git commit -m "feat: add comprehensive security scanning pipeline"
git push

# Expected: Pipeline runs on next push
# Result: Container vulnerabilities, secrets, SAST issues detected
```

**Verification**:
```bash
# Trigger workflow manually
gh workflow run security-scanning.yml --ref main

# Wait 15 minutes for results
gh run list --workflow security-scanning.yml
```

#### Day 2-3: Fix Hardcoded Secrets
**Effort**: 3 hours | **Risk**: HIGH (Production impact)

1. **Identify all secrets in git**:
```bash
git log --all -p -S "password" | grep -B5 -B5 password
git log --all -p -S "secret" | head -50
```

2. **Rotate ALL secrets** (before fix goes live):
```bash
# In AWS Secrets Manager console:
# - nova/jwt-secret
# - nova/database/password
# - nova/database/root-password
# - nova/redis/password
# - nova/s3/access-key
# - nova/s3/secret-key
```

3. **Deploy External Secrets**:
```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace

# Deploy secret stores
kubectl apply -f k8s/infrastructure/base/external-secrets.yaml

# Verify
kubectl get externalsecrets -n nova-gateway
kubectl get secrets -n nova-gateway
```

4. **Update deployments** to use External Secrets:
```yaml
# Before
env:
- name: JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: graphql-gateway-secret  # Hardcoded
      key: JWT_SECRET

# After
env:
- name: JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: graphql-gateway-secret  # Managed by External Secrets
      key: JWT_SECRET
```

5. **Scan and clean git history**:
```bash
# Using BFG Repo-Cleaner (faster than git filter-branch)
bfg --delete-files 'Dockerfile' --replace-text 'password=.*' -r .

# Or for specific patterns
git filter-branch --tree-filter 'sed -i "s/password=.*/password=***REDACTED***/g" k8s/**/*.yaml' HEAD

# Force push (careful!)
git push --force-with-lease origin main
```

#### Day 3: Add Authentication Tests
**Effort**: 2 hours | **Risk**: LOW

```bash
# Tests are ready in backend/libs/actix-middleware/tests/security_auth_tests.rs

# Run locally
cd backend/libs/actix-middleware
cargo test security_auth_tests

# Should pass immediately (validates auth enforcement)
```

**Expected output**:
```
test test_protected_endpoint_without_auth_returns_401 ... ok
test test_protected_endpoint_with_expired_token_returns_401 ... ok
test test_graphql_query_without_auth_fails ... ok
test_graphql_introspection_requires_auth ... ok
```

#### Day 4: Enable TLS/Certificate Management
**Effort**: 1 hour | **Risk**: MEDIUM (downtime if misconfigured)

```bash
# 1. Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.yaml

# 2. Create ClusterIssuer
cat > /tmp/letsencrypt-issuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@nova.social
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

kubectl apply -f /tmp/letsencrypt-issuer.yaml

# 3. Update ingress to use TLS
kubectl patch ingress graphql-gateway-ingress -n nova-gateway --type merge -p '{
  "metadata": {
    "annotations": {
      "cert-manager.io/cluster-issuer": "letsencrypt-prod",
      "nginx.ingress.kubernetes.io/ssl-redirect": "true"
    }
  },
  "spec": {
    "tls": [{
      "hosts": ["api.nova.social"],
      "secretName": "nova-api-tls"
    }]
  }
}'

# 4. Verify certificate was issued
kubectl get certificate -n nova-gateway
kubectl describe certificate nova-api-tls -n nova-gateway
```

#### Day 5: Integration Testing
**Effort**: 2 hours | **Risk**: LOW

```bash
# Run expanded integration tests
cd backend
cargo test --test '*' integration

# Should validate:
# ✓ Auth enforcement
# ✓ JWT validation
# ✓ Database connectivity
# ✓ gRPC service calls
```

**Verification Checklist**:
```
[ ] Security scanning workflow runs
[ ] Container scan blocks on CRITICAL CVEs
[ ] Secrets detected by gitleaks
[ ] No hardcoded passwords in ConfigMaps
[ ] External Secrets pulling from AWS
[ ] Auth tests pass
[ ] TLS certificate issued and valid
[ ] All tests passing in CI
```

---

### Week 2: HIGH Priority

#### Load Testing
**Effort**: 8 hours | **Files**:
- `tests/load/k6-script.js` (create)
- Update `ci-cd-pipeline.yml` with load test stage

```javascript
// tests/load/k6-script.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  vus: 100,
  duration: '5m',
  thresholds: {
    http_req_duration: ['p(99)<500'],  // 99th percentile < 500ms
    http_req_failed: ['rate<0.01'],    // < 1% failure rate
  },
};

export default function () {
  // Test connection pool under load
  let res = http.post('http://graphql-gateway:8080/graphql', {
    query: '{ user(id: "123") { id name } }',
  }, {
    headers: {
      'Authorization': 'Bearer ' + __ENV.JWT_TOKEN,
    },
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'latency < 500ms': (r) => r.timings.duration < 500,
    'no timeout': (r) => r.timings.duration > 0,
  });

  sleep(1);
}
```

**Add to pipeline**:
```yaml
# .github/workflows/ci-cd-pipeline.yml
load-test:
  name: Load Testing
  needs: deploy-staging
  runs-on: ubuntu-latest

  steps:
  - uses: actions/checkout@v4
  - uses: grafana/k6-action@v0.3.0
    with:
      filename: tests/load/k6-script.js
      cloud: false
```

#### Code Coverage Fix
**Effort**: 6 hours

```bash
# Current: Claims 50%, actual ~0.2%
# Required: Set realistic baseline, trend coverage

# 1. Set initial baseline to 20% (realistic for current codebase)
# 2. Add weekly coverage report
# 3. Require +2% improvement for PRs

# Update ci-cd-pipeline.yml
cargo tarpaulin --fail-under 20 --out Xml
```

#### Integration Tests Expansion
**Effort**: 12 hours

```bash
# Current: PostgreSQL + Redis only
# Required: Full service-to-service validation

# Create comprehensive integration suite
cat > backend/tests/integration.rs << 'EOF'
#[tokio::test]
async fn test_graphql_gateway_calls_auth_service() {
  // Test actual gRPC call to auth-service
}

#[tokio::test]
async fn test_user_service_database_consistency() {
  // Test data consistency across transactions
}

#[tokio::test]
async fn test_service_timeout_handling() {
  // Test behavior when service is slow
}
EOF
```

---

### Week 3: MEDIUM Priority

#### Monitoring & Observability
**Effort**: 10 hours

1. **GraphQL Metrics**:
```rust
// backend/graphql-gateway/src/metrics.rs
pub struct GraphQLMetrics {
    pub query_duration: Histogram,
    pub query_errors: Counter,
    pub resolver_duration: Histogram,
}

// Register with Prometheus
metrics::register_histogram!("graphql_query_duration_seconds");
metrics::register_counter!("graphql_query_errors_total");
```

2. **Deploy Prometheus + Grafana**:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n nova-monitoring --create-namespace

# Import Grafana dashboards
curl https://grafana.com/api/dashboards/3662/revisions/1/download | \
  kubectl apply -f -
```

3. **Configure Alerts**:
```yaml
# k8s/infrastructure/base/prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: nova-alerts
spec:
  groups:
  - name: nova.rules
    rules:
    - alert: HighErrorRate
      expr: sum(rate(http_requests_total{status=~"5.."}[5m])) > 0.01
      for: 2m
      labels:
        severity: critical
```

#### Blue-Green Deployments
**Effort**: 4 hours

```bash
# Install Argo Rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Replace Deployment with Rollout
cat > k8s/graphql-gateway/rollout.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: graphql-gateway
spec:
  replicas: 3
  strategy:
    canary:
      steps:
      - setWeight: 10
      - pause: { duration: 5m }
      - setWeight: 50
      - pause: { duration: 5m }
      - setWeight: 100
  template: ...
EOF
```

#### GraphQL Schema Validation
**Effort**: 4 hours

```rust
// backend/graphql-gateway/src/schema_validation.rs
#[test]
fn test_all_types_documented() {
    let schema = get_schema();

    for type_def in schema.types {
        assert!(
            !type_def.description.is_empty(),
            "Type {} missing description",
            type_def.name
        );
    }
}

#[test]
fn test_no_deprecated_fields_in_production() {
    let schema = get_schema();

    for field in schema.all_fields() {
        if field.is_deprecated {
            panic!("Deprecated field {} found in production schema", field.name);
        }
    }
}
```

---

### Week 4: NICE-TO-HAVE

#### SBOM & Artifact Signing
**Effort**: 3 hours
- Already configured in `security-scanning.yml`
- Just needs to run once

#### Chaos Engineering
**Effort**: 6 hours
```yaml
# k8s/base/chaos-mesh/pod-failure.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: test-pod-failure
spec:
  action: pod-kill
  selector:
    namespaces:
    - nova
  duration: '30s'
  scheduler:
    cron: '@hourly'  # Run hourly
```

---

## Testing Checklist

Run these before declaring "Week 1 COMPLETE":

```bash
# Security
[ ] Security scanning workflow runs
[ ] Trivy blocks CRITICAL vulnerabilities
[ ] gitleaks detects hardcoded secrets
[ ] No hardcoded passwords in ConfigMaps

# Authentication
[ ] All auth tests pass
[ ] /graphql endpoint requires JWT
[ ] /health endpoint public (no auth required)
[ ] Expired tokens rejected with 401

# Secrets Management
[ ] External Secrets pulling from AWS
[ ] Pod can decrypt secrets
[ ] Secret rotation works (check after 1 hour)

# TLS/Certificates
[ ] cert-manager installed
[ ] Certificate issued and valid
[ ] HTTPS enforced on ingress
[ ] curl https://api.nova.social/health returns 200

# Database
[ ] Integration tests pass
[ ] Connection pool limits work
[ ] Queries don't hang under load

# Deployment
[ ] All images pushed to ECR
[ ] Kubernetes manifests valid
[ ] Pods starting successfully
[ ] Health checks passing
```

---

## Git Commit Messages

```
# Week 1, Day 1
git commit -m "feat: add comprehensive security scanning pipeline

- Add Trivy container scanning (blocks on CRITICAL)
- Add gitleaks secrets detection
- Add cargo-audit and cargo-deny for dependencies
- Add Kube-score for K8s configuration scanning
- Upload results to GitHub Security tab"

# Week 1, Day 2
git commit -m "security: implement external secrets operator

- Replace hardcoded JWT secret with AWS Secrets Manager
- Replace hardcoded database passwords with external references
- Implement automatic secret rotation every 6 hours
- Add audit logging for all secret access"

# Week 1, Day 3
git commit -m "test: add comprehensive authentication test suite

- Add 15 new security-focused auth tests
- Test JWT validation, expiration, malformed tokens
- Test GraphQL introspection requires auth
- Validate 401 returned for all unauthorized requests"

# Week 1, Day 4
git commit -m "feat: enable TLS and certificate management

- Install cert-manager and ClusterIssuer
- Configure Let's Encrypt ACME for automatic renewal
- Force HTTPS redirect on all ingresses
- Enable HSTS header for production"

# Week 1, Day 5
git commit -m "test: expand integration test suite

- Add gRPC service-to-service tests
- Add database transaction consistency tests
- Add service timeout and failure scenarios
- Add GraphQL endpoint validation tests"
```

---

## Risk Management

### Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Secrets rotation breaks deployment | HIGH | Test in staging first, have rollback plan |
| cert-manager issues cause downtime | MEDIUM | Maintain HTTP endpoint during transition |
| Load tests impact staging | MEDIUM | Run during off-peak hours, limit VUs |
| Auth tests break existing endpoints | MEDIUM | Run tests first, review failures before deploying |
| Container scan blocks all images | MEDIUM | Whitelist known false positives initially |

### Rollback Procedures

```bash
# If security scanning blocks everything:
git revert <commit-hash>
git push

# If External Secrets fails:
kubectl rollout undo statefulset postgres
kubectl rollout undo deployment graphql-gateway

# If TLS breaks access:
kubectl patch ingress graphql-gateway-ingress --type json \
  -p '[{"op":"remove","path":"/spec/tls"}]'
```

---

## Monitoring Progress

### Weekly Check-in

```bash
# Week 1 Progress
kubectl get pods -n nova
kubectl get jobs
gh workflow list

# Week 2 Progress
kubectl logs -l app=graphql-gateway -n nova-gateway
kubectl top nodes
kubectl top pods -n nova

# Week 3 Progress
kubectl get alerts
kubectl get servicemonitors
```

---

## Success Criteria

After 4 weeks:

- ✅ Security scanning blocks all deployments with critical CVEs
- ✅ All secrets stored in AWS Secrets Manager (none in git)
- ✅ All endpoints enforce JWT authentication
- ✅ TLS/HTTPS enforced
- ✅ Load testing validates connection pool limits
- ✅ Code coverage trending (baseline 20%, target 40%)
- ✅ Zero authentication bypasses in CI/CD tests
- ✅ Prometheus + Grafana monitoring deployed
- ✅ Incident alerts configured

---

## Contact & Escalation

- **DevOps Lead**: Resolve pipeline issues
- **Security**: Review scanning results
- **Backend Team**: Fix failing auth tests
- **Infra**: Manage AWS Secrets Manager

---

**Generated**: 2025-11-10
**Status**: Ready for implementation
**Next Step**: Start Week 1, Day 1
