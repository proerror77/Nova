# Zitadel & Nova Integration - Implementation Summary

## What Was Implemented

This implementation enables **Zitadel to act as an OIDC Provider for Matrix SSO while using Nova's identity-service as the source of truth for user data**.

### Architecture Decision: Real-time Claims Enrichment

We chose **Strategy A** - Zitadel fetches user claims from Nova identity-service during token issuance via HTTP API call.

**Why Strategy A (vs pre-syncing users to Zitadel)?**
- ✅ Single source of truth (Nova identity-service)
- ✅ No data duplication or sync complexity
- ✅ Real-time profile updates reflected immediately
- ✅ Simpler architecture (no migration needed)
- ✅ Low latency (internal HTTP call ~1-5ms)

## Components Implemented

### 1. Identity Service HTTP API

**New Module**: `/backend/identity-service/src/http/`

**Key Files**:
- `src/http/mod.rs` - HTTP server setup with authentication middleware
- `src/http/zitadel.rs` - User claims endpoint implementation
- `src/main.rs` - Updated to start HTTP server on port 8081

**Endpoint**: `GET /internal/zitadel/user-claims/:user_id`

**Authentication**: `X-Internal-API-Key` header (configurable via `INTERNAL_API_KEY` env var)

**Response**: Standard OIDC claims + Nova-specific claims

### 2. Zitadel Action (JavaScript)

**File**: `/backend/k8s/base/zitadel-action-nova-claims.js`

**Functionality**:
- Executes during OIDC token issuance (Pre-Token Creation flow)
- Fetches user claims from identity-service HTTP endpoint
- Injects claims into ID token and UserInfo response
- Graceful degradation on errors (uses Zitadel fallback data)

**Triggers**:
- Pre Userinfo creation
- Pre access token creation

### 3. Kubernetes Configuration

**New Files**:
- `/backend/k8s/base/identity-service-secrets.yaml` - INTERNAL_API_KEY secret
- `/backend/k8s/base/zitadel-actions-config.yaml` - Action code and configuration

**Updated Files**:
- `/backend/k8s/base/identity-service.yaml` - Added HTTP port, API key env var, updated health probes

**Dependencies Added** (Cargo.toml):
- `axum = "0.7"` - HTTP server framework
- `tower = "0.5"` - Middleware support
- `tower-http = "0.6"` - CORS and tracing
- `hyper = "1.4"` - HTTP implementation

### 4. Documentation

**Comprehensive Docs**:
- `/backend/docs/zitadel-nova-integration.md` - Full integration guide (architecture, deployment, testing, troubleshooting)
- `/backend/docs/zitadel-quickstart.md` - Quick setup guide (5 steps)
- `/backend/docs/ZITADEL_INTEGRATION_SUMMARY.md` - This file

## OIDC Claims Mapping

| OIDC Claim | Nova Source | Required |
|------------|-------------|----------|
| `sub` | `users.id` (UUID) | ✅ |
| `preferred_username` | `users.username` | ✅ |
| `name` | `users.display_name` | ✅ |
| `email` | `users.email` | ✅ |
| `email_verified` | `users.email_verified` | ✅ |
| `picture` | `users.avatar_url` | Optional |
| `given_name` | `users.first_name` | Optional |
| `family_name` | `users.last_name` | Optional |
| `locale` | `users.location` | Optional |
| `phone_number` | `users.phone_number` | Optional |
| `phone_number_verified` | `users.phone_verified` | Optional |

**Custom Claims** (namespaced):
- `https://nova.app/claims/bio` - User bio
- `https://nova.app/claims/created_at` - Account creation timestamp
- `https://nova.app/claims/updated_at` - Last update timestamp

## Deployment Checklist

### Prerequisites
- [x] Zitadel deployed and accessible (https://id.staging.nova.app)
- [x] Identity-service running in Kubernetes
- [x] kubectl access to nova-backend namespace

### Setup Steps

1. **Generate API Key**
   ```bash
   openssl rand -hex 32
   ```

2. **Create Secrets**
   ```bash
   kubectl create secret generic identity-service-secrets \
     --from-literal=INTERNAL_API_KEY=<key> -n nova-backend
   ```

3. **Deploy Updated Identity Service**
   ```bash
   kubectl apply -f backend/k8s/base/identity-service.yaml
   ```

4. **Configure Zitadel Action** (Manual - via Zitadel Console)
   - Create Action: `nova_claims_enrichment`
   - Add script from `zitadel-action-nova-claims.js`
   - Configure environment variables (API key)

5. **Create Action Execution**
   - Flow: Complement Token
   - Triggers: Pre Userinfo, Pre access token

### Verification

- [ ] Health check: `curl http://identity-service:8081/health` → `OK`
- [ ] User claims endpoint works (with API key)
- [ ] OIDC token contains Nova user claims
- [ ] Matrix SSO login works end-to-end

## Security Features

### Authentication & Authorization
- ✅ Internal API key authentication (`X-Internal-API-Key` header)
- ✅ Middleware-based auth - all internal endpoints protected
- ✅ Health check endpoint public (no auth required)

### Network Security
- ✅ HTTP server only accessible within Kubernetes cluster
- ✅ Service type: ClusterIP (not exposed externally)
- ✅ Recommended: NetworkPolicy to restrict HTTP access to Zitadel pods only

### Secrets Management
- ✅ API key stored in Kubernetes Secret (not in code)
- ✅ Secret shared between identity-service and Zitadel Action
- ✅ Recommendation: Rotate API key every 90 days

### Resilience
- ✅ Graceful degradation in Zitadel Action (fallback to Zitadel user data)
- ✅ Error logging for debugging
- ✅ Non-blocking failures (don't prevent token issuance)

## Testing

### Unit Tests
- ✅ User claims serialization test in `zitadel.rs`

### Integration Tests
```bash
# Test user claims endpoint
curl -H "X-Internal-API-Key: <key>" \
  http://identity-service:8081/internal/zitadel/user-claims/<user-uuid>

# Expected: JSON with user claims
```

### End-to-End Tests
1. Configure Matrix Synapse OIDC
2. Login via Matrix client
3. Inspect ID token - verify Nova claims present

## Monitoring

### Metrics to Track
- HTTP request count: `/internal/zitadel/user-claims`
- Response time (p50, p95, p99)
- Error rate (4xx, 5xx)
- Zitadel Action execution success/failure

### Logs
- Identity-service: `kubectl logs -f deployment/identity-service -n nova-backend`
- Zitadel Action: Check Zitadel console → Actions → Executions → Logs

### Recommended Alerts
- User claims endpoint error rate > 5%
- Response time p95 > 100ms
- Zitadel Action failures

## Limitations & Future Work

### Current Limitations
1. **Zitadel Action Configuration**: Must be done manually via Zitadel console (not via Kubernetes)
2. **Environment Variables**: Zitadel Actions V2 may not support env vars in all versions (hardcoded fallback needed)
3. **User ID Mapping**: Assumes Zitadel user ID = Nova user UUID (or uses user metadata)

### Future Enhancements
1. **Caching Layer**: Add Redis cache to user claims endpoint (TTL: 60s)
2. **Zitadel API Automation**: Use Zitadel API to create Actions programmatically
3. **User Sync Fallback**: Implement batch user sync via Kafka events (Strategy B)
4. **Rate Limiting**: Protect user claims endpoint from abuse
5. **Matrix-Specific Claims**: Add homeserver affinity, room permissions

## Research References

This implementation was informed by:

### Zitadel Documentation
- [Configuring Custom Claims in ZITADEL](https://zitadel.com/blog/custom-claims) - Official guide on custom OIDC claims
- [ZITADEL Actions v2](https://zitadel.com/docs/concepts/features/actions_v2) - Actions architecture and capabilities
- [Using Actions](https://zitadel.com/docs/guides/integrate/actions/usage) - Practical implementation guide
- [Modules (HTTP Calls)](https://zitadel.com/docs/apis/actions/modules) - HTTP fetch API in Actions
- [Retrieve User Roles](https://zitadel.com/docs/guides/integrate/retrieve-user-roles) - User authorization patterns

### Standards
- [OIDC Standard Claims](https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims) - OpenID Connect specification
- [Matrix OIDC SSO](https://matrix-org.github.io/synapse/latest/openid.html) - Matrix Synapse OIDC configuration

## File Manifest

### Source Code
```
backend/identity-service/
├── Cargo.toml                          # Added: axum, tower, hyper
├── src/
│   ├── http/
│   │   ├── mod.rs                      # NEW: HTTP server setup
│   │   └── zitadel.rs                  # NEW: User claims endpoint
│   ├── lib.rs                          # Updated: Added http module
│   └── main.rs                         # Updated: Start HTTP server
```

### Kubernetes Configuration
```
backend/k8s/base/
├── identity-service.yaml               # Updated: HTTP port, API key, health probes
├── identity-service-secrets.yaml       # NEW: INTERNAL_API_KEY secret
├── zitadel-actions-config.yaml         # NEW: Action code and config
└── zitadel-action-nova-claims.js       # NEW: Zitadel Action JavaScript
```

### Documentation
```
backend/docs/
├── zitadel-nova-integration.md         # NEW: Comprehensive integration guide
├── zitadel-quickstart.md               # NEW: Quick setup guide
└── ZITADEL_INTEGRATION_SUMMARY.md      # NEW: This file
```

## Support

### Documentation
- **Full Guide**: `/backend/docs/zitadel-nova-integration.md`
- **Quick Setup**: `/backend/docs/zitadel-quickstart.md`
- **Summary**: `/backend/docs/ZITADEL_INTEGRATION_SUMMARY.md`

### Troubleshooting
- Check logs: `kubectl logs -f deployment/identity-service -n nova-backend`
- Test endpoint: See Testing section above
- Verify secrets: `kubectl get secret identity-service-secrets -n nova-backend`

### Contact
- Backend Team: @backend-team
- Security Review: @security-team
- DevOps Support: @devops-team

---

**Implementation Date**: 2025-12-13
**Author**: Backend Systems Architect (Claude)
**Status**: Ready for Deployment & Testing
