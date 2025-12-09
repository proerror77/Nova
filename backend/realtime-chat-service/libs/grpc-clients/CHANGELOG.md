# gRPC Clients Library Changelog

## [2.0.0] - 2025-11-09

### 🔒 BREAKING CHANGES

**Mandatory TLS in Production/Staging**

- **BEFORE**: TLS was optional in all environments (`GRPC_TLS_ENABLED=false` allowed everywhere)
- **AFTER**: TLS is **MANDATORY** in `APP_ENV=production` or `APP_ENV=staging`
- **Impact**: Production/staging deployments will **FAIL TO START** if TLS is not properly configured

### ✨ New Features

#### Type-Safe TLS Configuration

**Replaced scattered Option fields with type-safe enum**:

```rust
// Old (5 separate fields, no constraints)
pub tls_enabled: bool,
pub tls_domain_name: Option<String>,
pub tls_ca_cert_path: Option<String>,
pub tls_client_cert_path: Option<String>,
pub tls_client_key_path: Option<String>,

// New (single enum, enforced constraints)
pub tls: TlsConfig,

pub enum TlsConfig {
    Disabled,
    Enabled {
        domain_name: String,
        ca_cert_path: PathBuf,
        client_identity: Option<ClientIdentity>,
    },
}
```

#### Environment-Based TLS Enforcement

```rust
enum Environment {
    Development,       // TLS optional (defaults to disabled)
    ProductionLike,    // TLS mandatory (staging + production)
}
```

**Detection logic**:
- `APP_ENV=production` → ProductionLike → TLS required
- `APP_ENV=staging` → ProductionLike → TLS required
- `APP_ENV=development` → Development → TLS optional
- (missing) → Development → TLS optional

#### Certificate Validation at Startup

**All certificate paths validated before service starts**:

```rust
// CA cert existence check
if !ca_cert_path.exists() {
    return Err("CA certificate not found: {path}");
}

// mTLS identity validation
if cert_path.exists() && !key_path.exists() {
    return Err("Client key not found: {path}");
}
```

**Benefit**: **Fail-fast** - errors detected at startup, not during runtime

### 🛠️ Code Quality Improvements

#### Eliminated Special Cases

**Before** (nested if statements):
```rust
if self.tls_enabled {
    if let Some(ca_path) = &self.tls_ca_cert_path {
        if let Some(domain) = &self.tls_domain_name {
            if let (Some(cert), Some(key)) = (...) {
                // 4 levels of nesting
            }
        }
    }
}
```

**After** (pattern matching, no special cases):
```rust
match &self.tls {
    TlsConfig::Disabled => Ok(ep),
    TlsConfig::Enabled { domain_name, ca_cert_path, client_identity } => {
        let tls = ClientTlsConfig::new()
            .ca_certificate(Certificate::from_pem(fs::read(ca_cert_path)?))
            .domain_name(domain_name);
        
        if let Some(identity) = client_identity {
            tls = tls.identity(...);
        }
        Ok(ep.tls_config(tls)?)
    }
}
```

#### Error Messages

**Before**: Generic errors
```rust
Err("TLS configuration error")
```

**After**: Actionable error messages
```rust
Err("gRPC TLS is MANDATORY in ProductionLike environment. Set GRPC_TLS_ENABLED=true")
Err("CA certificate not found: /etc/nova/certs/ca.pem")
Err("Both GRPC_TLS_CLIENT_CERT_PATH and GRPC_TLS_CLIENT_KEY_PATH must be set for mTLS")
```

### 🧪 Testing

**New test coverage**:
- ✅ `test_environment_detection` - Validates APP_ENV parsing
- ✅ `test_production_requires_tls` - Enforces TLS in production
- ✅ `test_development_allows_disabled_tls` - Allows optional TLS in dev
- ✅ `test_tls_requires_domain_and_ca` - Validates required TLS fields
- ✅ `test_mtls_requires_both_cert_and_key` - Enforces mTLS pairing

**All tests pass**: `cargo test --lib config::tests`

### 📚 Documentation

**New files**:
- `.env.example` - Environment variable template with TLS examples
- `TLS_MIGRATION.md` - Complete migration guide with troubleshooting
- `CHANGELOG.md` - This file

### 🔄 Migration Guide

See [`TLS_MIGRATION.md`](./TLS_MIGRATION.md) for complete upgrade instructions.

**Quick summary**:

1. **Development** - No changes required (TLS remains optional)
2. **Staging/Production** - Configure these environment variables:
   ```bash
   APP_ENV=production
   GRPC_TLS_ENABLED=true
   GRPC_TLS_DOMAIN_NAME=grpc.nova-platform.com
   GRPC_TLS_CA_CERT_PATH=/etc/nova/certs/ca.pem
   
   # Optional mTLS:
   GRPC_TLS_CLIENT_CERT_PATH=/etc/nova/certs/client.pem
   GRPC_TLS_CLIENT_KEY_PATH=/etc/nova/certs/client-key.pem
   ```

### 🐛 Bug Fixes

- **Fixed**: No validation of certificate paths (silent failures at runtime)
- **Fixed**: Incomplete mTLS configuration accepted (only cert or only key)
- **Fixed**: Environment-based security policies not enforced

### ⚙️ Internal Changes

- Refactored `from_env()` to extract `load_tls_config()` helper
- Changed TLS configuration from 5 fields to single `TlsConfig` enum
- Added `Environment` enum for environment detection
- Added `ClientIdentity` struct for mTLS pairing

### 📊 Metrics

**Code reduction**:
- `make_endpoint()`: 35 lines → 25 lines (-29%)
- Nesting depth: 4 levels → 2 levels (-50%)
- Pattern matches: Clear, exhaustive, no special cases

**Security improvements**:
- 🔒 Production TLS enforcement (P0 blocker prevention)
- 🔒 Certificate validation at startup (fail-fast)
- 🔒 mTLS pairing validation (prevent config errors)

---

## [1.0.0] - 2025-11-01

Initial release with optional TLS support.
