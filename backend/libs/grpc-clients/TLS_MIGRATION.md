# gRPC TLS Migration Guide

**Version**: 1.0  
**Date**: 2025-11-09  
**Breaking Change**: Production/Staging environments now REQUIRE TLS

---

## Overview

gRPC TLS is now **mandatory** in `production` and `staging` environments. This change ensures all inter-service communication is encrypted, preventing credential/PII leakage.

### What Changed

**Before**:
```bash
# TLS was optional everywhere
GRPC_TLS_ENABLED=false  # Allowed in production ❌
```

**After**:
```bash
# TLS is mandatory in production/staging
APP_ENV=production
GRPC_TLS_ENABLED=false  # ❌ STARTUP FAILS
```

---

## Migration Checklist

### 1. Development Environment (No Action Required)
- ✅ TLS remains **optional** in development
- ✅ Defaults to `GRPC_TLS_ENABLED=false`
- ✅ No configuration changes needed

### 2. Staging Environment (Action Required)

**Configure TLS**:
```bash
APP_ENV=staging
GRPC_TLS_ENABLED=true
GRPC_TLS_DOMAIN_NAME=grpc.staging.nova-platform.com
GRPC_TLS_CA_CERT_PATH=/etc/nova/certs/ca.pem

# Optional mTLS:
GRPC_TLS_CLIENT_CERT_PATH=/etc/nova/certs/client.pem
GRPC_TLS_CLIENT_KEY_PATH=/etc/nova/certs/client-key.pem
```

**Validate Certificates**:
```bash
# CA cert must exist
test -f "$GRPC_TLS_CA_CERT_PATH" || echo "CA cert missing!"

# If using mTLS
test -f "$GRPC_TLS_CLIENT_CERT_PATH" || echo "Client cert missing!"
test -f "$GRPC_TLS_CLIENT_KEY_PATH" || echo "Client key missing!"
```

### 3. Production Environment (Action Required)

Same as staging, but with production domain/certificates.

**Update Service URLs**:
```bash
# Change from http:// to https://
GRPC_AUTH_SERVICE_URL=https://auth-service.nova-platform.internal:9080
GRPC_USER_SERVICE_URL=https://user-service.nova-platform.internal:9081
# ... etc
```

---

## Error Messages & Troubleshooting

### Error: "gRPC TLS is MANDATORY in ProductionLike environment"

**Cause**: `GRPC_TLS_ENABLED=false` in production/staging  
**Fix**:
```bash
GRPC_TLS_ENABLED=true
```

### Error: "GRPC_TLS_DOMAIN_NAME is required when TLS is enabled"

**Cause**: TLS enabled but missing domain configuration  
**Fix**:
```bash
GRPC_TLS_DOMAIN_NAME=grpc.nova-platform.com
```

### Error: "CA certificate not found: /path/to/ca.pem"

**Cause**: Certificate file doesn't exist or wrong path  
**Fix**:
```bash
# Verify file exists
ls -l "$GRPC_TLS_CA_CERT_PATH"

# Check permissions (service user must have read access)
chmod 644 /path/to/ca.pem
```

### Error: "Both GRPC_TLS_CLIENT_CERT_PATH and GRPC_TLS_CLIENT_KEY_PATH must be set for mTLS"

**Cause**: Only one of client cert/key configured  
**Fix**:
```bash
# Either configure both:
GRPC_TLS_CLIENT_CERT_PATH=/path/to/client.pem
GRPC_TLS_CLIENT_KEY_PATH=/path/to/client-key.pem

# Or remove both for server-only TLS:
unset GRPC_TLS_CLIENT_CERT_PATH
unset GRPC_TLS_CLIENT_KEY_PATH
```

---

## Testing TLS Configuration

### Local Testing with Self-Signed Certificates

Generate test certificates:
```bash
# Generate CA
openssl req -x509 -newkey rsa:4096 -keyout ca-key.pem -out ca.pem \
  -days 365 -nodes -subj "/CN=Nova Test CA"

# Generate server cert
openssl req -newkey rsa:4096 -keyout server-key.pem -out server.csr \
  -nodes -subj "/CN=localhost"
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out server.pem -days 365

# Generate client cert (for mTLS)
openssl req -newkey rsa:4096 -keyout client-key.pem -out client.csr \
  -nodes -subj "/CN=Nova Client"
openssl x509 -req -in client.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out client.pem -days 365
```

Test configuration:
```bash
APP_ENV=staging
GRPC_TLS_ENABLED=true
GRPC_TLS_DOMAIN_NAME=localhost
GRPC_TLS_CA_CERT_PATH=./ca.pem
GRPC_TLS_CLIENT_CERT_PATH=./client.pem
GRPC_TLS_CLIENT_KEY_PATH=./client-key.pem
```

---

## Rollback Plan

If TLS causes production issues, you can temporarily override by changing `APP_ENV`:

```bash
# EMERGENCY ONLY - disables TLS enforcement
APP_ENV=development
GRPC_TLS_ENABLED=false
```

**⚠️ WARNING**: This bypasses security controls. Use only for emergency rollback. File incident ticket immediately.

---

## Security Best Practices

1. **Certificate Rotation**:
   - Rotate certificates every 90 days
   - Use cert-manager or similar for automation

2. **Private Key Protection**:
   ```bash
   # Restrict key file permissions
   chmod 600 /path/to/client-key.pem
   chown service-user:service-group /path/to/client-key.pem
   ```

3. **Certificate Validation**:
   - Verify certificate expiration: `openssl x509 -in ca.pem -noout -dates`
   - Monitor cert expiry with alerts (30/7/1 day warnings)

4. **mTLS Recommendation**:
   - Enable mTLS for all production inter-service communication
   - Use separate client certificates per service for audit trails

---

## Implementation Details

### Data Structure Changes

**Old** (scattered fields):
```rust
pub struct GrpcConfig {
    pub tls_enabled: bool,
    pub tls_domain_name: Option<String>,
    pub tls_ca_cert_path: Option<String>,
    pub tls_client_cert_path: Option<String>,
    pub tls_client_key_path: Option<String>,
}
```

**New** (type-safe):
```rust
pub enum TlsConfig {
    Disabled,
    Enabled {
        domain_name: String,
        ca_cert_path: PathBuf,
        client_identity: Option<ClientIdentity>,
    },
}

pub struct ClientIdentity {
    pub cert_path: PathBuf,
    pub key_path: PathBuf,
}
```

### Environment Detection

```rust
enum Environment {
    Development,
    ProductionLike, // staging + production
}

impl Environment {
    fn from_env() -> Self {
        match env::var("APP_ENV").as_deref() {
            Ok("production") | Ok("staging") => Self::ProductionLike,
            _ => Self::Development,
        }
    }

    fn requires_tls(&self) -> bool {
        matches!(self, Self::ProductionLike)
    }
}
```

---

## Support

For issues:
1. Check logs for detailed error messages
2. Verify certificate files exist and are readable
3. Test with `openssl s_client` if gRPC fails
4. Escalate to platform team if unresolved

**Contact**: #nova-platform-support
