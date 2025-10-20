# CI/CD Setup Guide

Complete GitHub Actions CI/CD pipeline has been configured for your Nova project.

## Workflows Created

### 1. CI Pipeline (ci.yml)
Runs on every push and PR:
- Unit tests with PostgreSQL + Redis
- Code coverage reports (Codecov)
- Linting (cargo clippy)
- Format checks (cargo fmt)
- Security audit (cargo audit)
- Release build

### 2. Docker Build (docker-build.yml)
Builds and pushes to GitHub Container Registry:
- Triggered on push to main/master/develop
- Tags: branch name, commit SHA, version
- Automatic caching for faster builds

### 3. Deploy (deploy.yml)
Auto-deploys to production:
- Triggered on main/master push or version tags
- Requires GitHub Secrets configuration

### 4. Release (release.yml)
Creates GitHub releases:
- Triggered on version tags (v*)
- Auto-generates release notes
- Uploads binary artifacts

### 5. Coverage Report (coverage.yml)
Code coverage tracking:
- Posts coverage % on PRs
- Uploads to Codecov

## Setup Instructions

### Step 1: Configure GitHub Secrets

Go to: Repository Settings → Secrets and variables → Actions

Add these secrets for deployment:

```
DEPLOY_KEY   = Your SSH private key
DEPLOY_HOST  = Deployment server (e.g., example.com)
DEPLOY_USER  = SSH username
CARGO_TOKEN  = (Optional) Cargo registry token
```

### Step 2: Customize Deployment Logic

Edit `.github/workflows/deploy.yml` to match your infrastructure:

Example for Kubernetes:
```yaml
- name: Deploy
  run: |
    kubectl set image deployment/nova-user-service \
      nova-user-service=${{ steps.version.outputs.image }}
```

### Step 3: Push to GitHub

```bash
git add .github/
git commit -m "chore: add CI/CD workflows"
git push
```

## How It Works

1. **On Push**: CI workflow runs (tests, lint, build)
2. **If Tests Pass**: Docker image built and pushed
3. **On main/master**: Auto-deploy to production (if configured)
4. **On Tag v***: Release workflow creates GitHub Release

## View Workflow Status

- GitHub Repository → Actions tab
- See all runs, logs, and artifacts
- Failed checks will show in PR

## Key Features

✅ Parallel job execution for speed
✅ Automatic caching for Cargo dependencies
✅ Code coverage tracking
✅ Docker image versioning
✅ Security audits
✅ Automatic deployments (configurable)

## Common Tasks

**Skip CI for a commit:**
```bash
git commit -m "docs: update [skip ci]"
```

**View workflow logs:**
- GitHub → Actions → Select workflow → Click run

**Run workflow manually:**
- Actions → Workflow → "Run workflow" button

## Docker Image Access

Images are stored at:
```
ghcr.io/YOUR_USERNAME/nova/nova-user-service:TAG
```

Pull example:
```bash
docker pull ghcr.io/YOUR_USERNAME/nova/nova-user-service:latest
```

## Troubleshooting

**Tests failing?**
- Check logs in Actions tab
- Ensure .env has correct test DB config

**Docker push failing?**
- Verify GitHub Token has package write permissions

**Deployment failing?**
- Check SSH key configuration
- Verify DEPLOY_HOST and DEPLOY_USER

## Resources

- GitHub Actions: https://docs.github.com/en/actions
- Rust: https://doc.rust-lang.org/
- Docker: https://docs.docker.com/
