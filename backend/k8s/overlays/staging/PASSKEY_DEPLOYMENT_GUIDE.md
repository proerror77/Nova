# Passkey (WebAuthn/FIDO2) Deployment Guide

## Prerequisites

### 1. Apple Developer Team ID

You need your Apple Developer Team ID to configure AASA.

**How to find your Team ID:**
1. Go to https://developer.apple.com/account
2. Click "Membership" in the left sidebar
3. Your Team ID is shown under "Membership Information" (10-character alphanumeric string)

**Or from Xcode:**
1. Open Xcode → Settings → Accounts
2. Select your Apple ID
3. Select your team and note the Team ID

### 2. Update Configuration Files

Replace `YOUR_TEAM_ID` in these files:

```bash
# Backend AASA ConfigMap
sed -i '' 's/YOUR_TEAM_ID/ACTUAL_TEAM_ID/g' \
  backend/k8s/overlays/staging/apple-well-known.yaml

# Static AASA file (for local testing)
sed -i '' 's/YOUR_TEAM_ID/ACTUAL_TEAM_ID/g' \
  backend/static/.well-known/apple-app-site-association
```

### 3. Update iOS Project Team ID

In Xcode:
1. Open the project
2. Select the target → Signing & Capabilities
3. Select your team from the dropdown
4. Enable "Automatically manage signing"

---

## Deployment Steps

### Step 1: Deploy Backend Services

```bash
# Apply Kustomize configuration
cd backend/k8s
kubectl apply -k overlays/staging

# Verify deployments
kubectl get pods -n nova-backend | grep -E "identity|graphql|apple-well-known"

# Check AASA is served correctly
curl -s https://staging.gcp.icered.com/.well-known/apple-app-site-association | jq
```

### Step 2: Run Database Migration

```bash
# Connect to database pod or run migration
kubectl exec -it deploy/identity-service -n nova-backend -- \
  /app/identity-service migrate

# Or run locally against staging DB
cd backend/identity-service
DATABASE_URL="postgres://..." sqlx migrate run
```

### Step 3: Verify Backend API

```bash
# Test Passkey API health (should return 401 Unauthorized for protected endpoints)
curl -X POST https://staging.gcp.icered.com/api/v2/auth/passkey/register/start \
  -H "Content-Type: application/json" \
  -d '{"credential_name": "Test"}'

# Expected: {"code":"unauthorized","message":"Authentication required"}

# Test authentication endpoint (public)
curl -X POST https://staging.gcp.icered.com/api/v2/auth/passkey/authenticate/start \
  -H "Content-Type: application/json" \
  -d '{}'

# Expected: Either passkey options or error if no passkeys registered
```

### Step 4: DNS Configuration (if using nova.app domain)

Ensure DNS points to your GCP load balancer:
```
nova.app A <LOAD_BALANCER_IP>
```

Or for staging, use the existing staging.gcp.icered.com domain.

---

## iOS Testing

### Test AASA Validation

Apple validates AASA files automatically. To test manually:

```bash
# Check AASA file format
curl -s https://nova.app/.well-known/apple-app-site-association | jq

# Validate with Apple's CDN (may take up to 24h to update)
# https://app-site-association.cdn-apple.com/a/v1/nova.app
```

### Test on Real Device

**Important:** Passkeys require a real device with Face ID/Touch ID. Simulator does not support WebAuthn.

1. Build the iOS app with the correct Team ID
2. Run on a real device with iOS 16+
3. Navigate to Settings → Passkeys
4. Tap "Add Passkey"
5. Authenticate with Face ID/Touch ID
6. Verify the passkey appears in the list

### Test Login Flow

1. Log out of the app
2. On login screen, select "Login with Passkey"
3. Face ID/Touch ID should prompt
4. Should log in successfully

---

## Environment Variables

Add to your staging ConfigMap or secrets:

```yaml
# Required
PASSKEY_ENABLED: "true"
PASSKEY_RP_ID: "nova.app"  # or "staging.gcp.icered.com" for staging
PASSKEY_RP_NAME: "Nova Social"
PASSKEY_ORIGIN: "https://nova.app"  # or "https://staging.gcp.icered.com"

# Optional (defaults shown)
PASSKEY_CHALLENGE_TTL_SECS: "300"
PASSKEY_REQUIRE_USER_VERIFICATION: "true"
PASSKEY_ALLOW_DISCOVERABLE_CREDENTIALS: "true"
```

---

## Troubleshooting

### "Invalid RP ID" Error

- Ensure `PASSKEY_RP_ID` matches the domain in Associated Domains
- Ensure `PASSKEY_ORIGIN` is the correct HTTPS URL

### AASA Not Loading

1. Check file is served with `Content-Type: application/json`
2. Check HTTPS certificate is valid
3. Apple caches AASA for 24h - changes may take time to propagate

### "No Passkeys Available"

- User must have at least one passkey registered
- Passkey must be registered with the same RP ID

### Sign-in With Apple Conflict

If using both Passkey and Sign in with Apple:
- Passkey uses `webcredentials` domain
- Sign in with Apple uses `applinks` domain
- Both can coexist in the same AASA file

---

## Security Checklist

- [ ] Team ID is correct in AASA
- [ ] HTTPS is enforced (no HTTP)
- [ ] Redis challenge TTL is reasonable (300s default)
- [ ] User verification is required
- [ ] Sign count is validated for clone detection
- [ ] Revoked passkeys are properly invalidated

---

## API Reference

### Registration (Requires Auth)

```
POST /api/v2/auth/passkey/register/start
POST /api/v2/auth/passkey/register/complete
```

### Authentication (Public)

```
POST /api/v2/auth/passkey/authenticate/start
POST /api/v2/auth/passkey/authenticate/complete
```

### Management (Requires Auth)

```
GET    /api/v2/auth/passkey/list
DELETE /api/v2/auth/passkey/{credential_id}
PUT    /api/v2/auth/passkey/{credential_id}/rename
```
