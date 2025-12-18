# Nova Workflow Automation Guide

This document provides a comprehensive overview of the CI/CD automation workflows implemented for the Nova Social Platform.

## Table of Contents

1. [Overview](#overview)
2. [Workflow Architecture](#workflow-architecture)
3. [Core Workflows](#core-workflows)
4. [Development Workflows](#development-workflows)
5. [Deployment Workflows](#deployment-workflows)
6. [Monitoring & Alerts](#monitoring--alerts)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Overview

The Nova CI/CD system provides:
- **Incremental builds**: Only build changed services
- **Layered deployments**: Deploy services in dependency order
- **Automated releases**: Semantic versioning with changelog generation
- **PR automation**: Auto-labeling, reviewer assignment, validation
- **Cost monitoring**: Track and alert on workflow usage

### Key Principles

1. **Efficiency**: Only build what changed
2. **Safety**: Layered deployments with automatic rollback
3. **Visibility**: Rich notifications and status reports
4. **Automation**: Minimize manual intervention

---

## Workflow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Unified CI/CD Orchestrator                   │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │  Change  │→│  Quality │→│  Tests   │→│ Security │        │
│  │ Detection│  │  Checks  │  │          │  │  Scan    │        │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
│        ↓                                       ↓                │
│  ┌──────────┐                           ┌──────────┐           │
│  │  Build   │←─────────────────────────→│  Deploy  │           │
│  │ & Push   │                           │          │           │
│  └──────────┘                           └──────────┘           │
│        ↓                                       ↓                │
│  ┌──────────┐                           ┌──────────┐           │
│  │  Release │                           │  Smoke   │           │
│  │          │                           │  Tests   │           │
│  └──────────┘                           └──────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Core Workflows

### 1. Unified CI/CD Orchestrator (`unified-ci-cd.yml`)

**Purpose**: Master workflow that routes to appropriate sub-workflows based on changes.

**Triggers**:
- Push to `main` or `develop`
- Pull requests to `main`
- Manual dispatch

**Features**:
- Path-based change detection
- Parallel quality and test jobs
- Conditional builds based on changes
- PR status comments

**Usage**:
```yaml
# Automatically triggered on push/PR
# Or manually:
gh workflow run "Unified CI/CD Orchestrator"
```

### 2. Incremental Build (`gcp-build-incremental.yml`)

**Purpose**: Build only changed services and push to Artifact Registry.

**Features**:
- Detects changed services from git diff
- Shared library change triggers full rebuild
- Parallel builds (up to 6)
- GHA cache integration

**Manual trigger**:
```bash
# Force specific services
gh workflow run "GCP Build (Incremental)" -f services="identity-service,graph-service"

# Force all services
gh workflow run "GCP Build (Incremental)" -f force_all=true
```

### 3. Incremental Deploy (`staging-deploy-incremental.yml`)

**Purpose**: Deploy services in dependency-aware layers with automatic rollback.

**Deployment Layers**:
| Layer | Services | Description |
|-------|----------|-------------|
| 0 | identity-service, graph-service | Foundation services |
| 1 | content-service, social-service, media-service | Core services |
| 2 | feed-service, ranking-service, search-service, notification-service | Business services |
| 3 | analytics-service, trust-safety-service, realtime-chat-service | Edge services |
| 4 | graphql-gateway | API gateway |

**Rollback**: Automatic rollback if any layer fails.

---

## Development Workflows

### 1. Pre-commit Hooks

**Installation**:
```bash
# Run the setup script
./scripts/setup-dev-environment.sh

# Or manually:
pip install pre-commit
pre-commit install
pre-commit install --hook-type commit-msg
```

**Configured Hooks**:
- Rust: `cargo fmt`, `cargo clippy`, `cargo check`
- Swift: `swiftlint`, `swift-format`
- General: trailing whitespace, YAML lint, secrets detection
- Commits: conventional commit validation

### 2. PR Automation (`pr-automation.yml`)

**Features**:
- **Auto-labeling**: Labels by file path and PR size
- **Reviewer assignment**: Based on CODEOWNERS
- **Title validation**: Conventional commits enforcement
- **Welcome message**: For first-time contributors

**PR Commands** (via comments):
| Command | Description | Access Required |
|---------|-------------|-----------------|
| `/lgtm` | Approve the PR | Write |
| `/hold` | Block merge | Write |
| `/unhold` | Remove block | Write |
| `/retest` | Retrigger CI | Write |
| `/help` | Show available commands | All |

### 3. Code Quality (`code-quality.yml`)

**Checks**:
- `unwrap()` detection in production code
- `println!` detection
- `panic!` detection
- Hardcoded secrets detection
- TODO/FIXME tracking
- Clippy lints (strict)
- Format check

---

## Deployment Workflows

### 1. Release Automation (`release-automation.yml`)

**Purpose**: Automated semantic versioning and release creation.

**Features**:
- Conventional commit analysis for version bumps
- Automatic changelog generation
- GitHub release creation
- Docker image tagging with version
- Optional production promotion

**Version Bump Rules**:
| Commit Prefix | Version Bump | Example |
|--------------|--------------|---------|
| `feat!:` or `BREAKING CHANGE:` | Major | 1.0.0 → 2.0.0 |
| `feat:` | Minor | 1.0.0 → 1.1.0 |
| `fix:`, `perf:`, `refactor:` | Patch | 1.0.0 → 1.0.1 |

**Manual trigger**:
```bash
# Dry run (see what would happen)
gh workflow run "Release Automation" -f dry_run=true

# Force specific version bump
gh workflow run "Release Automation" -f release_type=minor

# Release with production promotion
gh workflow run "Release Automation" -f promote_to_production=true
```

### 2. iOS Deployment (`ios-testflight-deploy.yml`)

**Purpose**: Build and deploy iOS app to TestFlight.

**Requirements**:
- Apple Developer certificates in secrets
- App Store Connect API key

---

## Monitoring & Alerts

### 1. Workflow Cost Monitoring (`workflow-cost-monitoring.yml`)

**Purpose**: Track GitHub Actions usage and costs.

**Schedule**: Weekly (Monday 00:00 UTC)

**Metrics Tracked**:
- Total runner minutes
- Estimated cost
- Per-workflow breakdown
- Daily usage trends

**Alert Threshold**: 10,000 minutes/week

**Reports**:
- Markdown report uploaded as artifact
- GitHub issue created on alert
- Feishu notification on alert

### 2. Security Scanning (`security-scanning.yml`)

**Pipeline Stages**:
1. Secrets Detection (gitleaks)
2. Dependency Scanning (cargo-deny, cargo-audit)
3. SAST Analysis (clippy security lints)
4. Container Scanning (Trivy)
5. SBOM Generation (syft)
6. Image Signing (cosign/sigstore)
7. K8s Config Scanning (kube-score, checkov)
8. Infrastructure Scanning

**Schedule**: Daily at 2 AM UTC

---

## Best Practices

### 1. Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code restructure
- `perf`: Performance improvement
- `test`: Tests
- `build`: Build system
- `ci`: CI/CD changes
- `chore`: Maintenance

**Examples**:
```bash
feat(identity): add OAuth2 authentication
fix(feed): resolve pagination issue
perf(media): optimize image processing pipeline
```

### 2. Branch Strategy

```
main (production-ready)
  └── develop (integration)
       ├── feature/xxx
       ├── fix/xxx
       └── hotfix/xxx
```

### 3. PR Guidelines

1. **Title**: Use conventional commit format
2. **Description**: Include "## Summary" and "## Test Plan"
3. **Size**: Keep PRs small (<500 lines when possible)
4. **Tests**: Include tests for new features
5. **Labels**: Will be auto-applied

### 4. Performance Optimization

**Caching**:
- Rust dependencies cached via GHA cache
- Docker layers cached per-service
- Build artifacts reused across jobs

**Parallelization**:
- Up to 6 parallel service builds
- Parallel test execution
- Matrix builds for cross-platform testing

---

## Troubleshooting

### Common Issues

#### 1. Build Fails with Cache Miss

```bash
# Clear GHA cache for a service
gh cache delete -R proerror/nova --key "gha-<service-name>"

# Force rebuild without cache
gh workflow run "GCP Build (Incremental)" -f force_all=true
```

#### 2. Deployment Rollback Triggered

Check the failed layer's logs:
```bash
# Get recent runs
gh run list -w "Staging Deploy (Incremental)"

# View specific run logs
gh run view <run-id> --log
```

#### 3. Pre-commit Hook Failures

```bash
# Skip hooks for emergency (not recommended)
git commit --no-verify -m "emergency: hotfix"

# Run hooks manually to debug
pre-commit run --all-files

# Update hooks
pre-commit autoupdate
```

#### 4. Cost Alert Triggered

1. Check the cost report artifact
2. Identify top-consuming workflows
3. Review for:
   - Unnecessary triggers
   - Inefficient caching
   - Long-running jobs
   - Failed retries

### Useful Commands

```bash
# List all workflow runs
gh run list

# Watch a running workflow
gh run watch

# Download artifacts
gh run download <run-id>

# View workflow status
gh workflow view "Unified CI/CD Orchestrator"

# Cancel a running workflow
gh run cancel <run-id>

# Retry a failed workflow
gh run rerun <run-id> --failed
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `.github/workflows/*.yml` | Workflow definitions |
| `.github/labeler.yml` | Auto-labeling rules |
| `.github/dependabot.yml` | Dependency updates |
| `.github/CODEOWNERS` | Code ownership |
| `.pre-commit-config.yaml` | Pre-commit hooks |
| `.yamllint.yml` | YAML lint config |
| `.markdownlint.json` | Markdown lint config |

---

## Support

For issues with CI/CD:
1. Check workflow logs
2. Review this documentation
3. Create an issue with label `ci`
4. Contact the DevOps team

---

*Last updated: 2025-12-17*
