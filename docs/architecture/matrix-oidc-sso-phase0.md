# Nova × Matrix OIDC SSO Integration - Phase 0: Environment Planning

> **Document Version**: 1.0
> **Date**: 2025-12-13
> **Status**: Planning
> **Author**: Nova Engineering

---

## 1. Executive Summary

This document establishes the foundational configuration for Nova's OIDC SSO integration with Matrix (Synapse). It defines domain names, URLs, secrets management, and environment variables required before implementation begins.

**Key Decisions Made**:
- OIDC Provider: **Zitadel** (Kubernetes-native, supports backchannel logout)
- UUID Format in mxid: **With dashes** (`@nova-550e8400-e29b-41d4-a716-446655440000:server`)
- Federation: **Disabled** (internal use only)

---

## 2. Domain & URL Configuration

### 2.1 Staging Environment

| Component | Internal URL | External URL | Notes |
|-----------|--------------|--------------|-------|
| **OIDC Issuer (Zitadel)** | `http://zitadel:8080` | `https://id.staging.nova.app` | Must be HTTPS externally |
| **Matrix Synapse** | `http://matrix-synapse:8008` | `https://matrix.staging.nova.app` | App direct-connect endpoint |
| **Identity Service** | `http://identity-service:8080` | `https://api.staging.nova.app/identity` | User store backend |
| **Nova API Gateway** | `http://graphql-gateway:4000` | `https://api.staging.nova.app` | Main API |

**Synapse Server Name**: `staging.nova.app`
**Example mxid**: `@nova-550e8400-e29b-41d4-a716-446655440000:staging.nova.app`

### 2.2 Production Environment

| Component | Internal URL | External URL | Notes |
|-----------|--------------|--------------|-------|
| **OIDC Issuer (Zitadel)** | `http://zitadel:8080` | `https://id.nova.app` | Must be HTTPS externally |
| **Matrix Synapse** | `http://matrix-synapse:8008` | `https://matrix.nova.app` | App direct-connect endpoint |
| **Identity Service** | `http://identity-service:8080` | `https://api.nova.app/identity` | User store backend |
| **Nova API Gateway** | `http://graphql-gateway:4000` | `https://api.nova.app` | Main API |

**Synapse Server Name**: `nova.app`
**Example mxid**: `@nova-550e8400-e29b-41d4-a716-446655440000:nova.app`

### 2.3 Critical Domain Rules

```
⚠️  MATRIX_SERVER_NAME must NEVER change after going live.
    Changing it invalidates ALL existing mxid values and breaks room membership.

⚠️  OIDC Issuer URL must be stable and match what's in ID tokens.
    Changing it breaks token validation across all clients.
```

---

## 3. OIDC Configuration

### 3.1 Zitadel OIDC Endpoints (Standard Discovery)

```yaml
# Well-known configuration: https://id.{env}.nova.app/.well-known/openid-configuration

issuer: "https://id.staging.nova.app"  # or https://id.nova.app for prod
authorization_endpoint: "https://id.staging.nova.app/oauth/v2/authorize"
token_endpoint: "https://id.staging.nova.app/oauth/v2/token"
userinfo_endpoint: "https://id.staging.nova.app/oidc/v1/userinfo"
jwks_uri: "https://id.staging.nova.app/oauth/v2/keys"
end_session_endpoint: "https://id.staging.nova.app/oidc/v1/end_session"
revocation_endpoint: "https://id.staging.nova.app/oauth/v2/revoke"
```

### 3.2 OIDC Client Registration (for Synapse)

```yaml
client_id: "synapse-nova-staging"  # or synapse-nova-prod
client_secret: "<generated-secure-secret>"
redirect_uris:
  - "https://matrix.staging.nova.app/_synapse/client/oidc/callback"
grant_types:
  - "authorization_code"
  - "refresh_token"
response_types:
  - "code"
scopes:
  - "openid"
  - "profile"
  - "email"
token_endpoint_auth_method: "client_secret_basic"
```

### 3.3 ID Token Claims Mapping

| OIDC Claim | Source (Nova) | Synapse Usage |
|------------|---------------|---------------|
| `sub` | `user.id` (UUID) | Matrix localpart: `nova-{sub}` |
| `preferred_username` | `user.username` | Display name fallback |
| `name` | `user.display_name` | Display name |
| `email` | `user.email` | Contact info |
| `email_verified` | `user.email_verified` | Verification status |
| `picture` | `user.avatar_url` | Matrix avatar |

---

## 4. Secrets Inventory

### 4.1 New Secrets Required

| Secret Name | Component | Purpose | Generation |
|-------------|-----------|---------|------------|
| `ZITADEL_MASTER_KEY` | Zitadel | Database encryption | `openssl rand -base64 32` |
| `ZITADEL_ADMIN_PASSWORD` | Zitadel | Initial admin user | Manual, strong password |
| `OIDC_CLIENT_SECRET` | Synapse | OIDC authentication | `openssl rand -base64 32` |
| `SYNAPSE_OIDC_CLIENT_SECRET_PATH` | Synapse | Path to mounted secret | `/secrets/oidc_client_secret` |

### 4.2 Existing Secrets (Keep)

| Secret Name | Kubernetes Secret | Used By |
|-------------|-------------------|---------|
| `POSTGRES_PASSWORD` | `matrix-synapse-secrets` | Synapse DB |
| `REGISTRATION_SHARED_SECRET` | `matrix-synapse-secrets` | Admin API user creation |
| `MACAROON_SECRET_KEY` | `matrix-synapse-secrets` | Token signing |
| `MATRIX_ACCESS_TOKEN` | `nova-matrix-service-token` | Service account |
| `JWT_SECRET_KEY` | `identity-service-secrets` | Nova JWT signing |

### 4.3 Kubernetes Secret Structure

```yaml
# backend/k8s/base/zitadel-secrets.yaml.template
apiVersion: v1
kind: Secret
metadata:
  name: zitadel-secrets
  namespace: nova-backend
type: Opaque
stringData:
  ZITADEL_MASTERKEY: "CHANGE_ME_32_BYTES_BASE64"
  ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD: "CHANGE_ME_ADMIN_PASSWORD"

---
# backend/k8s/base/synapse-oidc-secrets.yaml.template
apiVersion: v1
kind: Secret
metadata:
  name: synapse-oidc-secrets
  namespace: nova-backend
type: Opaque
stringData:
  oidc_client_secret: "CHANGE_ME_CLIENT_SECRET"
```

---

## 5. Environment Variables

### 5.1 Zitadel Configuration

```yaml
# Add to backend/k8s/base/configmap.yaml

# OIDC Provider (Zitadel)
ZITADEL_EXTERNALDOMAIN: "id.nova.app"
ZITADEL_EXTERNALPORT: "443"
ZITADEL_EXTERNALSECURE: "true"
ZITADEL_DATABASE_POSTGRES_HOST: "postgres"
ZITADEL_DATABASE_POSTGRES_PORT: "5432"
ZITADEL_DATABASE_POSTGRES_DATABASE: "zitadel"
ZITADEL_DATABASE_POSTGRES_USER_USERNAME: "zitadel"
ZITADEL_DATABASE_POSTGRES_ADMIN_USERNAME: "postgres"
```

### 5.2 Synapse OIDC Configuration

```yaml
# Add to staging overlay configmap

# Matrix OIDC SSO
MATRIX_OIDC_ENABLED: "true"
MATRIX_OIDC_ISSUER: "https://id.staging.nova.app"
MATRIX_OIDC_CLIENT_ID: "synapse-nova-staging"
MATRIX_OIDC_SCOPES: "openid profile email"
```

### 5.3 Identity Service Extensions

```yaml
# Future: when identity-service acts as user store for Zitadel

OIDC_PROVIDER_ENABLED: "true"
OIDC_PROVIDER_URL: "https://id.staging.nova.app"
```

---

## 6. iOS App Configuration

### 6.1 SSO Redirect URLs

```swift
// Staging
let matrixHomeserver = "https://matrix.staging.nova.app"
let ssoCallbackScheme = "nova-staging"  // Universal Link preferred
let ssoCallbackURL = "nova-staging://matrix-sso-callback"

// Production
let matrixHomeserver = "https://matrix.nova.app"
let ssoCallbackScheme = "nova"
let ssoCallbackURL = "nova://matrix-sso-callback"
```

### 6.2 Universal Links (Recommended)

```
# apple-app-site-association (on matrix.{env}.nova.app)
{
  "applinks": {
    "apps": [],
    "details": [{
      "appID": "TEAM_ID.app.nova.ios",
      "paths": ["/matrix-sso-callback/*"]
    }]
  }
}
```

---

## 7. UUID Format Standardization

### 7.1 Decision: Keep Dashes

```
✅  Correct:  @nova-550e8400-e29b-41d4-a716-446655440000:staging.nova.app
❌  Wrong:    @nova-550e8400e29b41d4a716446655440000:staging.nova.app
```

### 7.2 Code Changes Required

**File**: `backend/realtime-chat-service/src/services/matrix_client.rs:160`

```rust
// Current (INCORRECT - removes dashes):
format!("@{}:{}", user_id.to_string().replace("-", ""), ...)

// Should be (CORRECT - keeps dashes):
format!("@nova-{}:{}", user_id, server_name)
```

**Files to verify consistency**:
- `backend/realtime-chat-service/src/routes/matrix.rs:133` ✅ (already correct)
- `backend/realtime-chat-service/src/services/matrix_event_handler.rs:157` ✅ (extraction handles dashes)

---

## 8. DNS Requirements

### 8.1 Required DNS Records

| Record Type | Name | Value | TTL |
|-------------|------|-------|-----|
| A/CNAME | `id.staging.nova.app` | Load balancer IP/hostname | 300 |
| A/CNAME | `matrix.staging.nova.app` | Load balancer IP/hostname | 300 |
| A/CNAME | `id.nova.app` | Load balancer IP/hostname | 300 |
| A/CNAME | `matrix.nova.app` | Load balancer IP/hostname | 300 |

### 8.2 SSL/TLS Certificates

```yaml
# Use cert-manager with Let's Encrypt
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nova-oidc-tls
spec:
  secretName: nova-oidc-tls
  dnsNames:
    - id.staging.nova.app
    - matrix.staging.nova.app
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
```

---

## 9. Ingress Configuration

### 9.1 Zitadel Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: zitadel-ingress
  namespace: nova-backend
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-buffer-size: "128k"
spec:
  tls:
    - hosts:
        - id.staging.nova.app
      secretName: zitadel-tls
  rules:
    - host: id.staging.nova.app
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: zitadel
                port:
                  number: 8080
```

### 9.2 Matrix Synapse Ingress (Updated for SSO)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: matrix-synapse-ingress
  namespace: nova-backend
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  tls:
    - hosts:
        - matrix.staging.nova.app
      secretName: matrix-synapse-tls
  rules:
    - host: matrix.staging.nova.app
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: matrix-synapse
                port:
                  number: 8008
```

---

## 10. Rollback Strategy

### 10.1 Feature Flags

```yaml
# ConfigMap toggles
MATRIX_OIDC_ENABLED: "false"     # Disable OIDC, fall back to direct auth
MATRIX_SSO_WHITELIST: "user1,user2"  # Test with specific users first
```

### 10.2 Rollback Steps

1. Set `MATRIX_OIDC_ENABLED=false` in ConfigMap
2. Restart Synapse deployment
3. App falls back to legacy `/api/v2/matrix/token` (temporary)
4. Investigate and fix OIDC issues
5. Re-enable with `MATRIX_OIDC_ENABLED=true`

---

## 11. Pre-Implementation Checklist

- [ ] DNS records created for `id.{env}.nova.app` and `matrix.{env}.nova.app`
- [ ] SSL certificates provisioned (cert-manager configured)
- [ ] PostgreSQL database `zitadel` created with user
- [ ] Secrets generated and stored in k8s secrets
- [ ] Ingress controllers configured
- [ ] UUID format fix merged (`matrix_client.rs:160`)
- [ ] Team review of this document complete
- [ ] Staging environment ready for Zitadel deployment

---

## 12. Next Steps (Phase 1)

1. **Deploy Zitadel** to staging cluster
2. **Configure Nova as Identity Provider** in Zitadel (or use Zitadel's native user store)
3. **Register Synapse as OIDC client** in Zitadel admin console
4. **Test OIDC flow** with curl/browser before app integration

---

## Appendix A: Quick Reference Commands

```bash
# Generate secrets
openssl rand -base64 32  # For any 32-byte secret

# Create Zitadel database
psql -h postgres -U postgres -c "CREATE DATABASE zitadel;"
psql -h postgres -U postgres -c "CREATE USER zitadel WITH PASSWORD 'secret';"
psql -h postgres -U postgres -c "GRANT ALL ON DATABASE zitadel TO zitadel;"

# Test OIDC discovery
curl https://id.staging.nova.app/.well-known/openid-configuration | jq

# Verify Synapse SSO flow available
curl https://matrix.staging.nova.app/_matrix/client/v3/login | jq '.flows[] | select(.type == "m.login.sso")'
```

---

## Appendix B: Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              iOS App                                     │
├─────────────────────────────────────────────────────────────────────────┤
│  1. Login tap → Open SSO URL                                            │
│  2. ← Redirect to Zitadel login                                         │
│  3. User authenticates with Nova credentials                            │
│  4. ← Redirect back with loginToken                                     │
│  5. Exchange loginToken for Matrix access_token                         │
│  6. Direct Matrix API calls with user's own token                       │
└───────────────────┬─────────────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────┐     ┌───────────────────────────────┐
│         Zitadel (IdP)         │     │      Matrix Synapse (RP)      │
│  https://id.staging.nova.app  │◄───►│ https://matrix.staging.nova.app│
├───────────────────────────────┤     ├───────────────────────────────┤
│  • OIDC Authorization Server  │     │  • OIDC Client                │
│  • User authentication        │     │  • User auto-provisioning     │
│  • Token issuance             │     │  • mxid: @nova-{uuid}:server  │
│  • Session management         │     │  • Backchannel logout         │
└───────────────────┬───────────┘     └───────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────┐     ┌───────────────────────────────┐
│    Identity Service (Nova)    │     │   realtime-chat-service       │
│  (User Store / Future IdP)    │     │   (Admin operations only)     │
├───────────────────────────────┤     ├───────────────────────────────┤
│  • users, sessions tables     │     │  • Room creation/management   │
│  • Kafka: UserDeleted event   │     │  • Message sync (backup)      │
│  • Kafka: ProfileUpdated      │     │  • NO user tokens exposed     │
└───────────────────────────────┘     └───────────────────────────────┘
```
