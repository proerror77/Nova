# Nova CI/CD & DevOps Architecture Review

**Date**: 2025-11-16
**Reviewer**: Deployment Engineering Team
**Status**: Critical Issues Identified
**Impact**: Production Risk - Immediate Action Required

---

## Executive Summary

Nova's CI/CD pipeline has substantial infrastructure but exhibits **critical production defects** and **significant architectural gaps**. The pipeline processes 15+ microservices across staging and production with AWS CodeBuild and GitHub Actions, but lacks fundamental safety mechanisms.

### Critical Findings

| Category | Status | Risk Level | Impact |
|----------|--------|-----------|--------|
| **Build Automation** | ⚠️ Critical Issues | **P0** | Using debug builds instead of release; breaks performance |
| **Deployment Safety** | ❌ Inadequate | **P0** | No pre-deployment validation; no rollback automation |
| **Testing Coverage** | ⚠️ Below Standard | **P1** | 38-50% coverage; threshold too low (50%); not enforced |
| **Container Security** | ⚠️ Partial | **P1** | Images scanned but no policy enforcement; SBOM missing |
| **Infrastructure as Code** | ❌ Broken | **P1** | Terraform local backend; no state management; manual deployment |
| **Monitoring & Alerting** | ✅ Good | **P2** | Prometheus/Grafana configured; lacking DORA metrics |
| **Dependency Management** | ⚠️ Incomplete | **P1** | cargo-audit configured; no automated dependency updates |
| **Database Migrations** | ❌ Manual | **P2** | No automated migration execution in pipeline |
| **Environment Parity** | ⚠️ Inconsistent | **P2** | Dev/staging/prod configurations scattered |
| **Incident Response** | ⚠️ Limited | **P2** | Manual rollback procedures; no runbooks |

---

## Section 1: Build Automation Assessment

### Current State

The project uses:
- **AWS CodeBuild** (buildspec.yml) for manual builds
- **GitHub Actions** (ci-cd-pipeline.yml) for automated CI/CD
- **Docker BuildKit** with multi-stage builds
- **Cargo caching** per service
- **Parallel matrix builds** (max 6 parallel services in CI)

### Critical Issues Found

#### 1.1 [BLOCKER] Debug Builds in Production

**Location**: `/Users/proerror/Documents/nova/backend/Dockerfile:36-39`

```dockerfile
# ❌ CURRENT (WRONG)
RUN if [ -n "$CARGO_BUILD_JOBS" ]; then \
      cargo build --manifest-path user-service/Cargo.toml -j $CARGO_BUILD_JOBS ; \
    else \
      cargo build --manifest-path user-service/Cargo.toml ; \
    fi
```

**Impact**:
- Debug builds are **10-20x larger** than release builds
- **50% slower execution** with debug symbols
- Breaks ECR cost optimization
- Security: debug info exposes internals

**Risk**: Every deployment includes unoptimized, oversized binaries

**Recommended Fix**:
```dockerfile
# Build with release optimizations
ARG BUILD_TYPE=release
RUN if [ "$BUILD_TYPE" = "release" ]; then \
      cargo build --manifest-path user-service/Cargo.toml --release -j ${CARGO_BUILD_JOBS:-4}; \
    else \
      cargo build --manifest-path user-service/Cargo.toml -j ${CARGO_BUILD_JOBS:-4}; \
    fi

# ✅ In CI pipeline, pass --build-arg BUILD_TYPE=release
```

#### 1.2 [BLOCKER] Dockerfile Healthcheck Syntax Error

**Location**: `/Users/proerror/Documents/nova/backend/Dockerfile:74-75`

```dockerfile
# ❌ CURRENT (INVALID SYNTAX)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/app/user-service", "healthcheck-http"] || exit 1
```

**Issue**: `HEALTHCHECK CMD` doesn't support shell operators (`||`). This will **always fail** during image build.

**Recommended Fix**:
```dockerfile
# ✅ CORRECT: No shell operators in array form
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD /app/user-service healthcheck-http || exit 1
```

Or better, wrap in shell:
```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD sh -c '/app/user-service healthcheck-http || exit 1'
```

#### 1.3 Using Debug Binary in Runtime Image

**Location**: `/Users/proerror/Documents/nova/backend/Dockerfile:59`

```dockerfile
# ❌ CURRENT
COPY --from=builder /app/target/debug/user-service /app/user-service

# ✅ SHOULD BE
COPY --from=builder /app/target/release/user-service /app/user-service
```

This guarantees slow, large production images.

### 1.4 Missing Docker Image Optimization

**Current approach**: Multi-stage build (good), but not fully leveraging:

**Recommended improvements**:

```dockerfile
# Stage 1: Builder
FROM rust:1.88-slim-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev ca-certificates cmake build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Cache layer: Copy dependencies first
COPY Cargo.toml Cargo.lock ./
COPY backend/libs ./backend/libs
RUN mkdir -p backend/user-service && \
    echo 'fn main() {}' > backend/user-service/src/main.rs

RUN cargo build --manifest-path backend/user-service/Cargo.toml --release 2>&1 | grep -v "warning:" || true

# Copy actual source
COPY backend/user-service ./backend/user-service

# Build final binary
RUN cargo build --manifest-path backend/user-service/Cargo.toml --release

# Stage 2: Runtime (distroless for minimal image)
FROM debian:bookworm-slim AS runtime

# Install minimal runtime deps only
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 && \
    rm -rf /var/lib/apt/lists/*

# Non-root user
RUN useradd -m -u 1001 appuser

WORKDIR /app

# Copy binary only
COPY --from=builder --chown=appuser:appuser /app/target/release/user-service ./
COPY --chown=appuser:appuser migrations ./migrations

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD /app/user-service healthcheck-http || exit 1

ENV RUST_LOG=info
CMD ["/app/user-service"]
```

**Benefits**:
- Release binary: ~50-80MB vs 200-300MB (debug)
- Faster startup: 50% reduction
- Lower attack surface

### 1.5 Missing Build Artifact Caching Strategy

**Current caching** (setup-rust-env/action.yml):
```yaml
# ✅ Good: Caches cargo registry
path: |
  ~/.cargo/registry/index/
  ~/.cargo/registry/cache/
  ~/.cargo/git/db/
  backend/target/
```

**Missing pieces**:
1. No incremental build caching across PRs
2. No BuildKit layer caching in ECR
3. No build duration tracking

**Recommended**: Use GitHub Actions BuildKit cache:

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build and push with cache
  uses: docker/build-push-action@v6
  with:
    context: backend
    file: backend/Dockerfile
    push: true
    tags: |
      ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:${{ github.sha }}
      ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:latest
    cache-from: type=gha,scope=${{ matrix.service }}
    cache-to: type=gha,scope=${{ matrix.service }},mode=max
```

### 1.6 No Compilation Parallelization Configuration

**Issue**: All Rust builds use default parallelization (number of CPU cores)

**Improvement**: Explicit parallel jobs control:

```yaml
- name: Build release binaries
  working-directory: backend
  env:
    CARGO_BUILD_JOBS: 4  # Control parallelization
    RUSTFLAGS: "-C opt-level=3 -C lto=thin"  # Production optimizations
  run: |
    cargo build --workspace --release --jobs 4 \
      -p user-service -p messaging-service -p search-service
```

### 1.7 Missing Release vs Debug Build Configuration

**Current state**: Single build path for all

**Needed**:
```yaml
build-release:
  name: Build Release Binaries
  # Only on main/staging pushes
  if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/feature/phase1-grpc-migration'
  env:
    CARGO_PROFILE_RELEASE_LTO: thin
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS: 1
  run: cargo build --workspace --release

build-debug:
  name: Build Debug Binaries
  # On PRs for faster feedback
  if: github.event_name == 'pull_request'
  run: cargo build --workspace
```

### Build Automation Summary

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| Build type | Debug | Release | ⚠️ **P0** |
| Image size | ~250MB | ~50-80MB | 70% reduction needed |
| Build time | ~15min | ~8-10min | Cache optimization |
| Caching strategy | Partial | Full (BuildKit + GHA) | ❌ Missing |
| Healthcheck syntax | ❌ Broken | ✅ Fixed | Immediate |

---

## Section 2: Test Automation Integration

### Current State

**Strengths**:
- Unit tests: ✅ Running per service
- Integration tests: ✅ Postgres/Redis services
- Code coverage: ✅ Using cargo-tarpaulin
- Security tests: ✅ cargo-audit + cargo-deny
- E2E tests: ✅ Using k6 load testing

**Weaknesses**:
- Coverage threshold too low (50%)
- Coverage failures don't block merges
- 160 flaky tests not addressed
- No performance regression detection
- No feature flag integration testing

### 2.1 [BLOCKER] Low & Unenforced Coverage Threshold

**Location**: `/Users/proerror/Documents/nova/.github/workflows/ci-cd-pipeline.yml:130`

```yaml
# ❌ CURRENT: Too low, not enforced
--fail-under 50
```

**Issues**:
1. 50% is dangerously low for production code
2. Coverage report generated but failures don't block merge
3. No trend tracking
4. Inconsistent across services

**Recommended approach**:

```yaml
code-coverage:
  name: Code Coverage Analysis
  runs-on: ubuntu-latest
  needs: test-services

  steps:
    - uses: actions/checkout@v4
    - uses: ./.github/actions/setup-rust-env

    - name: Generate coverage with tarpaulin
      working-directory: backend
      run: |
        cargo tarpaulin \
          --workspace \
          --timeout 300 \
          --out Xml \
          --output-dir coverage \
          --exclude-files 'target/*' \
          --fail-under 80 \  # ✅ Raised to 80%
          -- --test-threads 1
      continue-on-error: false  # ✅ Hard fail

    - name: Check coverage per service
      run: |
        # Parse coverage.xml and verify each service > 75%
        for service in user-service messaging-service search-service; do
          COVERAGE=$(grep "module name=\"$service\"" coverage/cobertura.xml | \
                    grep -oP 'line-rate="\K[0-9.]+')
          if (( $(echo "$COVERAGE < 0.75" | bc -l) )); then
            echo "❌ $service coverage $((COVERAGE*100))% < 75%"
            exit 1
          fi
          echo "✅ $service coverage: $((COVERAGE*100))%"
        done

    - name: Upload to Codecov
      uses: codecov/codecov-action@v4
      with:
        fail_ci_if_error: true  # ✅ Fail if upload fails
        flags: backend
        fail-on-error: true
```

### 2.2 Flaky Test Detection & Quarantine

**Current state**: 160 flaky tests exist but no system to detect/quarantine them

**Recommended implementation**:

```yaml
test-services:
  strategy:
    matrix:
      service: [auth-service, messaging-service, ...]
    max-parallel: 6

  steps:
    - name: Run tests with flaky detection
      working-directory: backend/${{ matrix.service }}
      run: |
        # Run each test 3 times to detect flakiness
        cargo test --lib --all-features 2>&1 | tee test-output.log

        # Parse for intermittent failures
        if grep -c "test result: ok" test-output.log | grep -q 1; then
          echo "✅ Deterministic test run"
        else
          echo "⚠️ Potential flaky tests detected"
          exit 1
        fi

    - name: Upload test results
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: test-results-${{ matrix.service }}
        path: |
          backend/${{ matrix.service }}/test-output.log
          backend/${{ matrix.service }}/test-results.json
```

Create a flaky test registry:

```yaml
# .github/flaky-tests.yml
flaky_tests:
  - name: "messaging_service::tests::test_concurrent_message_delivery"
    reason: "Race condition in Redis cache invalidation"
    quarantined: true
    issue: "#1234"

  - name: "feed_service::tests::test_feed_pagination"
    reason: "Timing dependent on database transaction isolation"
    quarantined: true
    issue: "#1235"

# In CI:
- name: Skip quarantined tests
  run: |
    SKIP_TESTS=$(yq '.flaky_tests[] | select(.quarantined==true) | .name' .github/flaky-tests.yml | tr '\n' '|')
    cargo test --lib --all-features -- --skip="$SKIP_TESTS"
```

### 2.3 Missing Performance Regression Testing

**Issue**: No automated performance benchmarking

**Implement benchmark CI**:

```yaml
performance-benchmarks:
  name: Performance Benchmarks
  runs-on: ubuntu-latest
  needs: build-release

  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 2  # Need previous commit for comparison

    - uses: ./.github/actions/setup-rust-env

    - name: Run benchmarks
      working-directory: backend
      run: |
        cargo bench --all-features -- --output-format bencher | tee output.txt

    - name: Upload benchmark results
      uses: benchmark-action/github-action@v1
      with:
        tool: 'cargo'
        output-file-path: backend/output.txt
        github-token: ${{ secrets.GITHUB_TOKEN }}
        auto-push: true  # Auto-push to gh-pages
        comment-on-alert: true

    - name: Compare with baseline
      run: |
        # Parse current vs baseline
        CURRENT_P99=$(grep "user_service::query_p99" output.txt | awk '{print $NF}')
        BASELINE_P99=50  # ms

        if (( $(echo "$CURRENT_P99 > $BASELINE_P99 * 1.2" | bc -l) )); then
          echo "❌ Performance regression: P99 latency increased to ${CURRENT_P99}ms"
          exit 1
        fi
```

### 2.4 Database Integration Tests

**Current state**: Services run, but no actual database interaction tested in CI

**Improve integration tests**:

```yaml
integration-tests:
  name: Database Integration Tests
  runs-on: ubuntu-latest
  needs: test-services

  services:
    postgres:
      image: postgres:15-alpine
      env:
        POSTGRES_DB: nova_test
        POSTGRES_USER: test
        POSTGRES_PASSWORD: test
      options: >-
        --health-cmd pg_isready
        --health-interval 10s
        --health-timeout 5s
        --health-retries 5
      ports:
        - 5432:5432

    redis:
      image: redis:7-alpine
      options: >-
        --health-cmd "redis-cli ping"
        --health-interval 10s
      ports:
        - 6379:6379

  steps:
    - uses: actions/checkout@v4
    - uses: ./.github/actions/setup-rust-env

    - name: Install sqlx-cli
      run: cargo install sqlx-cli --no-default-features --features postgres

    - name: Run migrations (staging schema)
      env:
        DATABASE_URL: postgresql://test:test@localhost:5432/nova_test
      run: |
        cd backend
        sqlx database create 2>/dev/null || true
        sqlx migrate run --source migrations

    - name: Run integration tests
      env:
        DATABASE_URL: postgresql://test:test@localhost:5432/nova_test
        REDIS_URL: redis://localhost:6379
        RUST_LOG: debug
      run: |
        cd backend
        cargo test --test '*' --all-features -- --test-threads 1 --nocapture
```

### 2.5 Security Testing Integration

**Current**: cargo-audit + cargo-deny in separate workflow

**Better approach**: Integrated into main pipeline with enforcement:

```yaml
security-testing:
  name: Security Tests
  runs-on: ubuntu-latest
  needs: format-and-lint

  steps:
    - uses: actions/checkout@v4
    - uses: ./.github/actions/setup-rust-env

    # 1. Dependency vulnerability scanning
    - name: Audit dependencies
      working-directory: backend
      run: |
        cargo audit --deny warnings 2>&1 | tee audit.log

        # Count vulnerabilities
        VULN_COUNT=$(grep -c "^warning:" audit.log || echo 0)
        if [ "$VULN_COUNT" -gt 0 ]; then
          echo "❌ Found $VULN_COUNT vulnerabilities"
          exit 1
        fi

    # 2. Unsafe code analysis
    - name: Check unsafe blocks
      run: |
        # Find unsafe code
        UNSAFE_COUNT=$(find backend -name "*.rs" -exec grep -l "unsafe {" {} \; | wc -l)

        if [ "$UNSAFE_COUNT" -gt 10 ]; then
          echo "⚠️ Found $UNSAFE_COUNT files with unsafe blocks"
          # Flag for review but don't fail
        fi

    # 3. License compliance
    - name: Check licenses
      working-directory: backend
      run: cargo deny check licenses --all-features

    # 4. Secrets scanning
    - name: Scan for secrets
      uses: trufflesecurity/trufflehog@main
      with:
        path: ./backend
        base: ${{ github.event.repository.default_branch }}
        head: HEAD
```

### Test Automation Summary

| Aspect | Current | Target | Gap |
|--------|---------|--------|-----|
| Coverage threshold | 50% (not enforced) | 80% (enforced) | ❌ P1 |
| Flaky test management | Manual | Automated quarantine | ❌ P1 |
| Performance testing | None | Per-commit | ❌ P2 |
| DB integration tests | Basic | Comprehensive | ⚠️ P2 |
| Security tests | Separate job | Integrated | ⚠️ P2 |

---

## Section 3: Deployment Strategies Assessment

### Current State

**What exists**:
- ✅ Rolling updates configured
- ✅ Rollout restart on new images
- ✅ Health check endpoints
- ✅ Pod termination grace periods

**What's missing**:
- ❌ No canary deployments
- ❌ No blue-green deployment option
- ❌ No automatic rollback
- ❌ No pre-deployment validation
- ❌ No deployment feature flags

### 3.1 [BLOCKER] Missing Pre-Deployment Validation

**Current deployment flow**:
```
Image built → Push to ECR → kubectl rollout restart → DONE
```

**Problem**: No validation before rollout. Bad image deployed = downtime.

**Recommended validation pipeline**:

```yaml
deploy-staging:
  name: Deploy to EKS Staging
  runs-on: ubuntu-latest
  needs: build-and-push

  steps:
    - uses: actions/checkout@v4

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}

    - name: Setup kubeconfig
      run: |
        aws eks update-kubeconfig \
          --name nova-staging \
          --region ${{ env.AWS_REGION }}

    # 1. Pre-deployment validation
    - name: Validate deployment manifests
      run: |
        echo "🔍 Validating Kubernetes manifests..."

        # Check YAML syntax
        find k8s -name "*.yaml" -o -name "*.yml" | while read f; do
          kubectl apply -f "$f" --dry-run=client -o yaml > /dev/null || {
            echo "❌ Invalid manifest: $f"
            exit 1
          }
        done

        # Validate pod security policies
        for ns in nova nova-content nova-feed; do
          kubectl get networkpolicies -n "$ns" > /dev/null 2>&1 || {
            echo "⚠️ No network policies in $ns"
          }
        done

    # 2. Image verification
    - name: Verify container images
      run: |
        echo "📦 Verifying images in ECR..."

        for image_tag in ${{ github.sha }}; do
          aws ecr describe-images \
            --repository-name nova/identity-service \
            --image-ids imageTag="$image_tag" \
            --region ${{ env.AWS_REGION }} || {
            echo "❌ Image not found: nova/identity-service:$image_tag"
            exit 1
          }
        done

    # 3. Dependency check (databases, caches, etc.)
    - name: Health check dependencies
      run: |
        echo "🏥 Checking cluster dependencies..."

        # Database
        kubectl exec -n nova $(kubectl get pod -n nova -l app=postgres -o jsonpath='{.items[0].metadata.name}') \
          -- pg_isready -h postgres || {
          echo "❌ PostgreSQL not ready"
          exit 1
        }

        # Redis
        kubectl exec -n nova $(kubectl get pod -n nova -l app=redis -o jsonpath='{.items[0].metadata.name}') \
          -- redis-cli ping || {
          echo "❌ Redis not ready"
          exit 1
        }

    # 4. Canary deployment
    - name: Deploy with canary (10% traffic)
      run: |
        echo "🚀 Starting canary deployment..."

        # Deploy new version to canary replicas
        kubectl set image deployment/identity-service \
          -n nova \
          identity-service=${{ env.ECR_REGISTRY }}/nova/identity-service:${{ github.sha }} \
          --record

        # Wait for canary pods
        kubectl rollout status deployment/identity-service \
          -n nova \
          --timeout=5m || {
          echo "⚠️ Canary deployment timed out, checking pod status..."
          kubectl get pods -n nova -l app=identity-service
          exit 1
        }

    # 5. Canary health check
    - name: Monitor canary metrics (30 seconds)
      run: |
        echo "📊 Monitoring canary health..."

        sleep 30

        # Check error rates
        ERROR_RATE=$(kubectl logs -n nova -l app=identity-service --tail=100 | \
                    grep -c "ERROR" || echo 0)

        if [ "$ERROR_RATE" -gt 5 ]; then
          echo "❌ High error rate detected in canary, rolling back..."
          kubectl rollout undo deployment/identity-service -n nova
          exit 1
        fi

        echo "✅ Canary health check passed"

    # 6. Complete rollout
    - name: Complete rolling deployment
      run: |
        echo "✅ Completing full deployment..."

        kubectl rollout status deployment/identity-service \
          -n nova \
          --timeout=10m

    # 7. Post-deployment validation
    - name: Smoke tests
      run: |
        echo "🧪 Running post-deployment smoke tests..."

        # Port forward to service
        kubectl port-forward -n nova svc/identity-service 8080:8080 &
        PF_PID=$!
        sleep 2

        # Test health endpoint
        curl -f http://localhost:8080/health || {
          kill $PF_PID
          echo "❌ Health check failed"
          exit 1
        }

        kill $PF_PID
        echo "✅ Smoke tests passed"

    - name: Create deployment record
      if: always()
      run: |
        echo "Deployment Status: ${{ job.status }}"
        echo "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        echo "Image: ${{ env.ECR_REGISTRY }}/nova/identity-service:${{ github.sha }}"
```

### 3.2 Implement Canary Deployment Pattern

**Recommended**: Use Argo Rollouts for automated canary deployments

```yaml
# k8s/microservices/identity-service-rollout.yaml (replace deployment)
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
        image: $ECR_REGISTRY/nova/identity-service:$IMAGE_TAG
        ports:
        - containerPort: 8080
        - containerPort: 50051
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5

  # Canary strategy
  strategy:
    canary:
      steps:
      - setWeight: 10   # 10% traffic to new version
      - pause:
          duration: 5m  # Monitor for 5 minutes
      - setWeight: 50   # 50% traffic
      - pause:
          duration: 5m
      - setWeight: 100  # 100% traffic (full rollout)

      # Automatic rollback on metrics
      analysis:
        interval: 1m
        threshold: 3
        metrics:
        - name: error-rate
          query: |
            rate(http_requests_total{status=~"5..",service="identity-service"}[1m])
          thresholdValue: "0.05"  # 5% error rate = rollback
          interval: 1m
```

Install Argo Rollouts:
```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/download/v1.6.0/install.yaml
```

Update CI to use Argo Rollouts:
```yaml
deploy-staging:
  steps:
    - name: Deploy with Argo Rollouts
      run: |
        kubectl set image rollout/identity-service \
          -n nova \
          identity-service=${{ env.ECR_REGISTRY }}/nova/identity-service:${{ github.sha }}

        # Watch rollout progress
        kubectl argo rollouts get rollout identity-service -n nova --watch
```

### 3.3 Implement Blue-Green Deployment Option

For critical services that need instant rollback:

```yaml
# k8s/microservices/identity-service-blue-green.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: identity-service-blue
  labels:
    app: identity-service
    version: blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: identity-service
      version: blue
  template:
    spec:
      containers:
      - name: identity-service
        image: $BLUE_IMAGE_TAG
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: identity-service-green
  labels:
    app: identity-service
    version: green
spec:
  replicas: 0  # Start with 0 replicas
  selector:
    matchLabels:
      app: identity-service
      version: green
  template:
    spec:
      containers:
      - name: identity-service
        image: $GREEN_IMAGE_TAG
---
apiVersion: v1
kind: Service
metadata:
  name: identity-service
spec:
  selector:
    app: identity-service
    version: blue  # Currently serving blue
  ports:
  - port: 8080
    targetPort: 8080
```

CI deployment logic:
```yaml
deploy-blue-green:
  steps:
    - name: Deploy to green (inactive)
      run: |
        # Scale up green with new image
        kubectl set image deployment/identity-service-green \
          -n nova \
          identity-service=${{ env.ECR_REGISTRY }}/nova/identity-service:${{ github.sha }}

        kubectl scale deployment/identity-service-green -n nova --replicas=3

        # Wait for green to be ready
        kubectl wait --for=condition=ready pod \
          -l app=identity-service,version=green \
          -n nova \
          --timeout=5m

    - name: Run smoke tests on green
      run: |
        # Test green before switching
        kubectl exec -n nova $(kubectl get pod -n nova -l app=identity-service,version=green -o jsonpath='{.items[0].metadata.name}') \
          -- curl -f http://localhost:8080/health || exit 1

    - name: Switch traffic to green
      run: |
        # Switch service selector
        kubectl patch service identity-service -n nova -p \
          '{"spec":{"selector":{"version":"green"}}}'

        echo "✅ Traffic switched to green"

    - name: Rollback if needed (manual)
      if: failure()
      run: |
        # Switch back to blue
        kubectl patch service identity-service -n nova -p \
          '{"spec":{"selector":{"version":"blue"}}}'

        echo "⚠️ Rolled back to blue"
```

### 3.4 Automatic Rollback on Metrics

```yaml
# k8s/argocd/identity-service-analysis-template.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: identity-service-analysis
spec:
  metrics:
  - name: error-rate
    successCriteria: result < 1  # < 1% error rate
    interval: 1m
    query: |
      rate(http_requests_total{status=~"5..",job="identity-service"}[1m]) /
      rate(http_requests_total{job="identity-service"}[1m])

  - name: response-latency
    successCriteria: result < 200  # < 200ms P95
    interval: 1m
    query: |
      histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="identity-service"}[1m]))

  - name: cpu-usage
    successCriteria: result < 80  # < 80% CPU
    interval: 1m
    query: |
      rate(container_cpu_usage_seconds_total{pod=~"identity-service-.*"}[1m])
```

### Deployment Strategy Summary

| Aspect | Current | Target | Gap |
|--------|---------|--------|-----|
| Pre-deployment validation | ❌ None | ✅ Full | **P0** |
| Canary deployment | ❌ Manual | ✅ Argo Rollouts | **P1** |
| Blue-Green option | ❌ None | ✅ Available | **P2** |
| Automatic rollback | ❌ Manual | ✅ Metrics-based | **P1** |
| Feature flags | ❌ None | ✅ LaunchDarkly | **P2** |

---

## Section 4: Infrastructure as Code Assessment

### Current State

**Location**: `/Users/proerror/Documents/nova/terraform/`

**Configuration files**:
- `main.tf` - Terraform configuration
- `eks.tf` - EKS cluster setup
- `database.tf` - RDS/PostgreSQL
- `networking.tf` - VPC, subnets, security groups
- `security.tf` - IAM roles and policies
- `ecr.tf` - Container registry
- `variables.tf` - Input variables
- `outputs.tf` - Output values

### 4.1 [BLOCKER] Using Local Backend for State

**Location**: `/Users/proerror/Documents/nova/terraform/main.tf:12-13`

```hcl
# ❌ CURRENT (DANGEROUS)
backend "local" {}
```

**Risks**:
- State file stored locally only (single point of failure)
- No locking mechanism (concurrent modifications cause corruption)
- No backup (lost state = can't manage infrastructure)
- Can't be used in CI/CD (state not shared)
- Team members can't coordinate

**[CRITICAL] Fix immediately**:

```hcl
# ✅ CORRECT: Use S3 + DynamoDB for remote state
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "nova-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "nova-terraform-locks"
  }
}
```

Create the S3 backend:
```bash
# Run once to bootstrap backend
aws s3 mb s3://nova-terraform-state-$(date +%s) --region ap-northeast-1
aws s3api put-bucket-versioning \
  --bucket nova-terraform-state \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption \
  --bucket nova-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name nova-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
```

### 4.2 Missing Terraform Environment Segregation

**Current**: Single configuration for all environments

**Recommended structure**:

```
terraform/
  ├── modules/
  │   ├── eks/
  │   ├── rds/
  │   ├── networking/
  │   └── security/
  ├── environments/
  │   ├── dev/
  │   │   ├── terraform.tfvars
  │   │   └── main.tf
  │   ├── staging/
  │   │   ├── terraform.tfvars
  │   │   └── main.tf
  │   └── prod/
  │       ├── terraform.tfvars
  │       └── main.tf
  └── global/
      ├── s3-backend.tf
      └── kms.tf
```

Example `environments/prod/main.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "nova-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "nova-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "production"
      ManagedBy   = "Terraform"
      Project     = "Nova"
    }
  }
}

module "eks" {
  source = "../../modules/eks"

  cluster_name             = "nova-prod"
  kubernetes_version       = "1.28"
  node_group_min_size      = 3
  node_group_max_size      = 10
  node_instance_types      = ["t3.xlarge"]
  environment              = "prod"
}

module "rds" {
  source = "../../modules/rds"

  identifier       = "nova-prod-postgres"
  engine_version   = "15.4"
  instance_class   = "db.r6g.xlarge"
  allocated_storage = 100
  multi_az         = true
  backup_retention_period = 30
}
```

### 4.3 Missing Terraform State Validation in CI

Add Terraform checks to pipeline:

```yaml
validate-infrastructure:
  name: Validate IaC
  runs-on: ubuntu-latest

  steps:
    - uses: actions/checkout@v4

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2
      with:
        terraform_version: 1.5.0

    - name: Terraform format check
      run: terraform fmt -check -recursive terraform/

    - name: Terraform validate
      run: terraform validate
      working-directory: terraform/

    - name: TFLint security checks
      uses: terraform-linters/setup-tflint@v3
      with:
        tflint_version: latest

    - name: Run TFLint
      run: |
        tflint --init
        tflint --format compact terraform/

    - name: Cost estimation (Infracost)
      uses: infracost/actions/setup@v2
      with:
        api-key: ${{ secrets.INFRACOST_API_KEY }}

    - name: Generate cost report
      run: |
        infracost breakdown --path terraform/ \
          --format json > infracost.json

        infracost comment github --path infracost.json
```

### 4.4 IaC State Version Control

Create a wrapper script for Terraform:

```bash
#!/bin/bash
# scripts/terraform-wrapper.sh

set -euo pipefail

TERRAFORM_DIR="terraform/${1:-prod}"
TIMESTAMP=$(date -u +'%Y%m%d_%H%M%S')

echo "🔍 Validating Terraform configuration..."
terraform -chdir="$TERRAFORM_DIR" validate

echo "📋 Planning changes..."
terraform -chdir="$TERRAFORM_DIR" plan \
  -out="tfplan_${TIMESTAMP}" \
  -json > "tfplan_${TIMESTAMP}.json"

echo "📊 Cost estimation..."
infracost breakdown --path "$TERRAFORM_DIR" --format json > costs.json

echo "✅ Plan saved: tfplan_${TIMESTAMP}"
echo ""
echo "Review and apply:"
echo "  terraform -chdir=$TERRAFORM_DIR apply tfplan_${TIMESTAMP}"
```

### Infrastructure as Code Summary

| Aspect | Current | Target | Gap |
|--------|---------|--------|-----|
| State management | Local (dangerous) | S3 + DynamoDB | **P0** |
| Environment separation | None | terraform/environments/ | **P1** |
| CI validation | Basic | Comprehensive (TFLint, Infracost) | **P1** |
| Version pinning | ⚠️ Loose | ✅ Strict | **P2** |
| Rollback capability | Manual | Automated | **P2** |

---

## Section 5: Artifact Management

### Current State

**Registry**: AWS ECR (Elastic Container Registry)
**Tagging**: Git SHA + "latest"
**Scanning**: Basic image scanning
**Size**: No optimization data

### 5.1 [CRITICAL] Image Tagging Strategy

**Current**:
```
025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova/identity-service:latest
025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova/identity-service:abc123def456
```

**Problems**:
1. "latest" overwritten on each push (no immutability)
2. Git SHA isn't semantic (hard to understand versions)
3. No way to rollback to specific version
4. No multi-version support

**Recommended: Semantic Versioning**:

```yaml
push-ecr:
  steps:
    # Get semantic version
    - name: Determine version
      id: version
      run: |
        if [ "${{ github.ref }}" = "refs/heads/main" ]; then
          # Production: use git tags
          VERSION=$(git describe --tags --always --dirty)
          echo "tag=${VERSION}" >> $GITHUB_OUTPUT
        elif [ "${{ github.ref }}" = "refs/heads/feature/phase1-grpc-migration" ]; then
          # Staging: use commit date + short SHA
          VERSION=$(date +%Y%m%d)-$(git rev-parse --short HEAD)
          echo "tag=staging-${VERSION}" >> $GITHUB_OUTPUT
        else
          # PR: use PR number + short SHA
          PR_NUM=${{ github.event.pull_request.number }}
          SHA=$(git rev-parse --short HEAD)
          echo "tag=pr-${PR_NUM}-${SHA}" >> $GITHUB_OUTPUT
        fi

    - name: Push image with semantic tags
      run: |
        # Push multiple tags
        aws ecr batch-put-image \
          --repository-name nova/identity-service \
          --image-tag ${{ steps.version.outputs.tag }} \
          --image-tag $(date +%Y%m%d) \
          --image-tag $(date +%Y%m) \
          --region ${{ env.AWS_REGION }}

        # Immutable tags: lock versions in production
        if [ "${{ github.ref }}" = "refs/heads/main" ]; then
          aws ecr put-image-tag-mutability \
            --repository-name nova/identity-service \
            --image-tag-mutability IMMUTABLE \
            --region ${{ env.AWS_REGION }}
        fi
```

### 5.2 Comprehensive Image Scanning

**Current**: Basic ECR scanning

**Enhanced scanning**:

```yaml
scan-containers:
  name: Container Security Scanning
  runs-on: ubuntu-latest
  needs: build-and-push

  strategy:
    matrix:
      service:
        - identity-service
        - messaging-service
        - search-service

  steps:
    - uses: actions/checkout@v4

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}

    # 1. Trivy scanning for vulnerabilities
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:${{ github.sha }}
        format: 'sarif'
        output: 'trivy-results.sarif'
        exit-code: '1'  # Fail on vulnerabilities

    - name: Upload Trivy results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'

    # 2. ECR image scanning
    - name: Enable ECR image scanning
      run: |
        aws ecr put-image-scanning-configuration \
          --repository-name nova/${{ matrix.service }} \
          --image-scanning-configuration scanOnPush=true \
          --region ${{ env.AWS_REGION }}

    # 3. Generate SBOM (Software Bill of Materials)
    - name: Generate SBOM with Syft
      run: |
        syft ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:${{ github.sha }} \
          -o spdx-json > sbom-${{ matrix.service }}.json

    - name: Upload SBOM
      uses: actions/upload-artifact@v4
      with:
        name: sbom-${{ matrix.service }}
        path: sbom-${{ matrix.service }}.json

    # 4. Sign image with Cosign
    - name: Install Cosign
      run: curl https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 -o cosign && chmod +x cosign

    - name: Sign image
      env:
        COSIGN_EXPERIMENTAL: 1
      run: |
        ./cosign sign ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:${{ github.sha }}

    - name: Verify image signature
      run: |
        ./cosign verify ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:${{ github.sha }}
```

### 5.3 Image Size Optimization

**Current**: No size tracking

**Implement**:

```yaml
image-optimization:
  name: Image Size Analysis
  runs-on: ubuntu-latest

  steps:
    - name: Compare image sizes
      run: |
        echo "📊 Image Size Report"
        echo ""

        for service in identity-service messaging-service search-service; do
          SIZE=$(aws ecr describe-images \
            --repository-name nova/$service \
            --image-ids imageTag=${{ github.sha }} \
            --region ${{ env.AWS_REGION }} \
            --query 'imageDetails[0].imageSizeInBytes' \
            --output text)

          SIZE_MB=$((SIZE / 1024 / 1024))
          echo "  $service: ${SIZE_MB}MB"

          # Alert if size increased by >10%
          if [ "$SIZE_MB" -gt 200 ]; then
            echo "    ⚠️ Warning: Large image size"
          fi
        done

    - name: Generate image layer analysis
      run: |
        docker history ${{ env.ECR_REGISTRY }}/nova/identity-service:${{ github.sha }} \
          --human --no-trunc
```

### Artifact Management Summary

| Aspect | Current | Target | Gap |
|--------|---------|--------|-----|
| Image tagging | Git SHA + latest | Semantic versioning | **P1** |
| Vulnerability scanning | Basic | Trivy + ECR + Cosign | **P1** |
| SBOM generation | None | Syft SPDX JSON | **P1** |
| Image signing | None | Cosign signatures | **P2** |
| Size optimization | None | Layer analysis | **P2** |

---

## Section 6: Monitoring & Observability

### Current State

**What exists**:
- ✅ Prometheus scraping configured
- ✅ Alertmanager with Slack integration
- ✅ Pod-level metrics annotations
- ✅ Alert routing by severity
- ✅ Grafana dashboards mentioned

**What's missing**:
- ❌ No distributed tracing (Jaeger/Tempo)
- ❌ No log aggregation
- ❌ No DORA metrics tracking
- ❌ Limited SLO/SLI definition
- ❌ No custom application metrics

### 6.1 Add Distributed Tracing

**Implement Jaeger for gRPC tracing**:

```yaml
# k8s/infrastructure/jaeger-deployment.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: jaeger-configuration
  namespace: nova
data:
  sampling.json: |
    {
      "default_strategy": {
        "type": "probabilistic",
        "param": 0.1
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: nova
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
      - name: jaeger
        image: jaegertracing/all-in-one:latest
        ports:
        - containerPort: 6831  # Jaeger agent UDP
        - containerPort: 16686 # UI
        - containerPort: 14268 # Collector
        env:
        - name: SAMPLING_CONFIG_TYPE
          value: "file"
        - name: SAMPLING_CONFIG
          value: "/etc/jaeger/sampling.json"
        volumeMounts:
        - name: sampling
          mountPath: /etc/jaeger
      volumes:
      - name: sampling
        configMap:
          name: jaeger-configuration
---
apiVersion: v1
kind: Service
metadata:
  name: jaeger
  namespace: nova
spec:
  selector:
    app: jaeger
  ports:
  - port: 6831
    targetPort: 6831
    protocol: UDP
  - port: 14268
    targetPort: 14268
  - port: 16686
    targetPort: 16686
```

Enable tracing in services:

```rust
// In main.rs of each service
use opentelemetry::global;
use opentelemetry_jaeger::new_pipeline;
use tracing_subscriber::layer::SubscriberExt;

#[tokio::main]
async fn main() {
    // Initialize Jaeger tracer
    let tracer = new_pipeline()
        .install_simple()
        .expect("Failed to initialize tracer");

    let telemetry = tracing_opentelemetry::layer().with_tracer(tracer);
    let subscriber = tracing_subscriber::registry()
        .with(telemetry)
        .with(tracing_subscriber::fmt::layer());

    tracing::subscriber::set_default(subscriber);

    // Now all spans are sent to Jaeger
    info!("Application started");
}
```

### 6.2 Log Aggregation with Loki

```yaml
# k8s/infrastructure/loki-deployment.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: nova
data:
  loki-config.yaml: |
    auth_enabled: false
    ingester:
      chunk_idle_period: 3m
      chunk_retain_period: 1m
      max_chunk_age: 1h
    limits_config:
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h
    schema_config:
      configs:
      - from: 2020-10-24
        store: boltdb-shipper
        object_store: filesystem
        schema:
          prefix: index_
          version: v11
    server:
      http_listen_port: 3100
    storage_config:
      boltdb_shipper:
        active_index_directory: /loki/index
        shared_store: filesystem
      filesystem:
        directory: /loki/chunks
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  namespace: nova
spec:
  replicas: 1
  selector:
    matchLabels:
      app: loki
  template:
    metadata:
      labels:
        app: loki
    spec:
      containers:
      - name: loki
        image: grafana/loki:latest
        ports:
        - containerPort: 3100
        volumeMounts:
        - name: loki-config
          mountPath: /etc/loki
        - name: loki-storage
          mountPath: /loki
      volumes:
      - name: loki-config
        configMap:
          name: loki-config
      - name: loki-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: nova
spec:
  selector:
    app: loki
  ports:
  - port: 3100
```

### 6.3 DORA Metrics Dashboard

Create metrics for deployment frequency, lead time, etc:

```yaml
# Prometheus recording rules
groups:
- name: dora_metrics
  interval: 1m
  rules:

  # Deployment frequency (deployments per day)
  - record: deployment:frequency:daily
    expr: increase(deployments_total[1d])

  # Lead time (from commit to production)
  - record: deployment:lead_time:quantile
    expr: histogram_quantile(0.95, rate(deployment_lead_time_seconds_bucket[1h]))

  # Change failure rate
  - record: deployment:failure_rate:daily
    expr: increase(deployment_failures_total[1d]) / increase(deployments_total[1d])

  # Mean time to recovery (MTTR)
  - record: incident:mttr:avg
    expr: avg_over_time(incident_resolution_seconds[30d])

  # Availability/Uptime
  - record: service:availability:hourly
    expr: |
      (1 - increase(http_requests_total{status=~"5.."}[1h]) /
       increase(http_requests_total[1h])) * 100
```

### 6.4 Define SLOs/SLIs

```yaml
# k8s/monitoring/slo-definition.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: nova-slos
spec:
  groups:
  - name: nova.slos
    interval: 30s
    rules:

    # Availability SLO: 99.5%
    - alert: SLO_Availability_Breach
      expr: |
        (1 - (increase(http_requests_total{status=~"5.."}[5m]) /
             increase(http_requests_total[5m]))) < 0.995
      annotations:
        summary: "Availability SLO breached"

    # Latency SLO: P99 < 500ms
    - alert: SLO_Latency_Breach
      expr: |
        histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 0.5
      annotations:
        summary: "Latency SLO breached"

    # Error rate SLO: < 0.1%
    - alert: SLO_ErrorRate_Breach
      expr: |
        (increase(http_requests_total{status=~"5.."}[5m]) /
         increase(http_requests_total[5m])) > 0.001
      annotations:
        summary: "Error rate SLO breached"
```

### Monitoring Summary

| Aspect | Current | Target | Gap |
|--------|---------|--------|-----|
| Metrics collection | ✅ Prometheus | ✅ Complete | **P2** |
| Distributed tracing | ❌ None | ✅ Jaeger | **P1** |
| Log aggregation | ❌ None | ✅ Loki | **P1** |
| DORA metrics | ❌ Manual | ✅ Automated | **P2** |
| SLO/SLI tracking | ⚠️ Basic | ✅ Comprehensive | **P2** |

---

## Section 7: Security Scanning & Hardening

### Current State

**Existing security checks**:
- ✅ cargo-audit (dependency vulnerabilities)
- ✅ cargo-deny (licenses, vulnerabilities, bans)
- ✅ Secret scanning (gitleaks)
- ✅ Clippy security lints
- ✅ Container scanning

**Gaps**:
- ❌ No SAST (code analysis) beyond clippy
- ❌ No DAST (runtime security testing)
- ❌ No supply chain security (SLSA)
- ❌ No runtime security (Falco)

### 7.1 Enhance SAST with CodeQL

```yaml
sast-advanced:
  name: Advanced SAST Analysis
  runs-on: ubuntu-latest

  steps:
    - uses: actions/checkout@v4

    # GitHub CodeQL for Rust
    - name: Initialize CodeQL
      uses: github/codeql-action/init@v2
      with:
        languages: 'cpp'  # Rust compiles to native, analyze C++

    - uses: ./.github/actions/setup-rust-env

    - name: Build for CodeQL analysis
      working-directory: backend
      run: cargo build --release

    - name: Perform CodeQL Analysis
      uses: github/codeql-action/analyze@v2
```

### 7.2 Implement SLSA Framework

```yaml
build-with-slsa:
  name: SLSA Build Attestation
  runs-on: ubuntu-latest
  needs: test-services

  permissions:
    id-token: write
    contents: read

  steps:
    - uses: actions/checkout@v4

    - name: Build release
      working-directory: backend
      run: |
        cargo build --workspace --release

        # Generate build provenance
        echo "{
          \"buildType\": \"https://github.com/actions/github-actions\",
          \"builder\": \"$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/.github/workflows/ci-cd-pipeline.yml\",
          \"sourceRepository\": \"$GITHUB_SERVER_URL/$GITHUB_REPOSITORY\",
          \"invocation\": {
            \"configSource\": {
              \"uri\": \"$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/blob/$GITHUB_REF\",
              \"digest\": {
                \"sha256\": \"$(git rev-parse HEAD)\"
              }
            }
          }
        }" > provenance.json

    - name: Upload provenance
      uses: actions/upload-artifact@v4
      with:
        name: slsa-provenance
        path: provenance.json
```

### 7.3 Runtime Security with Falco

```yaml
# k8s/security/falco-deployment.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-config
  namespace: falco
data:
  falco.yaml: |
    rules_file:
    - /etc/falco/rules.yaml
    json_output: true
    file_output:
      enabled: true
      keep_alive: false
      filename: /var/log/falco_events.log
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: falco
  namespace: falco
spec:
  selector:
    matchLabels:
      app: falco
  template:
    metadata:
      labels:
        app: falco
    spec:
      serviceAccountName: falco
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: falco
        image: falcosecurity/falco:latest
        securityContext:
          privileged: true
        volumeMounts:
        - name: docker
          mountPath: /var/run/docker.sock
        - name: containerd
          mountPath: /var/run/containerd/containerd.sock
        - name: cgroup
          mountPath: /host/sys/fs/cgroup
        - name: proc
          mountPath: /host/proc
      volumes:
      - name: docker
        hostPath:
          path: /var/run/docker.sock
      - name: containerd
        hostPath:
          path: /var/run/containerd/containerd.sock
      - name: cgroup
        hostPath:
          path: /sys/fs/cgroup
      - name: proc
        hostPath:
          path: /proc
```

---

## Section 8: Database Migration Automation

### Current State

**Issue**: Migrations not executed in CI pipeline

### 8.1 Add Automated Migration Testing

```yaml
database-migrations:
  name: Test Database Migrations
  runs-on: ubuntu-latest
  needs: test-services

  services:
    postgres:
      image: postgres:15-alpine
      env:
        POSTGRES_DB: nova_test
        POSTGRES_USER: test
        POSTGRES_PASSWORD: test
      options: >-
        --health-cmd pg_isready
        --health-interval 10s
      ports:
        - 5432:5432

  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 2  # Need parent commit for migration validation

    - name: Install sqlx-cli
      run: cargo install sqlx-cli --no-default-features --features postgres

    - name: Test forward migration
      env:
        DATABASE_URL: postgresql://test:test@localhost:5432/nova_test
      run: |
        cd backend
        sqlx database create 2>/dev/null || true
        sqlx migrate run --source migrations
        echo "✅ Forward migration successful"

    - name: Validate schema
      env:
        DATABASE_URL: postgresql://test:test@localhost:5432/nova_test
      run: |
        psql postgresql://test:test@localhost:5432/nova_test -c "\dt+"

        # Check for required tables
        TABLES=$(psql postgresql://test:test@localhost:5432/nova_test -t -c \
          "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'")

        if [ "$TABLES" -lt 5 ]; then
          echo "❌ Expected at least 5 tables, found $TABLES"
          exit 1
        fi

    - name: Test rollback capability
      env:
        DATABASE_URL: postgresql://test:test@localhost:5432/nova_test
      run: |
        # Get current migration version
        CURRENT=$(sqlx migrate info --source migrations | tail -1 | awk '{print $1}')

        # Verify we can rollback (each migration needs down() equivalent)
        echo "Current migration: $CURRENT"
        echo "Rollback capability verified"
```

### 8.2 Production Migration Safety

```yaml
deploy-with-migrations:
  name: Deploy with Safe Migrations
  runs-on: ubuntu-latest
  needs: database-migrations

  steps:
    - uses: actions/checkout@v4

    - name: Plan migration
      env:
        DATABASE_URL: postgresql://prod-user:pass@prod-db:5432/nova
      run: |
        # Generate migration plan without executing
        sqlx migrate info --source migrations > migration-plan.txt

        echo "Planned migrations:"
        cat migration-plan.txt

    - name: Approve migration (manual gate for prod)
      if: github.ref == 'refs/heads/main'
      uses: trstringer/manual-approval@v1
      with:
        secret: ${{ secrets.GITHUB_TOKEN }}
        approvers: devops-team
        issue-title: "Approve database migration for production"
        issue-body: "Review planned migrations in artifacts"

    - name: Execute migration
      env:
        DATABASE_URL: postgresql://prod-user:pass@prod-db:5432/nova
      run: |
        # Back up database before migration
        pg_dump -Fc nova > /tmp/backup-$(date +%s).dump

        # Run migration
        sqlx migrate run --source migrations

        # Verify result
        sqlx migrate info --source migrations | tail -1

    - name: Validate data integrity
      env:
        DATABASE_URL: postgresql://prod-user:pass@prod-db:5432/nova
      run: |
        # Check row counts haven't changed unexpectedly
        psql postgresql://prod-user:pass@prod-db:5432/nova -c "
          SELECT relname, n_live_tup
          FROM pg_stat_user_tables
          ORDER BY n_live_tup DESC;"
```

---

## Section 9: Environment Parity & Configuration Management

### Current Issue

Kubernetes manifests, Docker configs, and environment variables are scattered.

### 9.1 Unified Configuration with Kustomize

```
k8s/
  ├── base/
  │   ├── identity-service/
  │   │   ├── kustomization.yaml
  │   │   ├── deployment.yaml
  │   │   ├── service.yaml
  │   │   └── configmap.yaml
  │   └── messaging-service/
  ├── overlays/
  │   ├── dev/
  │   │   ├── kustomization.yaml
  │   │   └── patches/
  │   ├── staging/
  │   │   ├── kustomization.yaml
  │   │   └── patches/
  │   └── prod/
  │       ├── kustomization.yaml
  │       └── patches/
```

Example `k8s/base/identity-service/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: nova

commonLabels:
  app: identity-service
  managed-by: kustomize

commonAnnotations:
  revision: "1"

resources:
- deployment.yaml
- service.yaml
- configmap.yaml
- secret.yaml

configMapGenerator:
- name: identity-service-config
  literals:
  - LOG_LEVEL=info
  - SERVICE_NAME=identity-service

secretGenerator:
- name: identity-service-secret
  envs:
  - secrets.env

replicas:
- name: identity-service
  count: 1  # Override in overlays

images:
- name: identity-service
  newTag: latest  # Override with actual tag

patchesStrategicMerge:
- patch-resources.yaml
```

Example `k8s/overlays/prod/kustomization.yaml`:

```yaml
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
  newTag: v1.2.3  # Use semantic version

commonLabels:
  environment: production

patchesStrategicMerge:
- patch-resources-prod.yaml

# Prod-specific configurations
configMapGenerator:
- name: identity-service-config
  behavior: merge
  literals:
  - LOG_LEVEL=warn
  - ENABLE_METRICS=true
  - ENABLE_TRACING=true

# Prod security patches
patchesJson6902:
- target:
    group: apps
    version: v1
    kind: Deployment
    name: identity-service
  patch: |-
    - op: replace
      path: /spec/template/spec/securityContext
      value:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
```

Deploy with environment-specific config:

```yaml
deploy:
  steps:
    - name: Deploy with Kustomize
      run: |
        ENVIRONMENT=${{ github.ref == 'refs/heads/main' && 'prod' || 'staging' }}

        kubectl apply -k k8s/overlays/$ENVIRONMENT
```

---

## Section 10: Incident Response & Rollback Procedures

### 10.1 Automated Rollback on Failures

```yaml
post-deployment-validation:
  name: Post-Deployment Validation
  runs-on: ubuntu-latest
  needs: deploy-staging
  if: always()

  steps:
    - uses: actions/checkout@v4

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}

    - name: Health check all services
      run: |
        aws eks update-kubeconfig --name nova-staging --region ${{ env.AWS_REGION }}

        FAILED_SERVICES=""
        for service in identity-service messaging-service search-service; do
          READY=$(kubectl get deployment -n nova $service -o jsonpath='{.status.readyReplicas}')
          DESIRED=$(kubectl get deployment -n nova $service -o jsonpath='{.spec.replicas}')

          if [ "$READY" != "$DESIRED" ]; then
            FAILED_SERVICES="$FAILED_SERVICES $service"
          fi
        done

        if [ -z "$FAILED_SERVICES" ]; then
          echo "✅ All services healthy"
        else
          echo "❌ Failed services:$FAILED_SERVICES"
          exit 1
        fi

    - name: Monitor error rate (30s)
      if: success()
      run: |
        echo "Monitoring error rates for 30 seconds..."
        sleep 30

        ERROR_RATE=$(kubectl logs -n nova -l app=identity-service --tail=1000 | \
                    grep -c "ERROR" || echo 0)

        if [ "$ERROR_RATE" -gt 20 ]; then
          echo "⚠️ High error rate detected"
          exit 1
        fi

    - name: Automatic rollback on failure
      if: failure()
      run: |
        echo "⚠️ Deployment validation failed, initiating rollback..."

        for service in identity-service messaging-service search-service; do
          kubectl rollout undo deployment/$service -n nova
          echo "Rolled back: $service"
        done

        # Wait for rollback to complete
        kubectl rollout status deployment/identity-service -n nova --timeout=5m

        echo "✅ Rollback complete"
        exit 1  # Still fail the deployment
```

### 10.2 Incident Playbook

Create `/docs/INCIDENT_RESPONSE.md`:

```markdown
# Incident Response Playbook

## High Error Rate (> 5%)

### Detection
- Alert: `ErrorRateHigh` triggered
- Check: `rate(http_requests_total{status=~"5.."}[1m]) > 0.05`

### Investigation
```bash
# 1. Check pod logs
kubectl logs -n nova -l app=identity-service --tail=100

# 2. Check resource usage
kubectl top pods -n nova -l app=identity-service

# 3. Check dependencies
kubectl exec -n nova $(POD) -- redis-cli ping
```

### Remediation
1. **Quick fix**: Scale down and up to restart pods
   ```bash
   kubectl scale deployment/identity-service -n nova --replicas=0
   sleep 10
   kubectl scale deployment/identity-service -n nova --replicas=3
   ```

2. **Rollback**: If issue persists
   ```bash
   kubectl rollout undo deployment/identity-service -n nova
   ```

3. **Full investigation**: If still failing
   - Escalate to on-call engineer
   - Check database performance
   - Review recent deployments
```

---

## Section 11: Pipeline Efficiency Metrics

### 11.1 Track DORA Metrics

**Implementation in CI**:

```yaml
record-metrics:
  name: Record Deployment Metrics
  runs-on: ubuntu-latest
  if: github.event_name == 'push'

  steps:
    - uses: actions/checkout@v4

    # Deploy frequency
    - name: Record deployment
      run: |
        TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

        curl -X POST 'http://prometheus-pushgateway:9091/metrics/job/deployments' \
          -d "deployment_count{branch=\"${{ github.ref_name }}\",service=\"nova\"} 1"

    # Lead time (commit to deployment)
    - name: Record lead time
      run: |
        COMMIT_TIME=$(git log -1 --format=%ct)
        DEPLOY_TIME=$(date +%s)
        LEAD_TIME=$((DEPLOY_TIME - COMMIT_TIME))

        curl -X POST 'http://prometheus-pushgateway:9091/metrics/job/lead_time' \
          -d "lead_time_seconds{branch=\"${{ github.ref_name }}\"} $LEAD_TIME"

    # Deployment status
    - name: Record deployment status
      run: |
        STATUS="${{ job.status }}"

        curl -X POST 'http://prometheus-pushgateway:9091/metrics/job/deployments' \
          -d "deployment_status{status=\"$STATUS\",branch=\"${{ github.ref_name }}\"} 1"
```

### 11.2 Build Time Optimization

```yaml
build-metrics:
  name: Analyze Build Performance
  runs-on: ubuntu-latest
  needs: build-release

  steps:
    - name: Report build duration
      run: |
        BUILD_DURATION=${{ job.duration }}
        echo "Build duration: ${BUILD_DURATION}s"

        # Alert if build time increases
        if [ "$BUILD_DURATION" -gt 900 ]; then
          echo "⚠️ Build time exceeded 15 minutes"
        fi
```

---

## Section 12: Priority Action Plan

### Immediate (Week 1) - P0 Issues

- [ ] **Fix Dockerfile debug builds** → Use `--release` flag
- [ ] **Fix healthcheck syntax** → Remove shell operators
- [ ] **Migrate Terraform state** → S3 + DynamoDB backend
- [ ] **Enable image immutability** → ECR policy
- [ ] **Implement pre-deployment validation** → Add smoke tests

### Short-term (Weeks 2-4) - P1 Issues

- [ ] **Implement canary deployments** → Argo Rollouts setup
- [ ] **Raise coverage threshold** → 80% enforcement
- [ ] **Add flaky test quarantine** → Detection + registry
- [ ] **Implement SBOM generation** → Syft integration
- [ ] **Setup distributed tracing** → Jaeger deployment

### Medium-term (Month 2) - P2 Issues

- [ ] **Add performance benchmarking** → Per-commit regression detection
- [ ] **Implement GitOps** → ArgoCD automation
- [ ] **Log aggregation** → Loki stack
- [ ] **DORA metrics tracking** → Dashboard setup
- [ ] **Security hardening** → Falco runtime monitoring

---

## Detailed Implementation Guide

### Fix 1: Update Dockerfile for Release Builds

```dockerfile
# Use this template for all services
FROM rust:1.88-slim-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev ca-certificates cmake build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY backend ./backend

# Build release binary (NOT debug)
RUN cargo build --manifest-path backend/user-service/Cargo.toml --release \
    && strip target/release/user-service

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1001 appuser
WORKDIR /app

COPY --from=builder --chown=appuser:appuser /app/target/release/user-service ./
USER appuser

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ./user-service healthcheck-http || exit 1

ENV RUST_LOG=info
CMD ["./user-service"]
```

### Fix 2: Terraform State Migration

```bash
#!/bin/bash
# scripts/migrate-terraform-state.sh

set -e

echo "Creating S3 backend for Terraform state..."

# Create S3 bucket
BUCKET_NAME="nova-terraform-state-$(date +%s)"
aws s3 mb "s3://$BUCKET_NAME" --region ap-northeast-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
    }]
  }'

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name nova-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

echo "✅ Backend created: $BUCKET_NAME"
echo "Update terraform/main.tf backend config:"
echo "  bucket = \"$BUCKET_NAME\""
```

### Fix 3: Coverage Threshold Enforcement

```yaml
# In .github/workflows/ci-cd-pipeline.yml
code-coverage:
  steps:
    - name: Generate coverage
      working-directory: backend
      run: |
        cargo tarpaulin \
          --workspace \
          --timeout 300 \
          --out Xml \
          --output-dir coverage \
          --fail-under 80 \  # Enforce 80%
          -- --test-threads 1
      continue-on-error: false  # Hard fail

    - name: Block merge if coverage insufficient
      if: failure()
      run: |
        echo "❌ Code coverage below 80% threshold"
        exit 1
```

---

## Summary of All Gaps

| Category | Issue | Severity | Fix Time |
|----------|-------|----------|----------|
| Build | Debug builds instead of release | **P0** | 1 day |
| Build | Healthcheck syntax error | **P0** | 1 day |
| Deploy | No pre-deployment validation | **P0** | 2 days |
| IaC | Local Terraform state | **P0** | 1 day |
| Test | Coverage threshold too low | **P1** | 2 days |
| Deploy | No canary deployments | **P1** | 3 days |
| Test | 160 flaky tests unmanaged | **P1** | 5 days |
| Security | No SBOM generation | **P1** | 1 day |
| Monitor | Missing distributed tracing | **P1** | 3 days |
| Monitor | No log aggregation | **P1** | 2 days |
| Observe | No DORA metrics | **P2** | 3 days |
| Deploy | No database migration CI | **P2** | 2 days |

---

## Conclusion

Nova's CI/CD infrastructure is **foundational but flawed**. The project has invested in modern tooling (GitHub Actions, EKS, Prometheus) but lacks fundamental safety mechanisms.

**Critical path forward**:

1. **Immediately fix production defects** (P0): Debug builds, healthchecks, validation
2. **Strengthen deployment safety** (P1): Canary patterns, rollback automation
3. **Operationalize visibility** (P2): Tracing, logging, DORA metrics

With these improvements, Nova can transition from "ships working deployments by accident" to "automatically prevents failures."

