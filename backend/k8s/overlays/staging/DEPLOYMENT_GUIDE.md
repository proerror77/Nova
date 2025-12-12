# Synapse OIDC Deployment Guide - Staging Environment

Complete guide for deploying Synapse with OIDC SSO and backchannel logout support in the Nova staging environment.

## Prerequisites

- Kubernetes cluster access (staging)
- kubectl configured for nova-backend namespace
- Zitadel OIDC application configured
- PostgreSQL database for Synapse

## Architecture Overview

```
┌─────────────────┐
│   iOS Client    │
│  (Element SDK)  │
└────────┬────────┘
         │
         │ Matrix Client-Server API
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│              Kubernetes Ingress (nginx)                 │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  matrix.staging.nova.app          staging.nova.app      │
│         │                               │               │
│         ▼                               ▼               │
│  ┌─────────────┐              ┌──────────────────┐     │
│  │   Synapse   │              │  Well-Known      │     │
│  │  Homeserver │              │  Discovery       │     │
│  └──────┬──────┘              └──────────────────┘     │
│         │                                               │
│         │ OIDC SSO                                      │
│         ▼                                               │
│  ┌─────────────────┐                                    │
│  │    Zitadel      │                                    │
│  │  (id.staging)   │                                    │
│  └─────────────────┘                                    │
│                                                          │
└─────────────────────────────────────────────────────────┘
         │
         │ Admin API
         ▼
┌─────────────────────┐
│ realtime-chat-      │
│     service         │
└─────────────────────┘
```

## Step 1: Configure Zitadel OIDC Application

### 1.1 Create OIDC Application

In Zitadel Console (https://id.staging.nova.app):

1. Navigate to: Projects > Nova > Applications
2. Click "New Application"
3. Select "Web Application"
4. Configure:
   - Name: `synapse-nova-staging`
   - Authentication Method: `Code`
   - Grant Types: `Authorization Code`, `Refresh Token`
   - Redirect URIs:
     ```
     https://matrix.staging.nova.app/_synapse/client/oidc/callback
     ```
   - Post Logout Redirect URIs:
     ```
     https://matrix.staging.nova.app/_synapse/client/oidc/logout
     ```
   - Backchannel Logout URI:
     ```
     https://matrix.staging.nova.app/_synapse/client/oidc/backchannel_logout
     ```

5. Save and note the **Client ID** and **Client Secret**

### 1.2 Configure Token Settings

In the application settings:

- Access Token Type: `JWT`
- ID Token Lifetime: `12h`
- Access Token Lifetime: `12h`
- Refresh Token Lifetime: `720h` (30 days)
- Enable Refresh Token Rotation: `Yes`

### 1.3 Configure Claims

Ensure these claims are included in ID token:
- `sub` (user ID)
- `email`
- `email_verified`
- `preferred_username`
- `name`
- `profile` (optional)

## Step 2: Create Kubernetes Secrets

### 2.1 Generate Secrets

Generate secure random values:

```bash
# Registration shared secret (for admin user creation)
openssl rand -base64 32

# Additional secrets if needed
openssl rand -base64 32
```

### 2.2 Create Secrets File

```bash
cd /Users/proerror/Documents/Nova/backend/k8s/overlays/staging

# Copy template
cp synapse-secrets.yaml.template synapse-secrets.yaml

# Edit and fill in actual values
# IMPORTANT: Do not commit synapse-secrets.yaml to git!
```

Fill in these values in `synapse-secrets.yaml`:

```yaml
stringData:
  oidc_client_secret: "<CLIENT_SECRET_FROM_ZITADEL>"
  registration_shared_secret: "<GENERATED_SECRET>"
```

### 2.3 Apply Secrets

```bash
kubectl apply -f synapse-secrets.yaml
```

Verify secrets are created:

```bash
kubectl get secrets -n nova-backend | grep synapse
```

Expected output:
```
synapse-oidc-secrets    Opaque    2    10s
synapse-admin-api       Opaque    3    10s
nova-matrix-service-token Opaque  3    10s
```

## Step 3: Deploy Synapse with OIDC Configuration

### 3.1 Apply Kustomization

```bash
cd /Users/proerror/Documents/Nova/backend/k8s/overlays/staging

# Build and preview
kubectl kustomize . | less

# Apply
kubectl apply -k .
```

### 3.2 Verify Deployment

Check Synapse pod is running:

```bash
kubectl get pods -n nova-backend -l app=matrix-synapse
```

Check logs:

```bash
kubectl logs -n nova-backend -l app=matrix-synapse --tail=100 -f
```

Look for these log lines indicating OIDC is configured:
```
Synapse now listening on port 8008
OIDC provider 'nova' configured
Backchannel logout enabled for OIDC provider 'nova'
```

### 3.3 Verify Ingress

Check ingress is configured:

```bash
kubectl get ingress -n nova-backend
```

Test endpoints:

```bash
# Test Matrix homeserver is accessible
curl https://matrix.staging.nova.app/_matrix/client/versions

# Test well-known discovery
curl https://staging.nova.app/.well-known/matrix/client

# Expected response:
# {
#   "m.homeserver": {
#     "base_url": "https://matrix.staging.nova.app"
#   },
#   ...
# }
```

## Step 4: Create Admin User for Admin API

### 4.1 Get Registration Secret

```bash
REGISTRATION_SECRET=$(kubectl get secret synapse-oidc-secrets -n nova-backend \
  -o jsonpath='{.data.registration_shared_secret}' | base64 -d)
```

### 4.2 Run Admin User Creation Script

```bash
cd /Users/proerror/Documents/Nova/backend/k8s/scripts

python3 create-synapse-admin.py \
  --homeserver https://matrix.staging.nova.app \
  --secret "$REGISTRATION_SECRET" \
  --username nova-admin \
  --login
```

This will:
1. Create admin user `nova-admin`
2. Generate secure password
3. Login and obtain access token
4. Display kubectl command to store the token

### 4.3 Store Admin Token

Copy the kubectl command from the script output and run it:

```bash
kubectl create secret generic synapse-admin-api \
  --from-literal=SYNAPSE_ADMIN_TOKEN='syt_YOUR_TOKEN_HERE' \
  --from-literal=SYNAPSE_HOMESERVER_URL='http://matrix-synapse:8008' \
  --from-literal=SYNAPSE_SERVER_NAME='staging.nova.app' \
  --namespace=nova-backend \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 4.4 Test Admin API Access

```bash
ADMIN_TOKEN=$(kubectl get secret synapse-admin-api -n nova-backend \
  -o jsonpath='{.data.SYNAPSE_ADMIN_TOKEN}' | base64 -d)

curl -X GET "https://matrix.staging.nova.app/_synapse/admin/v1/server_version" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Expected response:
# {
#   "server_version": "1.98.0",
#   "python_version": "3.11"
# }
```

## Step 5: Test OIDC SSO Flow

### 5.1 Access Synapse Login Page

Open in browser:
```
https://matrix.staging.nova.app/
```

You should see a login page with "Continue with Nova" SSO button.

### 5.2 Test SSO Login

1. Click "Continue with Nova"
2. Redirects to Zitadel: `https://id.staging.nova.app/oauth/v2/authorize?...`
3. Login with Zitadel credentials
4. Consent screen (if first time)
5. Redirects back to: `https://matrix.staging.nova.app/_synapse/client/oidc/callback`
6. Should complete login and create Matrix user

### 5.3 Verify User Creation

Check user was created with correct localpart:

```bash
# List users via Admin API
curl -X GET "https://matrix.staging.nova.app/_synapse/admin/v2/users?limit=10" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

User ID format should be: `@nova-{UUID}:staging.nova.app`

### 5.4 Test Backchannel Logout

1. Login to Synapse via OIDC
2. In another tab, logout from Zitadel
3. Zitadel should send backchannel logout to Synapse
4. User's Synapse session should be terminated

Verify in Synapse logs:

```bash
kubectl logs -n nova-backend -l app=matrix-synapse | grep backchannel
```

## Step 6: Configure realtime-chat-service

### 6.1 Update Service Deployment

Ensure `realtime-chat-service` deployment references the admin API secret:

```yaml
# In k8s/microservices/realtime-chat-service-deployment.yaml
env:
  - name: SYNAPSE_ADMIN_TOKEN
    valueFrom:
      secretKeyRef:
        name: synapse-admin-api
        key: SYNAPSE_ADMIN_TOKEN
  - name: SYNAPSE_HOMESERVER_URL
    valueFrom:
      secretKeyRef:
        name: synapse-admin-api
        key: SYNAPSE_HOMESERVER_URL
```

### 6.2 Redeploy realtime-chat-service

```bash
kubectl rollout restart deployment/realtime-chat-service -n nova-backend
```

### 6.3 Verify Service Access

Check service logs for Admin API initialization:

```bash
kubectl logs -n nova-backend -l app=realtime-chat-service | grep -i synapse
```

Expected log:
```
Synapse Admin API client initialized
Homeserver: http://matrix-synapse:8008
```

## Step 7: iOS Client Configuration

### 7.1 Update iOS App Matrix Configuration

In iOS app, configure Element/Matrix SDK:

```swift
// Use well-known discovery
let homeserverURL = "https://staging.nova.app"

// Element SDK will automatically fetch:
// https://staging.nova.app/.well-known/matrix/client
// and discover homeserver at https://matrix.staging.nova.app
```

### 7.2 Test iOS Login Flow

1. Open Nova iOS app
2. Navigate to messaging/chat feature
3. Should trigger OIDC SSO flow
4. Opens Safari/ASWebAuthenticationSession
5. Redirects to Zitadel login
6. After login, redirects back to app
7. App receives Matrix access token

## Verification Checklist

- [ ] Synapse pod is running and healthy
- [ ] OIDC provider configured in homeserver.yaml
- [ ] Backchannel logout enabled
- [ ] Ingress accessible (matrix.staging.nova.app)
- [ ] Well-known endpoints serving correct JSON
- [ ] Admin user created and can access Admin API
- [ ] Admin token stored in Kubernetes secret
- [ ] realtime-chat-service can access Admin API
- [ ] OIDC SSO login flow works in browser
- [ ] Users created with correct localpart format
- [ ] Backchannel logout triggers session termination
- [ ] iOS app can discover homeserver via well-known
- [ ] iOS app can complete OIDC login

## Troubleshooting

### OIDC Login Fails

Check Synapse logs:
```bash
kubectl logs -n nova-backend -l app=matrix-synapse | grep -i oidc
```

Common issues:
- Client secret mismatch
- Redirect URI not whitelisted in Zitadel
- JWKS fetch failure (check network/DNS)

### Backchannel Logout Not Working

Verify configuration:
```bash
kubectl get configmap matrix-synapse-config -n nova-backend -o yaml | grep backchannel
```

Should see:
```yaml
backchannel_logout_enabled: true
backchannel_logout_uri: "https://matrix.staging.nova.app/..."
```

Check Zitadel backchannel logout URI is configured.

### Admin API 401 Unauthorized

Token might be invalid or expired:
```bash
# Regenerate admin token
python3 scripts/create-synapse-admin.py --login
# Update secret with new token
```

### Well-Known Not Accessible

Check well-known pod:
```bash
kubectl get pods -n nova-backend -l app=matrix-well-known
kubectl logs -n nova-backend -l app=matrix-well-known
```

Test directly:
```bash
kubectl port-forward -n nova-backend service/matrix-well-known 8080:80
curl http://localhost:8080/.well-known/matrix/client
```

### Users Created with Wrong Format

Check user_mapping_provider configuration:
```bash
kubectl get configmap matrix-synapse-config -n nova-backend -o yaml | grep localpart_template
```

Should be:
```yaml
localpart_template: "nova-{{ user.sub }}"
```

## Rollback Procedure

If deployment fails, rollback:

```bash
# Rollback Synapse deployment
kubectl rollout undo deployment/matrix-synapse -n nova-backend

# Remove OIDC configuration (if needed)
kubectl apply -k /Users/proerror/Documents/Nova/backend/k8s/overlays/staging-previous

# Check pod status
kubectl get pods -n nova-backend -w
```

## Security Notes

1. Never commit `synapse-secrets.yaml` to git
2. Rotate admin tokens periodically (every 90 days)
3. Audit Admin API usage via logs
4. Limit Admin API access to backend services only
5. Enable rate limiting on OIDC endpoints
6. Monitor failed login attempts

## Maintenance

### Rotate Admin Token

```bash
# Create new admin user or re-login
python3 scripts/create-synapse-admin.py --login

# Update secret
kubectl create secret generic synapse-admin-api \
  --from-literal=SYNAPSE_ADMIN_TOKEN='NEW_TOKEN' \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart realtime-chat-service to pick up new token
kubectl rollout restart deployment/realtime-chat-service -n nova-backend
```

### Upgrade Synapse

```bash
# Update image tag in kustomization.yaml
images:
  - name: matrixdotorg/synapse
    newTag: v1.99.0  # New version

# Apply update
kubectl apply -k .

# Monitor rollout
kubectl rollout status deployment/matrix-synapse -n nova-backend
```

## References

- [Synapse OIDC Configuration](https://matrix-org.github.io/synapse/latest/openid.html)
- [Synapse Admin API](https://matrix-org.github.io/synapse/latest/usage/administration/admin_api/)
- [Matrix Well-Known](https://spec.matrix.org/latest/client-server-api/#well-known-uri)
- [Zitadel OIDC Documentation](https://zitadel.com/docs/apis/openidoauth/endpoints)
- SYNAPSE_ADMIN_API.md (this directory)
