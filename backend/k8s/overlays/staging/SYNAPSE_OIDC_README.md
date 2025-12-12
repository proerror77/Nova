# Synapse OIDC Configuration for Nova Staging

Complete Synapse OIDC SSO integration with backchannel logout support for the Nova platform.

## Overview

This configuration enables Matrix Synapse to authenticate users via Zitadel OIDC, providing seamless SSO integration for Nova's messaging features.

### Key Features

- OIDC SSO authentication via Zitadel
- Backchannel logout support for session management
- Session expiration and refresh token handling
- Matrix well-known auto-discovery for iOS clients
- Admin API access for realtime-chat-service
- Grayscale testing support via attribute requirements

## Files Structure

```
backend/k8s/overlays/staging/
├── synapse-oidc-patch.yaml           # Main OIDC configuration
├── synapse-secrets.yaml.template     # Secrets template (DO NOT COMMIT)
├── matrix-well-known.yaml            # Well-known discovery for clients
├── DEPLOYMENT_GUIDE.md               # Step-by-step deployment guide
├── SYNAPSE_ADMIN_API.md              # Admin API usage documentation
└── SYNAPSE_OIDC_README.md            # This file

backend/k8s/scripts/
└── create-synapse-admin.py           # Admin user creation script
```

## Quick Start

### 1. Prerequisites

- Kubernetes cluster with nova-backend namespace
- Zitadel OIDC application configured
- kubectl configured and authenticated

### 2. Create Secrets

```bash
cd backend/k8s/overlays/staging
cp synapse-secrets.yaml.template synapse-secrets.yaml
# Edit synapse-secrets.yaml with actual values
kubectl apply -f synapse-secrets.yaml
```

### 3. Deploy Synapse

```bash
kubectl apply -k .
```

### 4. Create Admin User

```bash
cd backend/k8s/scripts
python3 create-synapse-admin.py --login
```

### 5. Verify Deployment

```bash
# Check pods
kubectl get pods -n nova-backend -l app=matrix-synapse

# Test well-known
curl https://staging.nova.app/.well-known/matrix/client

# Test OIDC login (browser)
open https://matrix.staging.nova.app/
```

## Configuration Details

### OIDC Provider Configuration

```yaml
oidc_providers:
  - idp_id: nova
    idp_name: "Nova"
    issuer: "https://id.staging.nova.app/"
    client_id: "synapse-nova-staging"
    backchannel_logout_enabled: true
    backchannel_logout_uri: "https://matrix.staging.nova.app/_synapse/client/oidc/backchannel_logout"
```

### Session Management

- Session lifetime: 7 days
- Refresh token lifetime: 90 days
- Access token refresh: 10 minutes
- UI auth timeout: 15 minutes

### User ID Format

Users created via OIDC will have the format:
```
@nova-{UUID}:staging.nova.app
```

Where `{UUID}` is the user's `sub` claim from Zitadel.

### Backchannel Logout

When users logout from Zitadel:
1. Zitadel sends backchannel logout request to Synapse
2. Synapse terminates all active sessions for that user
3. User must re-authenticate on next access

## Admin API

The realtime-chat-service uses the Synapse Admin API for:

- User deactivation (when Nova account deleted)
- Device management (logout from specific devices)
- Session management (force logout)
- User information queries

See `SYNAPSE_ADMIN_API.md` for detailed usage examples.

## Well-Known Discovery

iOS clients can auto-discover the homeserver via:

```
https://staging.nova.app/.well-known/matrix/client
```

Response:
```json
{
  "m.homeserver": {
    "base_url": "https://matrix.staging.nova.app"
  }
}
```

This allows the iOS app to simply use `staging.nova.app` as the homeserver identifier.

## Grayscale Testing (Optional)

To enable user filtering for beta testing, uncomment in `synapse-oidc-patch.yaml`:

```yaml
attribute_requirements:
  - attribute: "email_verified"
    value: "true"
  - attribute: "groups"
    value: "nova-beta-testers"
```

This will only allow users with verified emails and in the `nova-beta-testers` group to login.

## Security Considerations

1. **Secrets Management**
   - Never commit `synapse-secrets.yaml` to git
   - Rotate admin tokens every 90 days
   - Use Kubernetes RBAC to limit secret access

2. **Admin API Access**
   - Admin token only accessible to backend services
   - All Admin API calls logged and audited
   - Use internal service URLs only

3. **OIDC Security**
   - Client secret stored in Kubernetes secret
   - JWKS verification enabled
   - Backchannel logout for session security

4. **Network Security**
   - Admin API not exposed via public ingress
   - Internal communication uses service mesh
   - TLS for all external endpoints

## Monitoring

### Health Checks

```bash
# Synapse health
curl https://matrix.staging.nova.app/health

# Well-known availability
curl https://staging.nova.app/.well-known/matrix/client

# Admin API access
curl -H "Authorization: Bearer $TOKEN" \
  https://matrix.staging.nova.app/_synapse/admin/v1/server_version
```

### Logs

```bash
# Synapse logs
kubectl logs -n nova-backend -l app=matrix-synapse -f

# Filter for OIDC events
kubectl logs -n nova-backend -l app=matrix-synapse | grep -i oidc

# Filter for backchannel logout
kubectl logs -n nova-backend -l app=matrix-synapse | grep backchannel
```

### Metrics

Synapse exposes Prometheus metrics at:
```
http://matrix-synapse:8008/_synapse/metrics
```

Key metrics to monitor:
- `synapse_http_server_requests_total{servlet="OIDCCallbackResource"}`
- `synapse_oidc_login_attempts_total`
- `synapse_admin_api_requests_total`

## Troubleshooting

### OIDC Login Fails

1. Check Synapse logs for OIDC errors
2. Verify Zitadel client secret matches
3. Ensure redirect URIs are whitelisted in Zitadel
4. Test JWKS endpoint is accessible

### Backchannel Logout Not Working

1. Verify backchannel_logout_uri in Zitadel matches Synapse config
2. Check Synapse logs for backchannel logout requests
3. Ensure Synapse ingress allows POST to backchannel endpoint

### Admin API Returns 401

1. Verify admin token is valid
2. Check admin user has admin privileges
3. Regenerate token if needed using `create-synapse-admin.py`

### Well-Known 404

1. Check well-known pod is running
2. Verify ingress routes /.well-known/matrix/* to well-known service
3. Test service directly with port-forward

See `DEPLOYMENT_GUIDE.md` for detailed troubleshooting steps.

## Maintenance Tasks

### Weekly
- Monitor Synapse pod resource usage
- Check error logs for OIDC failures
- Verify well-known endpoints are accessible

### Monthly
- Review Admin API usage logs
- Check session and token expiration settings
- Update Synapse image if new version available

### Quarterly
- Rotate admin API tokens
- Review and update OIDC configuration
- Audit user access patterns
- Update documentation if needed

## References

- [Deployment Guide](./DEPLOYMENT_GUIDE.md) - Complete deployment instructions
- [Admin API Guide](./SYNAPSE_ADMIN_API.md) - Admin API usage and examples
- [Synapse OIDC Docs](https://matrix-org.github.io/synapse/latest/openid.html)
- [Matrix Spec - Well-Known](https://spec.matrix.org/latest/client-server-api/#well-known-uri)
- [OpenID Connect Backchannel Logout](https://openid.net/specs/openid-connect-backchannel-1_0.html)

## Support

For issues or questions:
1. Check the troubleshooting section in DEPLOYMENT_GUIDE.md
2. Review Synapse logs
3. Consult Matrix.org Synapse documentation
4. Contact Nova platform team

## Version History

- 2024-12-13: Initial OIDC configuration with backchannel logout support
  - Added session management
  - Added well-known discovery
  - Added Admin API configuration
  - Added comprehensive documentation
