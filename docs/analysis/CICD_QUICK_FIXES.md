# Nova CI/CD - Quick Fixes & Implementation Priority

This document provides specific, actionable fixes for the most critical CI/CD defects identified in the review.

---

## PRIORITY 1: Critical Production Defects (Do First)

### Fix 1.1: Update All Dockerfiles to Use Release Builds

**Files to update**:
- `backend/Dockerfile`
- `backend/Dockerfile.messaging`
- `backend/Dockerfile.template`

**Current problem**:
```dockerfile
RUN cargo build --manifest-path user-service/Cargo.toml  # ❌ Debug build
COPY --from=builder /app/target/debug/user-service      # ❌ Huge binary
```

**Fix**:
```dockerfile
# Stage 1: Builder
FROM rust:1.88-slim-bookworm AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY backend ./backend
COPY migrations ./migrations

# ✅ Build release with optimizations
RUN RUSTFLAGS="-C opt-level=3 -C lto=thin" \
    cargo build --release --bin user-service && \
    strip target/release/user-service

# Stage 2: Runtime
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1001 appuser
WORKDIR /app

# ✅ Copy release binary
COPY --from=builder --chown=appuser:appuser \
    /app/target/release/user-service ./user-service
COPY --chown=appuser:appuser migrations ./migrations

USER appuser
EXPOSE 8080

# ✅ Fix healthcheck syntax (remove ||)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD sh -c './user-service healthcheck-http || exit 1'

ENV RUST_LOG=info
CMD ["./user-service"]
```

**Impact**:
- Reduces image size: 250MB → 60MB (75% reduction)
- Faster startup: 50% reduction
- Lower AWS storage costs

**Timeline**: 1 day (one commit applies to all services)

---

### Fix 1.2: Update GitHub Actions to Build Release Images

**Location**: `.github/workflows/ci-cd-pipeline.yml` (lines 352-408)

**Update the build-and-push job**:

```yaml
build-and-push:
  timeout-minutes: 60
  name: Build and Push Docker Images
  runs-on: ubuntu-latest
  needs: setup-aws

  strategy:
    matrix:
      service:
        - user-service
        - auth-service
        - content-service
        # ... others
    max-parallel: 4
    fail-fast: false

  steps:
    - uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
      with:
        # Use inline cache driver for maximum speed
        driver-options: |
          image=moby/buildkit:latest
          network=host

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}

    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v2

    # ✅ Build release image with cache
    - name: Build and push image
      uses: docker/build-push-action@v6
      with:
        context: ./backend
        file: ./backend/Dockerfile
        push: true
        tags: |
          ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:${{ github.sha }}
          ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:latest
        # ✅ Use GitHub Actions cache for BuildKit
        cache-from: type=gha,scope=${{ matrix.service }}
        cache-to: type=gha,scope=${{ matrix.service }},mode=max
        # ✅ Build args for release
        build-args: |
          BUILD_TYPE=release
          RUST_VERSION=1.88

    - name: Verify image size
      run: |
        IMAGE_SIZE=$(aws ecr describe-images \
          --repository-name nova/${{ matrix.service }} \
          --image-ids imageTag=${{ github.sha }} \
          --region ${{ env.AWS_REGION }} \
          --query 'imageDetails[0].imageSizeInBytes' \
          --output text)

        SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))
        echo "📦 Image size: ${SIZE_MB}MB"

        # Alert if image is unexpectedly large
        if [ "$SIZE_MB" -gt 200 ]; then
          echo "⚠️ WARNING: Large image (debug build?)"
        fi
```

**Timeline**: 2 hours (modify one workflow file)

---

### Fix 1.3: Migrate Terraform State to S3

**Location**: `terraform/main.tf` (lines 1-20)

**BEFORE**:
```hcl
# ❌ DANGEROUS: Local backend
terraform {
  backend "local" {}
}
```

**AFTER**:
```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # ✅ Remote S3 backend with locking
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
      Project     = "Nova"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
```

**Bootstrap script** (`scripts/bootstrap-terraform-backend.sh`):

```bash
#!/bin/bash
set -e

echo "🔧 Bootstrapping Terraform S3 backend..."

REGION="ap-northeast-1"
BUCKET_NAME="nova-terraform-state"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Check if bucket already exists
if aws s3 ls "s3://$BUCKET_NAME" 2>/dev/null; then
  echo "✅ Bucket $BUCKET_NAME already exists"
else
  echo "Creating bucket $BUCKET_NAME..."
  aws s3 mb "s3://$BUCKET_NAME" --region $REGION

  # Enable versioning
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

  # Enable default encryption
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }'

  # Block public access
  aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  echo "✅ Bucket created and secured"
fi

# Create DynamoDB table for state locking
if aws dynamodb describe-table --table-name nova-terraform-locks --region $REGION 2>/dev/null; then
  echo "✅ DynamoDB table nova-terraform-locks already exists"
else
  echo "Creating DynamoDB table for state locking..."
  aws dynamodb create-table \
    --table-name nova-terraform-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

  # Wait for table to be active
  aws dynamodb wait table-exists \
    --table-name nova-terraform-locks \
    --region $REGION

  echo "✅ DynamoDB table created"
fi

echo "🎉 Backend bootstrap complete"
echo ""
echo "Next steps:"
echo "1. Run: cd terraform && terraform init"
echo "2. Verify: terraform state list"
```

**Timeline**:
- Setup: 30 minutes
- Migration: 1 day (requires coordination)

---

## PRIORITY 2: Deployment Safety (Week 1-2)

### Fix 2.1: Add Pre-Deployment Validation

**Create new workflow file**: `.github/workflows/pre-deployment-validation.yml`

```yaml
name: Pre-Deployment Validation

on:
  workflow_run:
    workflows: ["Build and Push Docker Images"]
    types: [completed]

jobs:
  validate-deployment:
    name: Validate Deployment Prerequisites
    runs-on: ubuntu-latest
    if: github.event.workflow_run.conclusion == 'success'

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-northeast-1

      - name: Setup kubeconfig
        run: |
          aws eks update-kubeconfig \
            --name nova-staging \
            --region ap-northeast-1

      # 1. Verify cluster health
      - name: Cluster health check
        run: |
          echo "🏥 Checking cluster health..."

          # Check nodes are ready
          READY_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' | wc -w)
          TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)

          if [ "$READY_NODES" -lt "$TOTAL_NODES" ]; then
            echo "❌ Not all nodes ready: $READY_NODES/$TOTAL_NODES"
            exit 1
          fi

          echo "✅ All $TOTAL_NODES nodes healthy"

      # 2. Verify dependencies
      - name: Dependency health check
        run: |
          echo "📦 Checking dependencies..."

          # PostgreSQL
          PG_POD=$(kubectl get pod -n nova -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
          if [ -n "$PG_POD" ]; then
            kubectl exec -n nova "$PG_POD" -- pg_isready || {
              echo "❌ PostgreSQL not responding"
              exit 1
            }
            echo "✅ PostgreSQL ready"
          fi

          # Redis
          REDIS_POD=$(kubectl get pod -n nova -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
          if [ -n "$REDIS_POD" ]; then
            kubectl exec -n nova "$REDIS_POD" -- redis-cli ping || {
              echo "❌ Redis not responding"
              exit 1
            }
            echo "✅ Redis ready"
          fi

      # 3. Verify recent images exist
      - name: Image availability check
        env:
          COMMIT_SHA: ${{ github.event.workflow_run.head_commit.id }}
        run: |
          echo "📷 Verifying images..."

          for service in identity-service messaging-service search-service; do
            IMAGE_COUNT=$(aws ecr describe-images \
              --repository-name nova/$service \
              --image-ids imageTag=$COMMIT_SHA \
              --region ap-northeast-1 \
              --query 'length(imageDetails)' \
              --output text 2>/dev/null || echo 0)

            if [ "$IMAGE_COUNT" -eq 0 ]; then
              echo "❌ Image not found: $service:$COMMIT_SHA"
              exit 1
            fi

            echo "✅ Found: $service:$COMMIT_SHA"
          done

      # 4. Manifest validation
      - name: Kubernetes manifest validation
        run: |
          echo "🔍 Validating manifests..."

          # Validate syntax
          find k8s -name "*.yaml" -o -name "*.yml" | while read f; do
            kubectl apply -f "$f" --dry-run=client -o yaml > /dev/null || {
              echo "❌ Invalid manifest: $f"
              exit 1
            }
          done

          echo "✅ All manifests valid"

      - name: Slack notification
        if: always()
        run: |
          STATUS=${{ job.status }}
          EMOJI=$( [ "$STATUS" = "success" ] && echo "✅" || echo "❌" )

          curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
            -H 'Content-Type: application/json' \
            -d "{
              \"text\": \"$EMOJI Pre-deployment validation $STATUS\",
              \"blocks\": [{
                \"type\": \"section\",
                \"text\": {
                  \"type\": \"mrkdwn\",
                  \"text\": \"Pre-deployment validation $STATUS\"
                }
              }]
            }"
```

**Timeline**: 1 day

---

### Fix 2.2: Update AWS CodeBuild to Use Release Builds

**File**: `buildspec.yml` (lines 39-79)

**BEFORE**:
```yaml
  build:
    commands:
      - echo "🚀 开始构建所有服务..."
      - |
        for service in "${SERVICES[@]}"; do
          docker buildx build \
            --platform linux/amd64 \
            --push \
            -f "$service/Dockerfile" \
            -t "$IMAGE_TAG" \
            ./backend  # ❌ Uses debug build from Dockerfile
        done
```

**AFTER**:
```yaml
  build:
    commands:
      - echo "🚀 Building all services with release optimizations..."
      - |
        ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
        BUILD_FAILED=0

        for service in "${SERVICES[@]}"; do
          echo "📦 Building $service..."

          # ✅ Build with cache
          if docker buildx build \
            --platform linux/amd64 \
            --push \
            --cache-from=type=registry,ref=$ECR_REGISTRY/$ECR_REGISTRY_ALIAS/$service:buildcache \
            --cache-to=type=registry,ref=$ECR_REGISTRY/$ECR_REGISTRY_ALIAS/$service:buildcache,mode=max \
            --build-arg BUILD_TYPE=release \
            -f backend/Dockerfile \
            -t "$ECR_REGISTRY/$ECR_REGISTRY_ALIAS/$service:$COMMIT_SHA" \
            -t "$ECR_REGISTRY/$ECR_REGISTRY_ALIAS/$service:latest" \
            backend; then
            echo "✅ $service built successfully"

            # Verify image size
            SIZE=$(docker image inspect "$ECR_REGISTRY/$ECR_REGISTRY_ALIAS/$service:$COMMIT_SHA" \
              --format='{{.Size}}' | awk '{print int($1/1024/1024)}')
            echo "  Image size: ${SIZE}MB"
          else
            echo "❌ $service build failed"
            BUILD_FAILED=1
          fi
        done

        exit $BUILD_FAILED
```

**Timeline**: 2 hours

---

## PRIORITY 3: Test Coverage Enforcement (Week 2)

### Fix 3.1: Raise and Enforce Coverage Threshold

**File**: `.github/workflows/ci-cd-pipeline.yml` (lines 99-155)

**UPDATE**:

```yaml
code-coverage:
  timeout-minutes: 20
  name: Code Coverage Analysis
  runs-on: ubuntu-latest
  needs: test-services

  steps:
    - uses: actions/checkout@v4

    - uses: ./.github/actions/setup-rust-env
      with:
        cache-key-suffix: coverage

    - name: Install cargo-tarpaulin
      run: |
        if ! command -v cargo-tarpaulin &> /dev/null; then
          cargo install cargo-tarpaulin --version 0.8.3
        fi

    # ✅ Enforce 80% coverage
    - name: Generate coverage report
      working-directory: backend
      run: |
        cargo tarpaulin \
          --workspace \
          --timeout 300 \
          --out Xml \
          --output-dir coverage \
          --exclude-files 'target/*' \
          --fail-under 80 \  # ✅ Raised from 50 to 80
          -- --test-threads 1
      continue-on-error: false  # ✅ Hard fail on coverage breach

    # ✅ Per-service coverage check
    - name: Validate per-service coverage
      run: |
        echo "📊 Per-Service Coverage Analysis"
        echo ""

        THRESHOLD=75

        for service in user-service messaging-service search-service; do
          # Extract coverage from XML
          COVERAGE=$(grep "module name=\"$service\"" coverage/cobertura.xml | \
                    grep -oP 'line-rate="\K[0-9.]+' | head -1)

          if [ -z "$COVERAGE" ]; then
            echo "⚠️ $service: No coverage data found"
            continue
          fi

          PCT=$(echo "scale=1; $COVERAGE * 100" | bc)
          STATUS="✅"

          if (( $(echo "$COVERAGE < 0.75" | bc -l) )); then
            STATUS="❌"
            EXIT_CODE=1
          fi

          echo "$STATUS $service: $PCT%"
        done

        exit ${EXIT_CODE:-0}

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v4
      with:
        file: backend/coverage/cobertura.xml
        flags: backend
        fail_ci_if_error: true  # ✅ Fail if upload fails

    - name: Comment on PR with coverage
      if: github.event_name == 'pull_request'
      uses: actions/github-script@v7
      with:
        script: |
          const fs = require('fs');
          const coverage = fs.readFileSync('backend/coverage/cobertura.xml', 'utf-8');

          const match = coverage.match(/line-rate="([0-9.]+)"/);
          const coveragePercent = match ? (parseFloat(match[1]) * 100).toFixed(2) : 'N/A';

          github.rest.issues.createComment({
            issue_number: context.issue.number,
            owner: context.repo.owner,
            repo: context.repo.repo,
            body: `📊 Code Coverage: **${coveragePercent}%**\n\nThreshold: 80% ✅`
          });
```

**Timeline**: 4 hours

---

## PRIORITY 4: Container Security (Week 3)

### Fix 4.1: Add Image Signing & SBOM Generation

**Create**: `.github/workflows/container-security.yml`

```yaml
name: Container Security & SBOM

on:
  push:
    branches: [main, feature/phase1-grpc-migration]
    paths:
      - 'backend/**'
      - '.github/workflows/container-security.yml'

jobs:
  sbom-and-signing:
    name: Generate SBOM & Sign Images
    runs-on: ubuntu-latest
    needs: build-and-push

    strategy:
      matrix:
        service:
          - identity-service
          - messaging-service
          - search-service

    permissions:
      id-token: write  # For Cosign keyless signing
      contents: read

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-northeast-1

      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v2

      # ✅ Generate SBOM with Syft
      - name: Generate SBOM
        uses: anchore/sbom-action@v0
        with:
          image: ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:${{ github.sha }}
          artifact-name: sbom-${{ matrix.service }}.spdx.json
          output-file: sbom-${{ matrix.service }}.spdx.json

      - name: Upload SBOM to artifacts
        uses: actions/upload-artifact@v4
        with:
          name: sboms
          path: sbom-${{ matrix.service }}.spdx.json

      # ✅ Sign image with Cosign (keyless signing)
      - name: Install Cosign
        uses: sigstore/cosign-installer@v3

      - name: Sign container image
        env:
          COSIGN_EXPERIMENTAL: 1
        run: |
          cosign sign \
            ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:${{ github.sha }} \
            --yes

      # ✅ Verify signature
      - name: Verify image signature
        env:
          COSIGN_EXPERIMENTAL: 1
        run: |
          cosign verify \
            ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:${{ github.sha }}

      - name: Attach SBOM to image
        run: |
          cosign attach sbom \
            --sbom sbom-${{ matrix.service }}.spdx.json \
            ${{ env.ECR_REGISTRY }}/nova/${{ matrix.service }}:${{ github.sha }}
```

**Timeline**: 1 day

---

## Verification Checklist

After applying each fix, verify:

```bash
# Fix 1.1: Debug builds → Release
docker inspect nova/identity-service:latest | grep -i size
# Should be < 100MB, not 250MB+

# Fix 1.2: Healthcheck syntax
docker build -f backend/Dockerfile --no-cache backend
# Should complete without healthcheck errors

# Fix 1.3: Terraform state
aws s3 ls s3://nova-terraform-state
# Should list state file

# Fix 2.1: Pre-deployment validation
kubectl get nodes
kubectl get pods -n nova
# All should be in Running state

# Fix 3.1: Coverage threshold
cargo tarpaulin --workspace --fail-under 80
# Should fail if coverage < 80%

# Fix 4.1: Image signing
cosign verify $ECR_REGISTRY/nova/identity-service:latest
# Should verify successfully
```

---

## Implementation Order

**Week 1 (Critical Path)**:
1. ✅ Fix 1.1: Update Dockerfiles (1 day)
2. ✅ Fix 1.2: Update GitHub Actions (2 hours)
3. ✅ Fix 1.3: Migrate Terraform state (30 mins setup + 1 day coordination)

**Week 2 (Deployment Safety)**:
4. ✅ Fix 2.1: Pre-deployment validation (1 day)
5. ✅ Fix 2.2: Update CodeBuild (2 hours)

**Week 3 (Quality Gates)**:
6. ✅ Fix 3.1: Coverage enforcement (4 hours)

**Week 4 (Security)**:
7. ✅ Fix 4.1: SBOM & signing (1 day)

---

## Estimated Impact

| Fix | Issue | Impact | Effort |
|-----|-------|--------|--------|
| 1.1 | Debug builds | 75% smaller images, 50% faster | 1 day |
| 1.2 | CI/CD builds | Consistent release builds | 2h |
| 1.3 | State management | Safe, recoverable infrastructure | 1 day |
| 2.1 | Deployment safety | Prevent bad deployments | 1 day |
| 2.2 | Manual builds | Automated release builds | 2h |
| 3.1 | Coverage | Enforce quality gates | 4h |
| 4.1 | Security | Sign images, generate SBOM | 1 day |

**Total effort**: ~6 days (can be parallelized)

