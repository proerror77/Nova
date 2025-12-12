# Synapse Admin API Configuration Guide

This document describes how to configure and use the Synapse Admin API for the `realtime-chat-service` in the Nova platform.

## Overview

The Synapse Admin API allows the `realtime-chat-service` to programmatically manage Matrix users and devices. This is essential for operations like:

- Deactivating users when accounts are deleted
- Managing user devices and sessions
- Logging out users from all devices
- Querying user information

## Prerequisites

1. Synapse homeserver deployed and running
2. PostgreSQL database configured
3. OIDC authentication enabled
4. Access to the Kubernetes cluster

## Step 1: Create Admin User

### Generate Registration Shared Secret

First, generate a secure registration shared secret:

```bash
openssl rand -base64 32
```

### Apply the Secret

Create the secret file from the template:

```bash
cd /Users/proerror/Documents/Nova/backend/k8s/overlays/staging
cp synapse-secrets.yaml.template synapse-secrets.yaml
```

Edit `synapse-secrets.yaml` and fill in:
- `oidc_client_secret`: Get from Zitadel Console > Applications > synapse-nova-staging
- `registration_shared_secret`: Use the value generated above

Apply the secrets:

```bash
kubectl apply -f synapse-secrets.yaml
```

### Register Admin User

Use the registration shared secret to create an admin user via the Synapse Admin API:

```bash
# Get the registration shared secret
REGISTRATION_SECRET=$(kubectl get secret synapse-oidc-secrets -n nova-backend -o jsonpath='{.data.registration_shared_secret}' | base64 -d)

# Register admin user
curl -X POST "https://matrix.staging.nova.app/_synapse/admin/v1/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"nonce\": \"$(openssl rand -hex 16)\",
    \"username\": \"nova-admin\",
    \"password\": \"$(openssl rand -base64 24)\",
    \"admin\": true,
    \"mac\": \"HMAC_GENERATED_VALUE\"
  }"
```

**Note**: The HMAC generation is complex. Use the provided Python script instead:

```python
#!/usr/bin/env python3
# scripts/create-synapse-admin.py

import hmac
import hashlib
import json
import requests
import secrets

HOMESERVER_URL = "https://matrix.staging.nova.app"
REGISTRATION_SECRET = "YOUR_REGISTRATION_SECRET"  # From synapse-oidc-secrets

def generate_mac(nonce, username, password, admin=True):
    """Generate HMAC for user registration"""
    mac = hmac.new(
        key=REGISTRATION_SECRET.encode('utf-8'),
        digestmod=hashlib.sha1,
    )

    mac.update(nonce.encode('utf-8'))
    mac.update(b"\x00")
    mac.update(username.encode('utf-8'))
    mac.update(b"\x00")
    mac.update(password.encode('utf-8'))
    mac.update(b"\x00")
    mac.update(b"admin" if admin else b"notadmin")

    return mac.hexdigest()

def register_admin_user(username, password):
    """Register a new admin user"""
    nonce = secrets.token_hex(16)
    mac = generate_mac(nonce, username, password, admin=True)

    data = {
        "nonce": nonce,
        "username": username,
        "password": password,
        "admin": True,
        "mac": mac
    }

    response = requests.post(
        f"{HOMESERVER_URL}/_synapse/admin/v1/register",
        json=data
    )

    return response.json()

if __name__ == "__main__":
    username = "nova-admin"
    password = secrets.token_urlsafe(32)

    result = register_admin_user(username, password)
    print(f"Admin user created: {result}")
    print(f"Username: {username}")
    print(f"Password: {password}")
    print("\nSave these credentials securely!")
```

Run the script:

```bash
cd /Users/proerror/Documents/Nova/backend/k8s/scripts
python3 create-synapse-admin.py
```

## Step 2: Obtain Admin Access Token

Login with the admin user to get an access token:

```bash
curl -X POST "https://matrix.staging.nova.app/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "m.login.password",
    "identifier": {
      "type": "m.id.user",
      "user": "nova-admin"
    },
    "password": "YOUR_ADMIN_PASSWORD"
  }'
```

Response will contain:
```json
{
  "user_id": "@nova-admin:staging.nova.app",
  "access_token": "syt_...",
  "device_id": "DEVICEID"
}
```

## Step 3: Store Admin Token in Kubernetes

Update the `synapse-admin-api` secret with the access token:

```bash
kubectl create secret generic synapse-admin-api \
  --from-literal=SYNAPSE_ADMIN_TOKEN="syt_YOUR_TOKEN_HERE" \
  --from-literal=SYNAPSE_HOMESERVER_URL="http://matrix-synapse:8008" \
  --from-literal=SYNAPSE_SERVER_NAME="staging.nova.app" \
  --namespace=nova-backend \
  --dry-run=client -o yaml | kubectl apply -f -
```

Or edit the secret directly:

```bash
kubectl edit secret synapse-admin-api -n nova-backend
```

## Step 4: Configure realtime-chat-service

The `realtime-chat-service` should read the admin token from the Kubernetes secret.

### Environment Variables

Ensure the service deployment references the secret:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: realtime-chat-service
  namespace: nova-backend
spec:
  template:
    spec:
      containers:
        - name: realtime-chat-service
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
            - name: SYNAPSE_SERVER_NAME
              valueFrom:
                secretKeyRef:
                  name: synapse-admin-api
                  key: SYNAPSE_SERVER_NAME
```

## Admin API Usage Examples

### 1. Deactivate a User

When a user deletes their Nova account, deactivate their Matrix account:

```rust
// In realtime-chat-service/src/matrix/admin.rs

use reqwest::Client;
use serde_json::json;

pub struct SynapseAdminClient {
    homeserver_url: String,
    admin_token: String,
}

impl SynapseAdminClient {
    pub fn new(homeserver_url: String, admin_token: String) -> Self {
        Self {
            homeserver_url,
            admin_token,
        }
    }

    /// Deactivate a Matrix user account
    pub async fn deactivate_user(&self, user_id: &str) -> Result<(), Box<dyn std::error::Error>> {
        let client = Client::new();
        let url = format!(
            "{}/_synapse/admin/v1/deactivate/{}",
            self.homeserver_url,
            urlencoding::encode(user_id)
        );

        let response = client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.admin_token))
            .json(&json!({
                "erase": true  // Delete user data (GDPR compliance)
            }))
            .send()
            .await?;

        if response.status().is_success() {
            Ok(())
        } else {
            Err(format!("Failed to deactivate user: {}", response.status()).into())
        }
    }
}
```

### 2. List User Devices

Get all devices for a user:

```rust
pub async fn list_user_devices(&self, user_id: &str) -> Result<Vec<Device>, Box<dyn std::error::Error>> {
    let client = Client::new();
    let url = format!(
        "{}/_synapse/admin/v2/users/{}/devices",
        self.homeserver_url,
        urlencoding::encode(user_id)
    );

    let response = client
        .get(&url)
        .header("Authorization", format!("Bearer {}", self.admin_token))
        .send()
        .await?;

    let devices: DevicesResponse = response.json().await?;
    Ok(devices.devices)
}
```

### 3. Delete a Specific Device

Remove a device (logout from specific device):

```rust
pub async fn delete_device(&self, user_id: &str, device_id: &str) -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new();
    let url = format!(
        "{}/_synapse/admin/v2/users/{}/devices/{}",
        self.homeserver_url,
        urlencoding::encode(user_id),
        urlencoding::encode(device_id)
    );

    let response = client
        .delete(&url)
        .header("Authorization", format!("Bearer {}", self.admin_token))
        .send()
        .await?;

    if response.status().is_success() {
        Ok(())
    } else {
        Err(format!("Failed to delete device: {}", response.status()).into())
    }
}
```

### 4. Delete All User Devices

Logout user from all devices:

```rust
pub async fn logout_user_all_devices(&self, user_id: &str) -> Result<(), Box<dyn std::error::Error>> {
    // First get all devices
    let devices = self.list_user_devices(user_id).await?;

    // Delete each device
    for device in devices {
        self.delete_device(user_id, &device.device_id).await?;
    }

    Ok(())
}
```

### 5. Get User Information

Query user details:

```rust
pub async fn get_user_info(&self, user_id: &str) -> Result<UserInfo, Box<dyn std::error::Error>> {
    let client = Client::new();
    let url = format!(
        "{}/_synapse/admin/v2/users/{}",
        self.homeserver_url,
        urlencoding::encode(user_id)
    );

    let response = client
        .get(&url)
        .header("Authorization", format!("Bearer {}", self.admin_token))
        .send()
        .await?;

    let user_info: UserInfo = response.json().await?;
    Ok(user_info)
}
```

## Common Admin API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/_synapse/admin/v1/deactivate/{user_id}` | POST | Deactivate user account |
| `/_synapse/admin/v2/users/{user_id}` | GET | Get user information |
| `/_synapse/admin/v2/users/{user_id}/devices` | GET | List user devices |
| `/_synapse/admin/v2/users/{user_id}/devices/{device_id}` | DELETE | Delete specific device |
| `/_synapse/admin/v1/reset_password/{user_id}` | POST | Reset user password |
| `/_synapse/admin/v1/whois/{user_id}` | GET | Get user session info |

## Security Considerations

### 1. Token Security

- **NEVER** expose the admin token to clients
- Store token only in Kubernetes secrets
- Use RBAC to limit access to the secret
- Rotate the admin token periodically

### 2. API Access Control

- Admin API should only be called from `realtime-chat-service` backend
- Use internal service URLs (`http://matrix-synapse:8008`)
- Never expose admin endpoints via public ingress

### 3. Audit Logging

Log all admin API operations:

```rust
info!(
    user_id = %user_id,
    action = "deactivate_user",
    "Admin API: Deactivating Matrix user"
);
```

### 4. Error Handling

Handle API errors gracefully:

```rust
match admin_client.deactivate_user(&user_id).await {
    Ok(_) => info!("User deactivated successfully"),
    Err(e) => {
        error!("Failed to deactivate user: {}", e);
        // Don't fail the entire operation, log and continue
    }
}
```

## Testing

### Test Admin API Access

```bash
# Get admin token from secret
ADMIN_TOKEN=$(kubectl get secret synapse-admin-api -n nova-backend -o jsonpath='{.data.SYNAPSE_ADMIN_TOKEN}' | base64 -d)

# Test getting server version (requires admin)
curl -X GET "https://matrix.staging.nova.app/_synapse/admin/v1/server_version" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Expected response:
# {
#   "server_version": "1.98.0",
#   "python_version": "3.11"
# }
```

### Test User Management

```bash
# Create a test user via OIDC (login via Zitadel)
# Then test deactivating the user

USER_ID="@nova-SOME_UUID:staging.nova.app"

curl -X POST "https://matrix.staging.nova.app/_synapse/admin/v1/deactivate/${USER_ID}" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"erase": false}'
```

## Troubleshooting

### 401 Unauthorized

- Verify admin token is correct
- Ensure user has admin privileges
- Check token hasn't expired

### 403 Forbidden

- User is not an admin
- Re-create the admin user with `admin: true`

### Connection Refused

- Check Synapse service is running: `kubectl get pods -n nova-backend`
- Verify service URL is correct (use internal service name)

### OIDC Users Cannot Be Deactivated

- Ensure `erase: true` is set in the request
- OIDC users may need special handling

## References

- [Synapse Admin API Documentation](https://matrix-org.github.io/synapse/latest/usage/administration/admin_api/)
- [User Admin API](https://matrix-org.github.io/synapse/latest/admin_api/user_admin_api.html)
- [Device Management](https://matrix-org.github.io/synapse/latest/admin_api/user_admin_api.html#list-all-devices)

## Next Steps

1. Apply the secrets configuration
2. Create the admin user
3. Update `realtime-chat-service` to use admin API
4. Implement user lifecycle management
5. Add comprehensive error handling and logging
