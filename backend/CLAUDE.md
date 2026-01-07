# Claude Code Guidelines for Nova Backend

## Build & Deployment Rules

### DO NOT use local Docker builds
- **Never** use `docker build` locally for building service images
- **Always** use GitHub Actions for building and deploying services
- Push code changes to trigger CI/CD pipelines instead

### Deployment Workflow
1. Commit and push changes to the appropriate branch
2. GitHub Actions will automatically build Docker images
3. For staging deployment, push to `main` or create a PR
4. For production deployment, use the release workflow

### Why?
- Local builds are slow and resource-intensive
- CI/CD ensures consistent build environments
- Reduces risk of "works on my machine" issues
- Centralizes build artifacts in the container registry

## Database Architecture

The Nova backend uses separate databases for each service:
- `nova_auth` - User authentication, sessions, invite codes
- `nova_social` - Likes, comments, shares, bookmarks
- `nova_content` - Posts, media references
- `nova_notification` - Push notifications, in-app notifications

**Important**: Cross-database queries are not possible. Use gRPC calls between services to fetch data from other databases.

## Kubernetes Namespaces

- `nova-staging` - Staging environment
- `nova-prod` - Production environment

## Common Commands

```bash
# Check pod status
kubectl get pods -n nova-staging

# View logs
kubectl logs -l app=<service-name> -n nova-staging --tail=100

# Port forward for debugging
kubectl port-forward svc/<service-name> 8080:8080 -n nova-staging
```
