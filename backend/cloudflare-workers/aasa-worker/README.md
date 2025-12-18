# ICERED AASA Cloudflare Worker

Apple App Site Association (AASA) Worker for Passkey/WebAuthn and Universal Links.

## Quick Deploy

```bash
cd backend/cloudflare-workers/aasa-worker

# Install wrangler
npm install

# Login to Cloudflare (first time only)
npx wrangler login

# Deploy to production
npx wrangler deploy
```

## Verify Deployment

After deployment, verify the AASA endpoint:

```bash
# Check icered.com
curl -s https://icered.com/.well-known/apple-app-site-association | jq

# Check app.icered.com
curl -s https://app.icered.com/.well-known/apple-app-site-association | jq
```

Expected response:
```json
{
  "webcredentials": {
    "apps": ["ABC123XYZ0.com.libruce.icered"]
  },
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "ABC123XYZ0.com.libruce.icered",
        "paths": ["/reset-password/*", "/verify/*", "/invite/*", "/callback/*", "/auth/*"]
      }
    ]
  }
}
```

## Apple Validation

Use Apple's CDN validation tool:
```bash
curl -s "https://app-site-association.cdn-apple.com/a/v1/icered.com" | jq
```

Note: Apple caches AASA files for up to 24 hours.

## Routes

| Domain | Path | Description |
|--------|------|-------------|
| icered.com | /.well-known/apple-app-site-association | Production AASA |
| app.icered.com | /.well-known/apple-app-site-association | Production AASA (app subdomain) |

## Troubleshooting

### Worker not triggering
Ensure routes are correctly configured in Cloudflare Dashboard:
1. Go to Workers & Pages > icered-aasa
2. Check "Triggers" tab for route bindings
3. Verify zone_name matches your Cloudflare zone

### AASA not updating on iOS
- Apple caches AASA for 24 hours
- Delete and reinstall app to force refresh
- Or wait 24 hours for cache to expire
