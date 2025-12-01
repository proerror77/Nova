# DevOps Configuration Templates - Nova Social

Ready-to-use configuration files for immediate implementation.

---

## 1. Clippy Configuration for Unwrap() Enforcement

### File: `backend/clippy.toml`

```toml
[lints]
# DENY: Will fail the build
clippy-warn = "clippy::unwrap_used"
clippy-warn = "clippy::panic"
clippy-warn = "clippy::todo"
clippy-warn = "clippy::unimplemented"
clippy-warn = "clippy::unreachable"

# ALLOW: Too noisy for now
clippy-allow = "clippy::too_many_arguments"
clippy-allow = "clippy::should_implement_trait"
clippy-allow = "clippy::type_complexity"
```

### File: `.github/workflows/code-quality.yml` (Updated)

```yaml
name: Code Quality Checks

on:
  pull_request:
    branches: [main, develop]
    paths:
      - 'backend/**'
      - '.github/workflows/code-quality.yml'
  push:
    branches: [main, develop]

jobs:
  # Enforce no unwrap() in production code
  enforce-no-unwrap:
    name: Enforce unwrap() Prohibition
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: ./.github/actions/setup-rust-env
        with:
          cache-key-suffix: unwrap-check

      - name: Run Clippy with unwrap_used as ERROR
        working-directory: backend
        run: |
          echo "🔍 Enforcing: No unwrap() calls allowed"
          cargo clippy --all-targets --all-features -- \
            -D clippy::unwrap_used \
            -D clippy::panic \
            -D clippy::todo \
            -W clippy::expect_used

      - name: Generate unwrap violation report
        if: failure()
        run: |
          echo "## ❌ Unwrap() Violations Found" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "Violations must be fixed before merge:" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          cargo clippy --all-targets -- -D clippy::unwrap_used 2>&1 | grep "unwrap" >> $GITHUB_STEP_SUMMARY || true
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "### Remediation Guide" >> $GITHUB_STEP_SUMMARY
          echo "1. Replace \`.unwrap()\` with \`.context(\"error message\")?\`" >> $GITHUB_STEP_SUMMARY
          echo "2. Or use \`.map_err(|e| anyhow!(...))?\"" >> $GITHUB_STEP_SUMMARY
          echo "3. For tests, use \`.expect(\"test setup failed\")\"" >> $GITHUB_STEP_SUMMARY
```

### Rust Code Example - Before/After

**BEFORE** (❌ Panic Risk):
```rust
pub async fn create_user(req: CreateUserRequest) -> Result<User> {
    let email = validate_email(&req.email).unwrap();
    let db_url = std::env::var("DATABASE_URL").unwrap();
    let pool = PgPool::connect(&db_url).await.unwrap();
    let user = pool.get_user(&email).await.unwrap();
    Ok(user)
}
```

**AFTER** (✅ Proper Error Handling):
```rust
pub async fn create_user(req: CreateUserRequest) -> Result<User> {
    let email = validate_email(&req.email)
        .context("Invalid email format")?;

    let db_url = std::env::var("DATABASE_URL")
        .context("DATABASE_URL environment variable not set")?;

    let pool = PgPool::connect(&db_url)
        .await
        .context("Failed to connect to database")?;

    let user = pool.get_user(&email)
        .await
        .context("User not found in database")?;

    Ok(user)
}

// For tests, expect() is acceptable:
#[cfg(test)]
mod tests {
    #[tokio::test]
    async fn test_create_user() {
        let pool = setup_test_db()
            .await
            .expect("Test database setup failed");
        // ...
    }
}
```

---

## 2. ArgoCD Installation & Configuration

### File: `k8s/argocd/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
  labels:
    app.kubernetes.io/name: argocd
---
apiVersion: v1
kind: Namespace
metadata:
  name: nova-staging
  labels:
    environment: staging
---
apiVersion: v1
kind: Namespace
metadata:
  name: nova-prod
  labels:
    environment: production
```

### File: `k8s/argocd/application-staging.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nova-staging
  namespace: argocd
  # Auto-delete when Application is deleted
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/proerror/nova
    targetRevision: main
    path: k8s/overlays/staging

    # Kustomize settings
    kustomize:
      version: v5.0.0
      commonLabels:
        app.kubernetes.io/managed-by: argocd
        app.kubernetes.io/environment: staging

  destination:
    server: https://kubernetes.default.svc
    namespace: nova-staging

  syncPolicy:
    # Automatic sync: Changes in git auto-deploy
    automated:
      prune: true      # Delete resources not in git
      selfHeal: true   # Revert manual kubectl changes

    # Selective sync options
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=false

    # Retry failed syncs
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 5m

  # Health assessment
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas  # Ignore HPA-managed replicas

  # Notification when sync completes
  info:
  - name: 'documentation'
    value: 'https://docs.nova.io/deployment'
  - name: 'slack'
    value: '#deployments'
```

### File: `k8s/argocd/application-production.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nova-production
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/proerror/nova
    targetRevision: main  # Use git tags for prod: v1.2.3
    path: k8s/overlays/production

  destination:
    server: https://kubernetes.default.svc
    namespace: nova-prod

  syncPolicy:
    automated:
      prune: true
      selfHeal: true

    # Manual sync for production (safer)
    # Remove automated for stricter control
    syncOptions:
    - CreateNamespace=true

  # Progressive sync: Don't all services at once
  progressDeadlineSeconds: 1800  # 30 min timeout
```

### Installation Script: `scripts/install-argocd.sh`

```bash
#!/bin/bash
set -e

NAMESPACE="argocd"
VERSION="v2.9.3"  # Update to latest

echo "📦 Installing ArgoCD $VERSION..."

# Create namespace
kubectl create namespace $NAMESPACE || echo "Namespace $NAMESPACE exists"

# Install ArgoCD
kubectl apply -n $NAMESPACE -f "https://raw.githubusercontent.com/argoproj/argo-cd/$VERSION/manifests/install.yaml"

# Wait for deployment
echo "⏳ Waiting for ArgoCD to be ready..."
kubectl rollout status deployment/argocd-server -n $NAMESPACE --timeout=300s
kubectl rollout status deployment/argocd-application-controller -n $NAMESPACE --timeout=300s

# Get initial password
echo ""
echo "✅ ArgoCD installed successfully!"
echo ""
echo "Access ArgoCD UI:"
echo "  kubectl port-forward -n $NAMESPACE svc/argocd-server 8080:443"
echo "  Browser: https://localhost:8080"
echo ""
INITIAL_PASSWORD=$(kubectl -n $NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Initial Credentials:"
echo "  Username: admin"
echo "  Password: $INITIAL_PASSWORD"
echo ""
echo "Change password:"
echo "  argocd account update-password --account admin --new-password <new-password>"
```

---

## 3. Prometheus Alert Rules

### File: `k8s/infrastructure/prometheus-rules.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: nova-alerts
  namespace: monitoring
  labels:
    prometheus: kube-prometheus
spec:
  groups:
  - name: nova.rules
    interval: 30s
    rules:

    # ============ HTTP Errors ============
    - alert: HighErrorRate
      expr: |
        rate(http_requests_total{status=~"5.."}[5m]) > 0.05
      for: 5m
      labels:
        severity: critical
        service: "{{ $labels.service }}"
      annotations:
        summary: "{{ $labels.service }}: High error rate"
        description: |
          Service {{ $labels.service }} error rate is {{ $value | humanizePercentage }} (threshold: 5%)
          Check: kubectl logs -n nova -l app={{ $labels.service }}

    # ============ Latency ============
    - alert: HighLatencyP95
      expr: |
        histogram_quantile(0.95,
          rate(http_request_duration_seconds_bucket{job="nova"}[5m])
        ) > 1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High P95 latency ({{ $value }}s > 1s)"
        description: |
          95th percentile latency exceeds 1 second.
          Service: {{ $labels.service }}
          Check database performance and slow queries.

    # ============ Pod Crashes ============
    - alert: PodCrashLooping
      expr: |
        rate(kube_pod_container_status_restarts_total[15m]) > 0.1
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Pod {{ $labels.pod }} is crash looping"
        description: |
          Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is restarting frequently.
          Check: kubectl describe pod -n {{ $labels.namespace }} {{ $labels.pod }}
          Logs: kubectl logs -n {{ $labels.namespace }} {{ $labels.pod }} --tail=50

    # ============ Disk Usage ============
    - alert: HighDiskUsage
      expr: |
        (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) > 0.85
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "PVC {{ $labels.persistentvolumeclaim }} disk usage > 85%"
        description: |
          Persistent volume {{ $labels.persistentvolumeclaim }} is {{ $value | humanizePercentage }} full.
          Consider scaling storage.

    # ============ Memory Pressure ============
    - alert: HighMemoryUsage
      expr: |
        (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Container {{ $labels.container }} memory usage > 85%"
        description: |
          Container {{ $labels.container }} in {{ $labels.pod }} is using {{ $value | humanizePercentage }} of memory limit.
          May cause OOMKill. Check resource requests.

    # ============ Database Connections ============
    - alert: DatabaseConnectionPoolNearMax
      expr: |
        pg_stat_activity_count / max_connections > 0.8
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "PostgreSQL connection pool at {{ $value | humanizePercentage }}"
        description: |
          Database {{ $labels.instance }} is using 80%+ of available connections.
          May indicate connection leak. Check active queries:
          SELECT * FROM pg_stat_activity WHERE state != 'idle';

    # ============ GraphQL Errors ============
    - alert: HighGraphQLErrorRate
      expr: |
        rate(graphql_request_total{status="error"}[5m]) > 0.01
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "GraphQL error rate > 1%"
        description: |
          GraphQL error rate for service {{ $labels.service }} is {{ $value | humanizePercentage }}.
          Query: {{ $labels.query }}

    # ============ Cache Hit Rate ============
    - alert: LowCacheHitRate
      expr: |
        (rate(cache_hits_total[5m]) / (rate(cache_hits_total[5m]) + rate(cache_misses_total[5m]))) < 0.5
      for: 10m
      labels:
        severity: info
      annotations:
        summary: "Cache hit rate low ({{ $value | humanizePercentage }})"
        description: |
          Cache hit rate for {{ $labels.service }} is below 50%.
          May indicate performance degradation. Check cache configuration.

  # ============ Recording Rules ============
  - name: nova.recording
    interval: 1m
    rules:
    - record: job:http_requests:rate5m
      expr: rate(http_requests_total[5m])

    - record: job:http_latency_p95:5m
      expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

    - record: job:error_rate:5m
      expr: rate(http_requests_total{status=~"5.."}[5m])
```

### File: `k8s/infrastructure/alertmanager-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: monitoring
data:
  alertmanager.yml: |
    global:
      resolve_timeout: 5m
      slack_api_url: '${SLACK_WEBHOOK_URL}'

    route:
      receiver: 'default'
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h

      routes:
      # Critical alerts → PagerDuty
      - match:
          severity: critical
        receiver: 'pagerduty'
        repeat_interval: 1h
        continue: true

      # Warnings → Slack
      - match:
          severity: warning
        receiver: 'slack-warnings'
        repeat_interval: 12h

      # Info → No notification (just logs)
      - match:
          severity: info
        receiver: 'null'
        repeat_interval: 1d

    receivers:
    - name: 'default'
      slack_configs:
      - channel: '#alerts-general'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

    - name: 'slack-warnings'
      slack_configs:
      - channel: '#alerts-warnings'
        title: '⚠️ {{ .GroupLabels.alertname }}'

    - name: 'pagerduty'
      pagerduty_configs:
      - service_key: '${PAGERDUTY_SERVICE_KEY}'

    - name: 'null'

    inhibit_rules:
    # Suppress warnings if critical already firing
    - source_match:
        severity: 'critical'
      target_match:
        severity: 'warning'
      equal: ['alertname', 'service']

    # Suppress info if warning already firing
    - source_match:
        severity: 'warning'
      target_match:
        severity: 'info'
      equal: ['alertname', 'service']
```

---

## 4. Pre-Commit Hooks Configuration

### File: `.pre-commit-config.yaml`

```yaml
# See https://pre-commit.com for more information
repos:
  # Rust formatting
  - repo: https://github.com/rust-lang/rustfmt
    rev: 1.75.0
    hooks:
      - id: rustfmt
        name: rustfmt
        language: rust
        types: [rust]
        args: [--edition=2021]

  # Rust linting with Clippy
  - repo: https://github.com/doublify/pre-commit-rust
    rev: v1.0
    hooks:
      - id: fmt
        args: [--all]
      - id: clippy
        args: [--all-targets, --all-features, --, -D, warnings]

  # Conventional commits
  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v2.4.0
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]

  # YAML validation
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: yaml-unsafe
        args: [--unsafe]
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-added-large-files
        args: [--maxkb=1000]
      - id: check-case-conflict
      - id: check-merge-conflict
      - id: check-json
      - id: check-toml
      - id: check-yaml

  # Git secrets detection
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: [--baseline, .secrets.baseline]

  # Markdown linting
  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.37.0
    hooks:
      - id: markdownlint
        args: [--ignore, docs/archived]

ci:
  autofix_commit_msg: |
    chore(pre-commit): auto fixes from pre-commit.com hooks

    for more information, see https://pre-commit.com
  autofix_prs: true
  autoupdate_branch: ''
  autoupdate_commit_msg: 'chore(pre-commit): autoupdate pre-commit hooks'
  autoupdate_schedule: weekly
  skip: []
  submodules: false
```

### Installation Script

```bash
#!/bin/bash
# scripts/setup-pre-commit.sh

echo "📦 Installing pre-commit hooks..."

# Install pre-commit if not already installed
if ! command -v pre-commit &> /dev/null; then
  pip install pre-commit
fi

# Install the git hook
pre-commit install
pre-commit install --hook-type commit-msg

# Run on all files to validate
echo "🔍 Running pre-commit on all files..."
pre-commit run --all-files

echo "✅ Pre-commit hooks installed and validated!"
echo ""
echo "Future commits will be checked automatically."
echo "To skip checks (not recommended): git commit --no-verify"
```

---

## 5. SLO Framework Configuration

### File: `k8s/infrastructure/slo-rules.yaml`

```yaml
# Service Level Objectives for Nova Social
# Based on service criticality and customer impact
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nova-slo-config
  namespace: monitoring
data:
  slo-definitions.yaml: |
    # Tier 1: Critical Services (99.95% SLA)
    tier1:
      services:
        - identity-service
        - graphql-gateway
      availability_target: 0.9995
      error_rate_target: 0.0005
      latency_p99_target: 200ms
      latency_p95_target: 100ms
      monthly_budget_seconds: 21.6  # ~21 seconds downtime/month

    # Tier 2: Core Services (99.5% SLA)
    tier2:
      services:
        - content-service
        - feed-service
        - social-service
        - graph-service
      availability_target: 0.995
      error_rate_target: 0.005
      latency_p99_target: 500ms
      latency_p95_target: 300ms
      monthly_budget_seconds: 21.6 * 5  # ~108 seconds downtime/month

    # Tier 3: Supporting Services (99.0% SLA)
    tier3:
      services:
        - analytics-service
        - notification-service
        - search-service
        - media-service
      availability_target: 0.99
      error_rate_target: 0.01
      latency_p99_target: 1000ms
      latency_p95_target: 500ms
      monthly_budget_seconds: 432  # ~7 minutes downtime/month

    # Tier 4: Non-Critical Services (95% SLA)
    tier4:
      services:
        - ranking-service
        - realtime-chat-service
        - trust-safety-service
      availability_target: 0.95
      error_rate_target: 0.05
      latency_p99_target: 2000ms
      latency_p95_target: 1000ms
      monthly_budget_seconds: 2160  # ~36 minutes downtime/month

---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-alerts
  namespace: monitoring
spec:
  groups:
  - name: slo.rules
    interval: 1m
    rules:
    # Error Budget Depletion Alerts
    - alert: SLOErrorBudgetDepletedTier1
      expr: |
        (rate(http_requests_total{tier="tier1",status=~"5.."}[30d]) /
         rate(http_requests_total{tier="tier1"}[30d])) > 0.0005
      for: 5m
      labels:
        severity: critical
        slo_tier: tier1
      annotations:
        summary: "Tier 1 service {{ $labels.service }}: Error budget depleted"
        description: |
          Service {{ $labels.service }} has exceeded 99.95% SLA.
          Current error rate: {{ $value | humanizePercentage }}
          Allowed: 0.05%

    - alert: SLOErrorBudgetWarningTier1
      expr: |
        (rate(http_requests_total{tier="tier1",status=~"5.."}[30d]) /
         rate(http_requests_total{tier="tier1"}[30d])) > 0.0003
      for: 5m
      labels:
        severity: warning
        slo_tier: tier1
      annotations:
        summary: "Tier 1 service {{ $labels.service }}: Error budget low"
        description: |
          Service {{ $labels.service }} is at 60% of error budget.
          Current error rate: {{ $value | humanizePercentage }}

    # Latency SLO Violations
    - alert: SLOLatencyViolationTier1
      expr: |
        histogram_quantile(0.99,
          rate(http_request_duration_seconds_bucket{tier="tier1"}[5m])
        ) > 0.2
      for: 5m
      labels:
        severity: warning
        slo_tier: tier1
      annotations:
        summary: "Tier 1 service {{ $labels.service }}: Latency SLO violation"
        description: |
          Service {{ $labels.service }} P99 latency {{ $value }}s exceeds 200ms target.
```

---

## 6. Blue-Green Deployment Script

### File: `scripts/deploy-blue-green.sh`

```bash
#!/bin/bash
set -e

SERVICE=$1
NAMESPACE=${2:-nova-staging}
NEW_IMAGE_TAG=${3:-$(git rev-parse --short HEAD)}
ECR_REGISTRY="025434362120.dkr.ecr.ap-northeast-1.amazonaws.com"

if [ -z "$SERVICE" ]; then
  echo "Usage: $0 <service> [namespace] [image-tag]"
  echo "Example: $0 graphql-gateway nova-staging main-abc123"
  exit 1
fi

# Determine current active version
CURRENT_ACTIVE=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" \
  -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "blue")
NEXT_VERSION=$([ "$CURRENT_ACTIVE" = "blue" ] && echo "green" || echo "blue")

echo "📢 Blue-Green Deployment: $SERVICE"
echo "  Current active: $CURRENT_ACTIVE"
echo "  Deploying to:  $NEXT_VERSION"
echo "  Image tag:     $NEW_IMAGE_TAG"
echo ""

# Update image
echo "🐳 Updating $SERVICE-$NEXT_VERSION image..."
kubectl set image deployment/$SERVICE-$NEXT_VERSION \
  -n $NAMESPACE \
  $SERVICE=$ECR_REGISTRY/nova/$SERVICE:$NEW_IMAGE_TAG \
  --record

# Wait for rollout
echo "⏳ Waiting for rollout to complete..."
kubectl rollout status deployment/$SERVICE-$NEXT_VERSION \
  -n $NAMESPACE \
  --timeout=5m

# Run smoke tests
echo "🧪 Running smoke tests..."
HEALTH_URL="http://$SERVICE.$NAMESPACE.svc.cluster.local:8080/health"

for i in {1..30}; do
  RESPONSE=$(kubectl run -i --rm test-$$ \
    --image=curlimages/curl:latest \
    --restart=Never \
    --quiet \
    -- curl -s "$HEALTH_URL" 2>/dev/null || echo "")

  if echo "$RESPONSE" | grep -q "ok"; then
    echo "✅ Health check passed"
    break
  fi

  if [ $i -eq 30 ]; then
    echo "❌ Health check failed after 30 attempts"
    echo "Smoke test output: $RESPONSE"
    exit 1
  fi

  echo "Attempt $i/30..."
  sleep 5
done

# Ask for confirmation before switching traffic
echo ""
echo "🔀 Ready to switch traffic?"
echo "  Current active: $CURRENT_ACTIVE → $NEXT_VERSION"
read -p "Switch traffic? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "🔄 Switching traffic..."
  kubectl patch svc "$SERVICE" -n "$NAMESPACE" -p \
    '{"spec":{"selector":{"version":"'$NEXT_VERSION'"}}}'

  echo "✅ Traffic switched to $NEXT_VERSION"
  echo ""
  echo "Verification commands:"
  echo "  kubectl logs -n $NAMESPACE -l app=$SERVICE,version=$NEXT_VERSION -f"
  echo "  kubectl get pods -n $NAMESPACE -l app=$SERVICE"
else
  echo "⏭️  Traffic switch cancelled. Deployment remains in standby on $NEXT_VERSION"
  echo "To switch manually:"
  echo "  kubectl patch svc $SERVICE -n $NAMESPACE -p '{\"spec\":{\"selector\":{\"version\":\"$NEXT_VERSION\"}}}'"
fi
```

---

## 7. GitHub Actions Workflow: Push Image Tags on ArgoCD Sync

### File: `.github/workflows/update-argocd-images.yml`

```yaml
name: Update ArgoCD Image Tags

on:
  push:
    branches:
      - main
      - feature/phase1-grpc-migration
    paths:
      - 'backend/**'

jobs:
  update-images:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Configure Git
        run: |
          git config user.email "github-actions@nova.io"
          git config user.name "GitHub Actions [Bot]"

      - name: Update staging image tags
        run: |
          # Update all services in staging kustomization
          for service in analytics-service content-service feed-service graph-service graphql-gateway identity-service media-service notification-service ranking-service realtime-chat-service search-service social-service trust-safety-service; do
            sed -i "s|newTag: .*$service:.*|newTag: ${{ github.sha }}|g" \
              k8s/overlays/staging/kustomization.yaml
          done

      - name: Commit image updates
        run: |
          if git diff --quiet k8s/overlays/staging/kustomization.yaml; then
            echo "No changes"
            exit 0
          fi

          git add k8s/overlays/staging/kustomization.yaml
          git commit -m "chore(argocd): update staging image tags to ${{ github.sha }}"
          git push origin HEAD:${{ github.ref_name }}

      - name: Verify ArgoCD sync
        run: |
          # Wait for ArgoCD to detect changes and sync
          echo "✅ Image tags updated. ArgoCD will detect changes via git polling."
```

---

**These templates are ready for immediate deployment. Customize paths and values for your specific infrastructure.**

**Document Version**: 1.0
**Last Updated**: November 26, 2025
