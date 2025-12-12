# Zitadel Nova Integration - Quick Setup Guide

## Prerequisites

- Kubernetes cluster with Nova backend deployed
- Zitadel deployed and accessible at `id.staging.nova.app`
- kubectl access to `nova-backend` namespace
- Admin access to Zitadel console

## Quick Setup (5 Steps)

### 1. Generate API Key

```bash
# Generate secure API key (save this!)
export INTERNAL_API_KEY=$(openssl rand -hex 32)
echo "API Key: $INTERNAL_API_KEY"
```

### 2. Create Kubernetes Secrets

```bash
# Create identity-service secret
kubectl create secret generic identity-service-secrets \
  --from-literal=INTERNAL_API_KEY=$INTERNAL_API_KEY \
  -n nova-backend

# Create zitadel-action secret (same key)
kubectl create secret generic zitadel-action-secrets \
  --from-literal=INTERNAL_API_KEY=$INTERNAL_API_KEY \
  --from-literal=IDENTITY_SERVICE_URL=http://identity-service:8081 \
  -n nova-backend
```

### 3. Deploy Updated Identity Service

```bash
# Apply updated Kubernetes manifests
kubectl apply -f backend/k8s/base/identity-service.yaml
kubectl apply -f backend/k8s/base/zitadel-actions-config.yaml

# Verify deployment
kubectl rollout status deployment/identity-service -n nova-backend

# Test health endpoint
kubectl port-forward svc/identity-service 8081:8081 -n nova-backend &
curl http://localhost:8081/health
# Expected: OK
```

### 4. Configure Zitadel Action (via Console)

1. **Open**: https://id.staging.nova.app
2. **Login** with admin credentials
3. **Navigate**: Actions → Actions → New
4. **Configure**:
   - Name: `nova_claims_enrichment`
   - Timeout: 5000ms
   - Allow failure: ✅
5. **Script**: Copy from `backend/k8s/base/zitadel-action-nova-claims.js`
6. **Save**

**Important**: Update the API key in the script:
```javascript
// Replace this line:
const internalApiKey = process.env.INTERNAL_API_KEY;

// With:
const internalApiKey = '<your-api-key-from-step-1>';
```

### 5. Create Action Execution

1. **Navigate**: Actions → Executions → New
2. **Flow Type**: Complement Token
3. **Triggers**:
   - ✅ Pre Userinfo creation
   - ✅ Pre access token creation
4. **Action**: `nova_claims_enrichment`
5. **Save**

## Verification

### Test User Claims Endpoint

```bash
# Get a test user UUID from database
kubectl exec -it deployment/identity-service -n nova-backend -- \
  psql $DATABASE_URL -c "SELECT id, username, email FROM users LIMIT 1;"

# Copy the user ID, then test:
export USER_ID="<uuid-from-above>"
export API_KEY="<your-api-key>"

curl -H "X-Internal-API-Key: $API_KEY" \
  http://localhost:8081/internal/zitadel/user-claims/$USER_ID | jq
```

Expected response:
```json
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "preferred_username": "alice",
  "name": "Alice Smith",
  "email": "alice@nova.app",
  "email_verified": true,
  ...
}
```

### Test OIDC Flow (End-to-End)

1. Configure Matrix Synapse OIDC (if not done):
   ```yaml
   # homeserver.yaml
   oidc_providers:
     - idp_id: zitadel
       idp_name: "Nova SSO"
       issuer: "https://id.staging.nova.app"
       client_id: "<matrix-client-id>"
       client_secret: "<matrix-client-secret>"
       scopes: ["openid", "profile", "email"]
       user_mapping_provider:
         config:
           localpart_template: "{{ user.preferred_username }}"
           display_name_template: "{{ user.name }}"
   ```

2. Login via Matrix client
3. Inspect ID token (browser DevTools → Network → token response)
4. Decode at https://jwt.io - verify claims contain Nova data

## Troubleshooting

### Issue: "Invalid API key"

```bash
# Check secrets match
kubectl get secret identity-service-secrets -n nova-backend \
  -o jsonpath='{.data.INTERNAL_API_KEY}' | base64 -d
kubectl get secret zitadel-action-secrets -n nova-backend \
  -o jsonpath='{.data.INTERNAL_API_KEY}' | base64 -d
```

Both should output the same key.

### Issue: 404 on user claims endpoint

```bash
# Check identity-service logs
kubectl logs -f deployment/identity-service -n nova-backend

# Verify user exists
kubectl exec -it deployment/identity-service -n nova-backend -- \
  psql $DATABASE_URL -c "SELECT id FROM users WHERE id = '<user-uuid>';"
```

### Issue: Zitadel Action not executing

1. Check Zitadel console → Actions → Executions → Logs
2. Look for errors in execution history
3. Verify Action is attached to correct triggers (Pre Userinfo, Pre access token)

## Next Steps

- Read full documentation: `backend/docs/zitadel-nova-integration.md`
- Configure Matrix Synapse OIDC
- Test with real users
- Monitor Zitadel Action execution logs
- Set up alerts for API endpoint errors

## Support

- Documentation: `/backend/docs/zitadel-nova-integration.md`
- Issues: Create GitHub issue with `[zitadel]` tag
- Team: @backend-team on Slack
