# CI/CD Pipeline - Quick Reference

## Pipeline Stages at a Glance

```
┌─────────────────────────────────────────────────────────────────┐
│ Stage 1: Format & Lint          ~ 2-3 min (BLOCKING)           │
│ ↓                                                               │
│ Stage 2: Unit Tests (12 svc)    ~ 8-12 min (BLOCKING)          │
│ ↓                                                               │
│ Stage 3: Code Coverage          ~ 5-8 min (BLOCKING if <50%)   │
│ ↓                                                               │
│ Stage 4: Security Audit         ~ 3-5 min (WARNING only)       │
│ ↓                                                               │
│ Stage 5: Dependency Check       ~ 1-2 min (INFO only)          │
│ ↓                                                               │
│ Stage 6: Integration Tests      ~ 4-6 min (BLOCKING)           │
│ ↓                                                               │
│ Stage 7: Build Release          ~ 6-10 min (BLOCKING)          │
│ (IF PUSH) ↓                                                     │
│ Stage 8: Docker Build & Push    ~ 8-15 min (BLOCKING)          │
│ ↓                                                               │
│ Stage 9: Deploy to Staging      ~ 3-5 min (INFO)               │
│ ↓                                                               │
│ Stage 10: Smoke Tests           ~ 2 min (INFO)                 │
│ ↓                                                               │
│ Stage 11: Quality Report        ~ 1 min (REPORTING)            │
│ ↓                                                               │
│ Stage 12: Notifications         ~ 1 min (REPORTING)            │
│                                                                 │
│ Total time: ~15 min (PR), ~40 min (Push with deploy)           │
└─────────────────────────────────────────────────────────────────┘
```

## Quality Gates (What Blocks Merge)

| Gate | Tool | How to Fix |
|------|------|-----------|
| **Format** | `cargo fmt --all -- --check` | Run: `cargo fmt --all` |
| **Lint** | `cargo clippy -D warnings` | Fix clippy warnings |
| **Tests** | `cargo test --lib` | Write passing tests |
| **Coverage** | 50% minimum | Add tests (use tarpaulin to check) |
| **Build** | `cargo build --release` | Fix compilation errors |

## Pre-Commit Checklist

Before pushing, run locally:

```bash
# 1. Format code
cargo fmt --all

# 2. Check lint
cargo clippy --workspace --all-targets --all-features -- -D warnings

# 3. Run tests
cargo test --lib

# 4. Check coverage (optional, but recommended)
cargo install cargo-tarpaulin
cargo tarpaulin --workspace --out Xml
```

## Services Being Tested

All 12 services tested in parallel (6 at a time):

```
✓ auth-service
✓ user-service
✓ messaging-service
✓ content-service
✓ feed-service
✓ search-service
✓ media-service
✓ notification-service
✓ streaming-service
✓ video-service
✓ cdn-service
✓ events-service
```

## Testing a Single Service Locally

```bash
# Test auth-service only
cd backend/auth-service
cargo test --lib --all-features

# Test with output
cargo test --lib --all-features -- --nocapture

# Test specific test function
cargo test --lib test_name
```

## Code Coverage

### Check Coverage Locally

```bash
cargo install cargo-tarpaulin
cd backend
cargo tarpaulin --workspace --out Html
# Opens coverage report in browser
```

### Coverage Threshold
- **Minimum**: 50%
- **How to improve**: Add tests for untested code paths
- **Report**: Uploaded to Codecov with each push

## Security Checks

### What Gets Checked

1. **Vulnerabilities** (`cargo audit`)
   - Known CVEs in dependencies
   - Blocks if found

2. **Licenses** (`cargo deny`)
   - MIT, Apache 2.0: ✅ OK
   - GPL: ❌ Usually rejected
   - Unlicensed: ⚠️ Warning

3. **Outdated Dependencies** (`cargo outdated`)
   - Just informational
   - Won't block merge

### Run Locally

```bash
# Check vulnerabilities
cargo install cargo-audit
cargo audit

# Check licenses
cargo install cargo-deny
cargo deny check licenses

# Check advisories
cargo deny check advisories
```

## Common Failures & Fixes

### Formatting Error
```
error: code is not formatted
  run `cargo fmt` to format this file
```
**Fix**: `cargo fmt --all`

### Clippy Warning Denied
```
error: this is inefficient
  --> file.rs:X:Y
```
**Fix**: Apply the suggested fix or refactor

### Test Failed
```
test result: FAILED. failures:
  - test_name
```
**Fix**: Debug and fix the test logic

### Coverage Below 50%
```
Coverage: 45.5% (below 50% threshold)
```
**Fix**: Add tests for uncovered code:
```bash
cargo tarpaulin --workspace --out Html
# Review report to find untested code
```

## Deployment Flow

### On Pull Request
- ✅ Runs all tests (stages 1-7)
- ⏸️ Stops (doesn't build Docker images)
- ✅ GitHub shows status checks

### On Push to Main
- ✅ Runs all tests (stages 1-7)
- ✅ Builds Docker images (stage 8)
- ✅ Pushes to ECR
- ✅ Deploys to EKS staging
- ✅ Smoke tests
- ✅ Quality report

### On Push to Feature Branch
- ✅ Same as main
- 📍 Deployed to staging only

## Viewing Results

### GitHub Actions
1. Go to: https://github.com/your-repo/actions
2. Select workflow run
3. Expand stage names to see logs

### Code Coverage
1. Go to: https://codecov.io/gh/your-repo
2. View trend over time
3. See uncovered lines

### Deployment Status
1. Check EKS pods: `kubectl get pods -A`
2. Check logs: `kubectl logs <pod-name> -n nova`
3. Check services: `kubectl get svc -A`

## Performance Tips

### Faster Local Testing

```bash
# Build with minimal features (faster)
cargo build --lib

# Test fewer features
cargo test --lib --no-default-features

# Run specific test only
cargo test --lib test_name -- --exact
```

### Parallel Testing

Pipeline already does this:
- 12 services tested simultaneously (6 max parallel)
- Saves ~5-7 minutes compared to sequential

## Adjusting Settings

### Change Coverage Threshold

Edit `.github/workflows/ci-cd-pipeline.yml` line 166:
```yaml
--fail-under 50     # Change to 60, 70, etc.
```

### Add New Service to Pipeline

Edit `.github/workflows/ci-cd-pipeline.yml` lines 67-79:
```yaml
strategy:
  matrix:
    service:
      - new-service    # Add here
```

Pipeline automatically tests it.

### Exclude Files from Coverage

Edit `.github/workflows/ci-cd-pipeline.yml` line 165:
```yaml
--exclude-files 'target/*' 'tests/*' 'migrations/*'
```

## Debugging Failed Pipeline

### Step 1: Check Pipeline Logs
1. Go to Actions → Failed run
2. Expand the failed stage
3. Read error message

### Step 2: Reproduce Locally
```bash
# Format & Lint
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings

# Tests
cargo test --lib

# Coverage (if applicable)
cargo tarpaulin --workspace --fail-under 50
```

### Step 3: Fix & Commit
```bash
# Fix the issue
# Then:
git add .
git commit -m "fix: correct formatting/tests/coverage"
git push
```

### Step 4: Monitor Re-run
- Pipeline re-runs automatically
- Check status in GitHub Actions

## Caching Strategy

Pipeline uses intelligent caching:
- **Cargo registry**: Downloaded crates cached
- **Cargo index**: Index cached
- **Build artifacts**: `backend/target/` cached
- **Cache key**: Based on `Cargo.lock`

**Result**: 60-70% faster builds after first run

## Integration Tests

### What Gets Tested
- Service with PostgreSQL 15
- Service with Redis 7
- Database migrations
- gRPC endpoints

### Databases Available in Tests
```rust
// In test code:
let db_url = "postgresql://test:test@localhost:5432/nova_test";
let redis_url = "redis://localhost:6379";
```

### Running Integration Tests Locally

```bash
# Start PostgreSQL
docker run --rm -d \
  -e POSTGRES_DB=nova_test \
  -e POSTGRES_USER=test \
  -e POSTGRES_PASSWORD=test \
  -p 5432:5432 \
  postgres:15-alpine

# Start Redis
docker run --rm -d \
  -p 6379:6379 \
  redis:7-alpine

# Run tests
cargo test --lib --test '*' --all-features

# Cleanup
docker stop <postgres-container-id> <redis-container-id>
```

## Quality Report

### Automatic Report Generated
Run at: https://github.com/your-repo/actions
- Shows all 12 services tested
- Lists quality gates
- Reports pass/fail

### Metrics Tracked
- ✅ Format & Lint results
- ✅ Unit test results (per service)
- ✅ Code coverage percentage
- ✅ Security audit findings
- ✅ Deployment status

## Emergency: Disable a Stage (Temporary)

**Not recommended**, but if needed:

Edit `.github/workflows/ci-cd-pipeline.yml` and change:
```yaml
if: true    # Enable
if: false   # Disable
```

Or add to job:
```yaml
if: false   # Completely skip this job
```

## Questions?

Check the full documentation: `CI_CD_ENHANCEMENT_SUMMARY.md`

Or run locally to test before pushing:
```bash
cargo fmt --all && \
cargo clippy --workspace --all-targets --all-features -- -D warnings && \
cargo test --lib
```
