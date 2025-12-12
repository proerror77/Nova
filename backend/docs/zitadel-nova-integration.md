# Zitadel & Nova User Sync Configuration

## Overview

This document describes the integration between Zitadel (OIDC Provider) and Nova's identity-service for user synchronization during Matrix SSO authentication.

## Architecture

### Design Decision: Strategy A - Real-time Claims Enrichment

We chose **Strategy A** (Zitadel fetches user data on-demand) over Strategy B (pre-sync users to Zitadel) for the following reasons:

1. **Single Source of Truth**: Nova identity-service remains the authoritative source for user data
2. **No Data Duplication**: Eliminates sync complexity and potential data inconsistency
3. **Real-time Updates**: User profile changes are immediately reflected in OIDC tokens
4. **Simpler Architecture**: No migration scripts or ongoing sync jobs needed
5. **Lower Latency**: HTTP call to internal service (~1-5ms) is negligible vs database migration overhead

### Data Flow

```
┌─────────────┐      OIDC Auth      ┌──────────────┐
│   Matrix    │ ──────────────────> │   Zitadel    │
│  Homeserver │                     │  (OIDC IdP)  │
└─────────────┘                     └──────────────┘
                                           │
                                           │ Zitadel Action
                                           │ (during token issuance)
                                           ▼
                                    ┌──────────────────┐
                                    │  identity-service│
                                    │  HTTP Endpoint   │
                                    │  GET /internal/  │
                                    │  zitadel/user-   │
                                    │  claims/:id      │
                                    └──────────────────┘
                                           │
                                           ▼
                                    ┌──────────────────┐
                                    │   PostgreSQL     │
                                    │   users table    │
                                    └──────────────────┘
```

### OIDC Claims Mapping

| OIDC Claim | Source | Description |
|------------|--------|-------------|
| `sub` | Nova `users.id` | User UUID (with dashes) - unique identifier |
| `preferred_username` | Nova `users.username` | Username for display |
| `name` | Nova `users.display_name` | Display name (fallback to username) |
| `email` | Nova `users.email` | Email address |
| `email_verified` | Nova `users.email_verified` | Email verification status |
| `picture` | Nova `users.avatar_url` | Profile picture URL |
| `given_name` | Nova `users.first_name` | First name (optional) |
| `family_name` | Nova `users.last_name` | Last name (optional) |
| `locale` | Nova `users.location` | User location (optional) |
| `phone_number` | Nova `users.phone_number` | Phone number (optional) |
| `phone_number_verified` | Nova `users.phone_verified` | Phone verification status |

### Custom Nova Claims (Namespaced)

| Claim | Source | Description |
|-------|--------|-------------|
| `https://nova.app/claims/bio` | Nova `users.bio` | User bio/description |
| `https://nova.app/claims/created_at` | Nova `users.created_at` | Account creation timestamp |
| `https://nova.app/claims/updated_at` | Nova `users.updated_at` | Last profile update timestamp |

## Implementation

### 1. Identity Service HTTP API

#### New Endpoint: GET /internal/zitadel/user-claims/:user_id

**Purpose**: Provide user claims data for Zitadel Actions to enrich OIDC tokens.

**Authentication**: Requires `X-Internal-API-Key` header matching `INTERNAL_API_KEY` environment variable.

**Request**:
```bash
curl -H "X-Internal-API-Key: <secret-key>" \
  http://identity-service:8081/internal/zitadel/user-claims/550e8400-e29b-41d4-a716-446655440000
```

**Response** (200 OK):
```json
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "preferred_username": "alice",
  "name": "Alice Smith",
  "email": "alice@nova.app",
  "email_verified": true,
  "picture": "https://cdn.nova.app/avatars/alice.jpg",
  "given_name": "Alice",
  "family_name": "Smith",
  "bio": "Software engineer and cat enthusiast",
  "locale": "San Francisco, CA",
  "phone_number": "+1234567890",
  "phone_number_verified": true,
  "created_at": 1704067200,
  "updated_at": 1735689600
}
```

**Error Response** (404 Not Found):
```json
{
  "error": "user_not_found",
  "message": "User not found: 550e8400-e29b-41d4-a716-446655440000"
}
```

**Implementation Files**:
- `/backend/identity-service/src/http/mod.rs` - HTTP server setup
- `/backend/identity-service/src/http/zitadel.rs` - User claims endpoint
- `/backend/identity-service/src/main.rs` - Start HTTP server alongside gRPC

### 2. Zitadel Action Configuration

#### Action: nova_claims_enrichment

**Type**: Complement Token Flow

**Triggers**:
- Pre Userinfo creation
- Pre access token creation

**JavaScript Code**: See `/backend/k8s/base/zitadel-action-nova-claims.js`

**Environment Variables** (configured in Zitadel Action):
- `IDENTITY_SERVICE_URL`: `http://identity-service:8081`
- `INTERNAL_API_KEY`: Secure API key (must match identity-service)

#### Action Logic

1. Extract user ID from Zitadel context (`ctx.user.id`)
2. Call Nova identity-service HTTP endpoint to fetch user claims
3. Parse JSON response
4. Inject claims into OIDC token using `api.v1.claims.setClaim()`
5. On error, fall back to Zitadel's built-in user data

#### Resilience Features

- **Graceful Degradation**: If identity-service is unavailable, use Zitadel user data as fallback
- **Error Logging**: All errors logged to Zitadel Actions console
- **Non-blocking**: Failures don't prevent token issuance

### 3. Kubernetes Configuration

#### Identity Service Deployment

**Changes to `/backend/k8s/base/identity-service.yaml`**:

1. **HTTP Server Port**: Port 8081 (already configured)
2. **gRPC Server Port**: Port 9081
3. **Environment Variable**: `INTERNAL_API_KEY` from secret
4. **Health Probes**: Updated to use `/health` endpoint

**New Secret**: `/backend/k8s/base/identity-service-secrets.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: identity-service-secrets
  namespace: nova-backend
type: Opaque
stringData:
  INTERNAL_API_KEY: "<generate-with-openssl-rand-hex-32>"
```

#### Zitadel Actions Configuration

**File**: `/backend/k8s/base/zitadel-actions-config.yaml`

Contains:
1. **ConfigMap**: JavaScript code for Zitadel Action (reference/documentation)
2. **Secret**: Environment variables for Zitadel Action (`INTERNAL_API_KEY`, `IDENTITY_SERVICE_URL`)

## Deployment Steps

### Step 1: Generate Shared API Key

```bash
# Generate a secure API key
openssl rand -hex 32

# Example output: a1b2c3d4e5f6...
```

### Step 2: Create Kubernetes Secrets

```bash
# Create identity-service secret
kubectl create secret generic identity-service-secrets \
  --from-literal=INTERNAL_API_KEY=<generated-key> \
  -n nova-backend

# Create zitadel-action secret (same key!)
kubectl create secret generic zitadel-action-secrets \
  --from-literal=INTERNAL_API_KEY=<same-generated-key> \
  --from-literal=IDENTITY_SERVICE_URL=http://identity-service:8081 \
  -n nova-backend
```

### Step 3: Deploy Updated Identity Service

```bash
# Build and push new identity-service image with HTTP API
cd backend/identity-service
docker build -t <registry>/nova-identity-service:latest .
docker push <registry>/nova-identity-service:latest

# Apply Kubernetes manifests
kubectl apply -f k8s/base/identity-service.yaml
kubectl apply -f k8s/base/identity-service-secrets.yaml
```

### Step 4: Configure Zitadel Action (Manual via UI)

1. **Login to Zitadel Console**: https://id.staging.nova.app
2. **Navigate to**: Actions → New Action
3. **Action Details**:
   - **Name**: `nova_claims_enrichment`
   - **Timeout**: 5000ms
   - **Allow failure**: Yes (graceful degradation)
4. **Script**: Copy content from `/backend/k8s/base/zitadel-action-nova-claims.js`
5. **Click**: Save

### Step 5: Create Action Execution

1. **Navigate to**: Actions → Executions → New
2. **Flow Type**: Complement Token
3. **Triggers**:
   - ✅ Pre Userinfo creation
   - ✅ Pre access token creation
4. **Action**: Select `nova_claims_enrichment`
5. **Click**: Save

### Step 6: Configure Action Environment Variables

**Note**: Zitadel Actions V2 environment variables are currently configured via the Zitadel console, not Kubernetes. Future versions may support external configuration.

1. **Navigate to**: Actions → `nova_claims_enrichment` → Settings
2. **Environment Variables** (if supported in your Zitadel version):
   - `IDENTITY_SERVICE_URL`: `http://identity-service:8081`
   - `INTERNAL_API_KEY`: `<your-generated-key>`

**Alternative (Hardcode in Action)**:
If environment variables are not supported, hardcode in the JavaScript:

```javascript
const identityServiceUrl = 'http://identity-service:8081';
const internalApiKey = '<your-generated-key>'; // NOT RECOMMENDED - security risk
```

**Recommended Workaround**: Use Zitadel User Metadata to store configuration per-organization.

## Testing

### Test 1: Health Check

```bash
# Test identity-service HTTP endpoint
kubectl port-forward svc/identity-service 8081:8081 -n nova-backend

curl http://localhost:8081/health
# Expected: OK
```

### Test 2: User Claims Endpoint (Authenticated)

```bash
# Get a valid Nova user UUID from database
export USER_ID="<valid-user-uuid>"
export API_KEY="<your-internal-api-key>"

curl -H "X-Internal-API-Key: $API_KEY" \
  http://localhost:8081/internal/zitadel/user-claims/$USER_ID

# Expected: JSON with user claims
```

### Test 3: Unauthorized Access

```bash
curl http://localhost:8081/internal/zitadel/user-claims/$USER_ID
# Expected: 401 Unauthorized
```

### Test 4: OIDC Token Claims (End-to-End)

1. **Configure Matrix Synapse** to use Zitadel OIDC
2. **Login** via Matrix client
3. **Inspect ID Token** (decode JWT at jwt.io):
   - Verify `sub` contains Nova user UUID
   - Verify `preferred_username` matches Nova username
   - Verify `email`, `picture`, etc. are populated

```bash
# Decode ID token (install jq)
echo "<id-token>" | cut -d. -f2 | base64 -d | jq

# Expected claims:
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "preferred_username": "alice",
  "email": "alice@nova.app",
  "email_verified": true,
  ...
}
```

## Monitoring

### Metrics

**Identity Service HTTP Endpoint**:
- Request count: `http_requests_total{endpoint="/internal/zitadel/user-claims"}`
- Response time: `http_request_duration_seconds{endpoint="/internal/zitadel/user-claims"}`
- Error rate: `http_requests_total{endpoint="/internal/zitadel/user-claims",status="5xx"}`

**Zitadel Action Logs**:
- Check Zitadel console → Actions → Executions → Logs
- Look for: "Successfully fetched Nova user claims"
- Errors: "ERROR: Failed to fetch user claims"

### Alerts

**Recommended Alerts**:
1. High error rate on user claims endpoint (> 5%)
2. Slow response time (p95 > 100ms)
3. Zitadel Action failures (if available via Zitadel metrics)

## Security Considerations

### 1. API Key Security

- **Secret Management**: Store `INTERNAL_API_KEY` in Kubernetes Secrets, never in code
- **Rotation**: Rotate API key every 90 days
- **Access Control**: Restrict identity-service HTTP port to internal cluster traffic only (NetworkPolicy)

### 2. Network Segmentation

**NetworkPolicy** (recommended):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: identity-service-http-ingress
  namespace: nova-backend
spec:
  podSelector:
    matchLabels:
      app: identity-service
  policyTypes:
  - Ingress
  ingress:
  # Allow HTTP from Zitadel only
  - from:
    - podSelector:
        matchLabels:
          app: zitadel
    ports:
    - protocol: TCP
      port: 8081
  # Allow gRPC from all backend services
  - from:
    - podSelector:
        matchLabels:
          component: backend
    ports:
    - protocol: TCP
      port: 9081
```

### 3. Rate Limiting

Future enhancement: Add rate limiting to `/internal/zitadel/user-claims` endpoint to prevent abuse.

### 4. Audit Logging

All user claims requests are logged with:
- User ID
- Timestamp
- Source IP (Zitadel pod)
- Success/failure status

## Troubleshooting

### Issue: "Invalid API key" errors

**Cause**: Mismatch between identity-service and Zitadel Action API keys

**Solution**:
```bash
# Verify secrets match
kubectl get secret identity-service-secrets -n nova-backend -o jsonpath='{.data.INTERNAL_API_KEY}' | base64 -d
kubectl get secret zitadel-action-secrets -n nova-backend -o jsonpath='{.data.INTERNAL_API_KEY}' | base64 -d

# Should output the same key
```

### Issue: "User not found" in Zitadel Action logs

**Cause**: Zitadel user ID doesn't match Nova user UUID

**Solution**: When creating users in Zitadel, ensure the user ID matches the Nova user UUID. Alternatively, store Nova user ID in Zitadel user metadata:

```javascript
// In Zitadel Action:
const novaUserId = ctx.user.metadata?.nova_user_id || ctx.user.id;
```

### Issue: OIDC tokens missing custom claims

**Causes**:
1. Zitadel Action not triggered
2. Action execution failed silently
3. identity-service HTTP endpoint unreachable

**Debugging**:
1. Check Zitadel Action execution logs
2. Test identity-service endpoint manually (see Testing section)
3. Check Kubernetes pod logs: `kubectl logs -f deployment/identity-service -n nova-backend`

### Issue: High latency on token issuance

**Cause**: Slow HTTP call to identity-service

**Solution**:
1. Verify identity-service is healthy and responsive
2. Check database query performance
3. Consider caching user claims in identity-service (Redis)

## Future Enhancements

### 1. Caching Layer

Add Redis caching to identity-service user claims endpoint:
- Cache TTL: 60 seconds
- Cache invalidation on user profile updates
- Reduces database load

### 2. Zitadel API Integration

Use Zitadel API to programmatically create/update Actions instead of manual UI configuration:
- `/management/v1/actions`
- `/management/v1/flows/{flowType}/trigger`

### 3. User Sync (Fallback Strategy)

If real-time claims enrichment proves unreliable, implement batch user sync:
1. Kafka consumer listens to `user.created` events
2. Create matching user in Zitadel via API
3. Store Nova user UUID in Zitadel user metadata

### 4. Matrix-Specific Claims

Add Matrix homeserver-specific claims for advanced features:
- Homeserver affinity
- Room join permissions
- Custom Matrix profile fields

## References

- [Zitadel Actions Documentation](https://zitadel.com/docs/guides/integrate/actions/usage)
- [Zitadel Actions Modules (HTTP)](https://zitadel.com/docs/apis/actions/modules)
- [Configuring Custom Claims in ZITADEL](https://zitadel.com/blog/custom-claims)
- [OIDC Standard Claims](https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims)
- [Matrix OIDC SSO Configuration](https://matrix-org.github.io/synapse/latest/openid.html)

## Contact

For questions or issues:
- Backend Team: @backend-team
- Security Review: @security-team
- DevOps Support: @devops-team
