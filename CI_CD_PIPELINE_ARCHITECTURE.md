# CI/CD Pipeline Architecture

## Visual Pipeline Flow

```
GitHub Push/PR Event
        │
        ├─────────────────────────────────────────────────────────┐
        │                                                         │
        ▼                                                         │
   ┌─────────────────────────────────────────────────────────┐  │
   │ Stage 1: Format & Lint (All Services)                  │  │
   │ ├─ cargo fmt --check                                   │  │
   │ └─ cargo clippy --workspace -D warnings                │  │
   │ Runs: 1 job, Sequential                                │  │
   │ Time: ~2-3 min                                         │  │
   │ Blocking: YES (Required to pass)                       │  │
   └─────────────────────────────────────────────────────────┘  │
        │                                                         │
        │ (Pass: continue, Fail: stop)                          │
        │                                                         │
        ▼                                                         │
   ┌─────────────────────────────────────────────────────────┐  │
   │ Stage 2: Unit Tests - All 12 Services                  │  │
   │ ┌────────────────────────────────────────────────────┐ │  │
   │ │ Parallel Matrix (6 max concurrent)                 │ │  │
   │ │ ├─ auth-service         ⬚ cargo test --lib        │ │  │
   │ │ ├─ user-service         ⬚ cargo test --lib        │ │  │
   │ │ ├─ messaging-service    ⬚ cargo test --lib        │ │  │
   │ │ ├─ content-service      ⬚ cargo test --lib        │ │  │
   │ │ ├─ feed-service         ⬚ cargo test --lib        │ │  │
   │ │ ├─ search-service       ⬚ cargo test --lib        │ │  │
   │ │ ├─ media-service        ⬚ cargo test --lib        │ │  │
   │ │ ├─ notification-service ⬚ cargo test --lib        │ │  │
   │ │ ├─ streaming-service    ⬚ cargo test --lib        │ │  │
   │ │ ├─ video-service        ⬚ cargo test --lib        │ │  │
   │ │ ├─ cdn-service          ⬚ cargo test --lib        │ │  │
   │ │ └─ events-service       ⬚ cargo test --lib        │ │  │
   │ └────────────────────────────────────────────────────┘ │  │
   │ Runs: 12 jobs, 6 parallel                              │  │
   │ Time: ~8-12 min                                        │  │
   │ Blocking: YES (All must pass)                          │  │
   └─────────────────────────────────────────────────────────┘  │
        │                                                         │
        ├─────────────┬──────────────────┬────────────────────┤  │
        │             │                  │                    │  │
        ▼             ▼                  ▼                    ▼  │
   ┌──────────┐  ┌──────────┐  ┌──────────────┐  ┌────────────┐│
   │ Stage 3  │  │ Stage 4  │  │ Stage 5      │  │ Stage 6    ││
   │ Coverage │  │ Security │  │ Dependencies │  │ Integration││
   │ Report   │  │ Audit    │  │ Check        │  │ Tests      ││
   │          │  │          │  │              │  │            ││
   │ tarpaulin│  │ audit +  │  │ outdated     │  │ PostgreSQL ││
   │ codecov  │  │ deny     │  │ tree         │  │ Redis      ││
   │          │  │          │  │              │  │            ││
   │ 5-8 min  │  │ 3-5 min  │  │ 1-2 min      │  │ 4-6 min    ││
   │ BLOCKING │  │ WARNING  │  │ INFO         │  │ BLOCKING   ││
   │ (>50%)   │  │ only     │  │ only         │  │            ││
   └──────────┘  └──────────┘  └──────────────┘  └────────────┘│
        │             │              │                    │     │
        │             │              │ (no block)        │     │
        │             │ (no block)    │                  │     │
        │             │               │                  │     │
        └─────────────┴───────────────┴──────────────────┘     │
                      │                                        │
                      │ (All blocking stages complete)        │
                      │                                        │
                      ▼                                        │
              ┌──────────────────┐                            │
              │ Stage 7: Build   │                            │
              │ Release Binaries │                            │
              │                  │                            │
              │ cargo build      │                            │
              │ --workspace      │                            │
              │ --release        │                            │
              │                  │                            │
              │ 6-10 min         │                            │
              │ BLOCKING         │                            │
              └──────────────────┘                            │
                      │                                        │
                      │ (Only on PUSH events)                 │
                      ├──────────────────────────────────────┐│
                      │ (on PULL_REQUEST: stops here)        ││
                      │                                      ││
                      ▼                                      ││
              ┌──────────────────────────────┐             ││
              │ Stage 8: Build Docker Images │             ││
              │                              │             ││
              │ ┌──────────────────────────┐│             ││
              │ │ 11 services in parallel  ││             ││
              │ │ (6 max)                  ││             ││
              │ │ • Build multi-stage      ││             ││
              │ │ • Push to ECR            ││             ││
              │ │ • Tag with SHA           ││             ││
              │ │ • Tag with branch        ││             ││
              │ │ • Verify image pushed    ││             ││
              │ └──────────────────────────┘│             ││
              │                              │             ││
              │ 8-15 min                    │             ││
              │ BLOCKING                    │             ││
              └──────────────────────────────┘             ││
                      │                                      ││
                      ▼                                      ││
              ┌──────────────────────────────┐             ││
              │ Stage 9: Deploy to EKS       │             ││
              │ (Staging)                    │             ││
              │                              │             ││
              │ • Update kubeconfig          │             ││
              │ • Rollout restart            │             ││
              │ • Health check               │             ││
              │ • Status verification        │             ││
              │                              │             ││
              │ 3-5 min                      │             ││
              │ INFO only                    │             ││
              └──────────────────────────────┘             ││
                      │                                      ││
                      ▼                                      ││
              ┌──────────────────────────────┐             ││
              │ Stage 10: Smoke Tests        │             ││
              │                              │             ││
              │ • Pod status check           │             ││
              │ • Service endpoints check    │             ││
              │ • ConfigMaps check           │             ││
              │                              │             ││
              │ ~2 min                       │             ││
              │ INFO only                    │             ││
              └──────────────────────────────┘             ││
                      │                                      ││
                      ├──────────────────────┐              ││
                      │ (on PULL_REQUEST: done)            ││
                      │                                      ││
                      ▼                                      ││
              ┌──────────────────────────────┐             ││
              │ Stage 11: Quality Report     │             ││
              │                              │             ││
              │ • Summary of all tests       │             ││
              │ • Services tested list       │             ││
              │ • Quality gates status       │             ││
              │ • Coverage report            │             ││
              │                              │             ││
              │ ~1 min                       │             ││
              │ REPORTING only               │             ││
              └──────────────────────────────┘             ││
                      │                                      ││
                      ▼                                      ││
              ┌──────────────────────────────┐             ││
              │ Stage 12: Notifications      │             ││
              │                              │             ││
              │ • Deployment status          │             ││
              │ • Job results summary         │             ││
              │ • Troubleshooting steps      │             ││
              │                              │             ││
              │ ~1 min                       │             ││
              │ REPORTING only               │             ││
              └──────────────────────────────┘             ││
                      │                                      ││
                      └──────────────────────────────────────┘│
                                                              │
                      ✅ SUCCESS or ❌ FAILURE               │
                                                              │
        (Pull Request: blocks merge if any BLOCKING stage fails)
        (Push: deploys if all BLOCKING stages pass)
```

## Dependency Graph

```
format-and-lint
    │
    ├──────────────────────────────────────────────────┐
    │                                                  │
    ▼                                                  ▼
test-services                               [security-audit]
    │ (12 services)                          [dependency-check]
    │
    ├────────────┬─────────────────┐
    │            │                 │
    ▼            ▼                 ▼
code-coverage  integration-tests  build-release
                                    │
                                    ├─────────────────┐
                                    │                 │
                                    ▼                 ▼
                            [build-and-push]  (if PUSH event)
                                    │
                                    ▼
                            deploy-staging
                                    │
                                    ▼
                            smoke-test
                                    │
                    ┌───────────────┴────────────────┐
                    │                                │
                    ▼                                ▼
            quality-report                    (deploy complete)
                    │
                    ├────────────────┐
                    │                │
                    ▼                ▼
                 notify        (pipeline end)
                    │
                    ▼
        ✅ Overall Result
```

## Job Dependencies

```
PULL REQUEST Event:
├─ format-and-lint ────────────┐
├─ test-services (needs: format-and-lint) ──┐
├─ code-coverage (needs: test-services) ────┤
├─ security-audit (needs: format-and-lint)  │
├─ dependency-check (needs: format-and-lint)│
├─ integration-tests (needs: test-services) │
├─ build-release (needs: [f-l, t-s, s-a])  │
│                                          │
│ Stops here (no push) ◄────────────────────┘
│
└─ quality-report (needs: [t-s, c-c, s-a])

PUSH Event (with all PR jobs):
├─ ... (all PR jobs) ...
├─ build-and-push (needs: [b-r, c-c, s-a, i-t])
├─ deploy-staging (needs: build-and-push)
├─ smoke-test (needs: deploy-staging)
├─ quality-report (needs: [t-s, c-c, s-a])
└─ notify (needs: [b-a-p, d-s, s-t, q-r])
```

## Timing Analysis

### Pull Request (No Deployment)
```
Sequential Blocking Stages:
  format-and-lint:     2-3 min   [████]
  test-services:       8-12 min  [█████████]
  integration-tests:   4-6 min   [█████]  (parallel with code-coverage)
  code-coverage:       5-8 min   [█████]  (parallel with integration-tests)
  security-audit:      3-5 min   [████]   (parallel with test-services)
  build-release:       6-10 min  [██████]

TOTAL TIME: ~15 min (parallel stages overlap)

Parallel Stages:
- test-services (12 services, 6 max parallel) = ~8-12 min
- While that runs:
  - integration-tests (4-6 min) ✓ fits within
  - code-coverage (5-8 min) ✓ fits within
  - security-audit (3-5 min) ✓ fits within

Critical Path:
format-and-lint → test-services → build-release → DONE
       3 min    +    12 min    +     10 min    = 25 min max
(but parallel staging reduces this to ~15 min)
```

### Push Event (With Deployment)
```
All PR jobs (15 min) plus:
  build-and-push:      8-15 min  [██████████]
  deploy-staging:      3-5 min   [████]
  smoke-test:          2 min     [██]
  quality-report:      1 min     [█]
  notify:              1 min     [█]

TOTAL TIME: ~40 min from push to deployed

Critical Path:
(15 min of tests) → build-and-push → deploy-staging → smoke-test → notify
                  8-15 min         +    3-5 min    +    2 min   +  1 min
                                  = 24-23 additional minutes
```

## Resource Allocation

### Per-Job Resource Estimates
```
format-and-lint:     Small  (code analysis only)
test-services:       Medium (1 per service, 6 parallel) × 12
code-coverage:       Medium (instrumentation overhead)
security-audit:      Small  (dependency scanning)
dependency-check:    Small  (metadata analysis)
integration-tests:   Large  (PostgreSQL + Redis containers)
build-release:       Medium (compilation)
build-and-push:      Large  (Docker multi-stage builds)
deploy-staging:      Small  (kubectl commands)
smoke-test:          Small  (health checks)
quality-report:      Small  (reporting)
notify:              Small  (reporting)
```

### GitHub Actions Runners
```
Matrix Parallelism (test-services):
├─ 6 concurrent runners active
├─ Each gets 1 service
├─ All share common cargo cache
└─ Subsequent jobs: 1 runner

Caching Benefits:
├─ First run: ~20 min (no cache)
├─ Subsequent: ~15 min (60-70% faster with cache)
└─ Shared cargo cache across all services
```

## Error Handling & Retry Strategy

### On Failure
```
format-and-lint FAILS
    └─ Stop pipeline
       └─ Mark as blocking
       └─ Display error
       └─ Require fix + re-push

test-services FAILS
    └─ Downstream jobs DON'T run
       └─ code-coverage skipped
       └─ integration-tests skipped
       └─ build-release skipped
       └─ build-and-push NOT triggered

code-coverage FAILS (< 50%)
    └─ Downstream jobs continue
       └─ build-release runs
       └─ build-and-push BLOCKED (needs: code-coverage)
       └─ No deployment

security-audit FAILS
    └─ Pipeline continues (warning only)
       └─ build-and-push still runs
       └─ Deployment proceeds (review needed)

build-and-push FAILS
    └─ deploy-staging NOT triggered
       └─ No deployment
       └─ Development image not pushed to ECR
```

### Retry Behavior
```
Individual job fails → Re-run single job
                    → OR push new commit
                    → OR manual re-run from GitHub UI

Pipeline fails → Fix issue locally
             → Push new commit
             → Entire pipeline re-runs
             → Cache speeds up process
```

## Service Testing Matrix

```
                Auth User Mess Cont Feed Sear Medi Noti Stre Vide CDN  Even
                ──── ──── ──── ──── ──── ──── ──── ──── ──── ──── ──── ────
Unit Tests      ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓
Doc Tests       ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓
Clippy Lint     ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓
Format Check    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓

Integration     (PostgreSQL + Redis in single job)
with DB         ✓ (all services have access)
with Redis      ✓ (all services have access)

Code Coverage   (Workspace-wide)
per service     ✓ (50% minimum across workspace)

Security Audit  (Workspace-wide)
all at once      ✓ (single audit for all dependencies)

Docker Build    ──── ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓    ✓
(11 services)   (all except video-service in current matrix)
```

## GitHub Actions Features Used

```
Matrix Strategy:
├─ test-services: 12 services
├─ build-and-push: 11 services
└─ max-parallel: 6 (tests), 4 (docker)

Service Containers:
├─ PostgreSQL 15-alpine
└─ Redis 7-alpine

Caching:
├─ actions/cache@v3 (registry, index, build)
└─ Keyed by Cargo.lock hash

Artifacts:
├─ Coverage reports → Codecov
└─ Build outputs → Docker images → ECR

Secrets (via environment):
├─ AWS_ACCESS_KEY_ID
├─ AWS_SECRET_ACCESS_KEY
└─ (All injected by GitHub)

Conditionals:
├─ if: github.event_name == 'push'  (Docker build)
├─ if: github.ref == 'refs/heads/main' (Deploy)
└─ if: always()  (Run even if previous failed)
```

## Scaling Considerations

### Adding More Services
1. Add to matrix (line 67-79)
2. Pipeline auto-scales
3. Default: 6 max parallel
4. Adjust `max-parallel` if needed

### Increasing Coverage Threshold
Edit line 166:
```yaml
--fail-under 50    # Change to 70
```

### Adding More Integration Tests
Extend `integration-tests` step
(PostgreSQL + Redis already available)

### Adding Service Container
Edit `integration-tests` services section:
```yaml
mongo:
  image: mongo:6
  ports:
    - 27017:27017
```

## Security Considerations

```
Secrets Management:
├─ AWS credentials: GitHub Secrets (encrypted)
├─ ECR login: aws-actions/amazon-ecr-login
├─ No secrets in logs
└─ Audit trails in GitHub Actions

Access Control:
├─ Deploy requires push to main/feature branch
├─ Pull requests blocked until all checks pass
└─ Status checks enforced

Image Security:
├─ Images built with multi-stage Dockerfile
├─ Pushed to private ECR registry
├─ Tagged with commit SHA (immutable reference)
└─ License/advisory scanning before push
```

## Monitoring & Observability

```
Pipeline Metrics Available:
├─ Execution time per stage
├─ Success/failure rates
├─ Test count and coverage
├─ Docker image sizes
├─ Build cache hit ratio
└─ Job duration trends

View in GitHub:
├─ Actions tab → Workflow runs
├─ Branch protection → Status checks
└─ Insights → Workflow runs

External Tools:
├─ Codecov.io → Coverage trends
├─ AWS CloudWatch → Deployment logs
└─ kubectl → Container logs
```
