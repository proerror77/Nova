# Synapse OIDC Quick Reference

Quick reference for common Synapse OIDC operations in staging.

## Deployment Commands

```bash
# Deploy everything
cd /Users/proerror/Documents/Nova/backend/k8s/overlays/staging
kubectl apply -k .

# Deploy only Synapse config
kubectl apply -f synapse-oidc-patch.yaml

# Deploy well-known
kubectl apply -f matrix-well-known.yaml

# Restart Synapse
kubectl rollout restart deployment/matrix-synapse -n nova-backend
```

## Secret Management

```bash
# Create secrets from template
cp synapse-secrets.yaml.template synapse-secrets.yaml
# Edit synapse-secrets.yaml
kubectl apply -f synapse-secrets.yaml

# View secrets (base64 encoded)
kubectl get secret synapse-oidc-secrets -n nova-backend -o yaml

# Get OIDC client secret
kubectl get secret synapse-oidc-secrets -n nova-backend \
  -o jsonpath='{.data.oidc_client_secret}' | base64 -d

# Get admin token
kubectl get secret synapse-admin-api -n nova-backend \
  -o jsonpath='{.data.SYNAPSE_ADMIN_TOKEN}' | base64 -d

# Update admin token
kubectl create secret generic synapse-admin-api \
  --from-literal=SYNAPSE_ADMIN_TOKEN='NEW_TOKEN' \
  --from-literal=SYNAPSE_HOMESERVER_URL='http://matrix-synapse:8008' \
  --from-literal=SYNAPSE_SERVER_NAME='staging.nova.app' \
  --namespace=nova-backend \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Admin User Operations

```bash
# Create admin user
cd /Users/proerror/Documents/Nova/backend/k8s/scripts
python3 create-synapse-admin.py --login

# Create with custom username
python3 create-synapse-admin.py --username custom-admin --login

# Get registration secret
kubectl get secret synapse-oidc-secrets -n nova-backend \
  -o jsonpath='{.data.registration_shared_secret}' | base64 -d
```

## Admin API Calls

```bash
# Set admin token variable
ADMIN_TOKEN=$(kubectl get secret synapse-admin-api -n nova-backend \
  -o jsonpath='{.data.SYNAPSE_ADMIN_TOKEN}' | base64 -d)

# Get server version
curl -X GET "https://matrix.staging.nova.app/_synapse/admin/v1/server_version" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# List users
curl -X GET "https://matrix.staging.nova.app/_synapse/admin/v2/users?limit=10" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Get user info
USER_ID="@nova-UUID:staging.nova.app"
curl -X GET "https://matrix.staging.nova.app/_synapse/admin/v2/users/${USER_ID}" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Deactivate user
curl -X POST "https://matrix.staging.nova.app/_synapse/admin/v1/deactivate/${USER_ID}" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"erase": true}'

# List user devices
curl -X GET "https://matrix.staging.nova.app/_synapse/admin/v2/users/${USER_ID}/devices" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Delete specific device
DEVICE_ID="DEVICEID"
curl -X DELETE "https://matrix.staging.nova.app/_synapse/admin/v2/users/${USER_ID}/devices/${DEVICE_ID}" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

## Testing & Verification

```bash
# Check Synapse pod status
kubectl get pods -n nova-backend -l app=matrix-synapse

# View Synapse logs
kubectl logs -n nova-backend -l app=matrix-synapse --tail=100 -f

# Filter for OIDC logs
kubectl logs -n nova-backend -l app=matrix-synapse | grep -i oidc

# Filter for backchannel logout
kubectl logs -n nova-backend -l app=matrix-synapse | grep backchannel

# Test well-known discovery
curl https://staging.nova.app/.well-known/matrix/client
curl https://staging.nova.app/.well-known/matrix/server

# Test Matrix client API
curl https://matrix.staging.nova.app/_matrix/client/versions

# Test health endpoint
curl https://matrix.staging.nova.app/health

# Port forward for local testing
kubectl port-forward -n nova-backend service/matrix-synapse 8008:8008
# Then access: http://localhost:8008
```

## Configuration Checks

```bash
# View Synapse config
kubectl get configmap matrix-synapse-config -n nova-backend -o yaml

# Check OIDC configuration
kubectl get configmap matrix-synapse-config -n nova-backend -o yaml | grep -A 30 oidc_providers

# Check backchannel logout config
kubectl get configmap matrix-synapse-config -n nova-backend -o yaml | grep backchannel

# Check session config
kubectl get configmap matrix-synapse-config -n nova-backend -o yaml | grep -E "(session_lifetime|refresh_token)"

# View ingress configuration
kubectl get ingress -n nova-backend matrix-synapse-ingress -o yaml
kubectl get ingress -n nova-backend matrix-well-known-ingress -o yaml
```

## Debugging

```bash
# Exec into Synapse pod
kubectl exec -it -n nova-backend deployment/matrix-synapse -- /bin/bash

# Check config file
kubectl exec -it -n nova-backend deployment/matrix-synapse -- cat /data/homeserver.yaml

# Check OIDC secret is mounted
kubectl exec -it -n nova-backend deployment/matrix-synapse -- cat /secrets/oidc_client_secret

# Check database connection
kubectl exec -it -n nova-backend deployment/matrix-synapse -- \
  python -c "import psycopg2; print('DB connection OK')"

# Restart pod (force restart)
kubectl delete pod -n nova-backend -l app=matrix-synapse

# Check events
kubectl get events -n nova-backend --sort-by='.lastTimestamp' | grep synapse

# Describe pod for issues
kubectl describe pod -n nova-backend -l app=matrix-synapse
```

## Monitoring

```bash
# Watch pod status
kubectl get pods -n nova-backend -l app=matrix-synapse -w

# Monitor resource usage
kubectl top pod -n nova-backend -l app=matrix-synapse

# Check deployment status
kubectl rollout status deployment/matrix-synapse -n nova-backend

# View deployment history
kubectl rollout history deployment/matrix-synapse -n nova-backend

# Check service endpoints
kubectl get endpoints -n nova-backend matrix-synapse
```

## Common Issues & Fixes

### OIDC Login Fails

```bash
# Check OIDC config
kubectl get configmap matrix-synapse-config -n nova-backend -o yaml | grep -A 20 oidc_providers

# Verify client secret
kubectl get secret synapse-oidc-secrets -n nova-backend -o jsonpath='{.data.oidc_client_secret}' | base64 -d

# Check logs for errors
kubectl logs -n nova-backend -l app=matrix-synapse | grep -i "error.*oidc"
```

### Admin API 401 Error

```bash
# Regenerate admin token
cd /Users/proerror/Documents/Nova/backend/k8s/scripts
python3 create-synapse-admin.py --login

# Update secret with new token (copy command from script output)
```

### Well-Known 404

```bash
# Check well-known pod
kubectl get pods -n nova-backend -l app=matrix-well-known

# Check logs
kubectl logs -n nova-backend -l app=matrix-well-known

# Restart well-known deployment
kubectl rollout restart deployment/matrix-well-known -n nova-backend

# Test directly
kubectl port-forward -n nova-backend service/matrix-well-known 8080:80
curl http://localhost:8080/.well-known/matrix/client
```

### Pod Won't Start

```bash
# Check events
kubectl describe pod -n nova-backend -l app=matrix-synapse

# Check PVC status
kubectl get pvc -n nova-backend matrix-synapse-data

# Check secrets exist
kubectl get secrets -n nova-backend | grep synapse

# View init container logs
kubectl logs -n nova-backend -l app=matrix-synapse -c generate-config
```

## Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/matrix-synapse -n nova-backend

# Rollback to specific revision
kubectl rollout undo deployment/matrix-synapse -n nova-backend --to-revision=2

# Check rollout history
kubectl rollout history deployment/matrix-synapse -n nova-backend
```

## Cleanup

```bash
# Delete all Synapse resources
kubectl delete -k /Users/proerror/Documents/Nova/backend/k8s/overlays/staging

# Delete only OIDC configuration
kubectl delete -f synapse-oidc-patch.yaml

# Delete well-known resources
kubectl delete -f matrix-well-known.yaml

# Delete secrets (be careful!)
kubectl delete secret synapse-oidc-secrets -n nova-backend
kubectl delete secret synapse-admin-api -n nova-backend
```

## URLs

| Service | URL | Purpose |
|---------|-----|---------|
| Synapse Homeserver | https://matrix.staging.nova.app | Matrix client-server API |
| Well-Known Client | https://staging.nova.app/.well-known/matrix/client | Client discovery |
| Well-Known Server | https://staging.nova.app/.well-known/matrix/server | Server discovery |
| Zitadel OIDC | https://id.staging.nova.app | Identity provider |
| OIDC Callback | https://matrix.staging.nova.app/_synapse/client/oidc/callback | SSO redirect |
| Backchannel Logout | https://matrix.staging.nova.app/_synapse/client/oidc/backchannel_logout | Session termination |

## Key Configuration Values

| Setting | Value | Purpose |
|---------|-------|---------|
| Server Name | staging.nova.app | Matrix server identifier |
| Homeserver URL | https://matrix.staging.nova.app | Public homeserver URL |
| OIDC Issuer | https://id.staging.nova.app/ | Zitadel issuer URL |
| Client ID | synapse-nova-staging | Zitadel application ID |
| User ID Format | @nova-{UUID}:staging.nova.app | Matrix user ID pattern |
| Session Lifetime | 7d | Default session duration |
| Refresh Token Lifetime | 90d | Refresh token validity |

## File Locations

| File | Purpose |
|------|---------|
| `/Users/proerror/Documents/Nova/backend/k8s/overlays/staging/synapse-oidc-patch.yaml` | Main OIDC configuration |
| `/Users/proerror/Documents/Nova/backend/k8s/overlays/staging/synapse-secrets.yaml.template` | Secrets template |
| `/Users/proerror/Documents/Nova/backend/k8s/overlays/staging/matrix-well-known.yaml` | Well-known discovery |
| `/Users/proerror/Documents/Nova/backend/k8s/scripts/create-synapse-admin.py` | Admin user creation |
| `/Users/proerror/Documents/Nova/backend/k8s/overlays/staging/DEPLOYMENT_GUIDE.md` | Full deployment guide |
| `/Users/proerror/Documents/Nova/backend/k8s/overlays/staging/SYNAPSE_ADMIN_API.md` | Admin API documentation |
