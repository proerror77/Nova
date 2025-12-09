# mTLS (Mutual TLS) Implementation Guide

**Version**: 0.2.0
**Last Updated**: 2025-11-11
**Security Level**: Production-Ready

---

## Table of Contents

1. [What is mTLS?](#what-is-mtls)
2. [Quick Start](#quick-start)
3. [Production Setup](#production-setup)
4. [Certificate Management](#certificate-management)
5. [Security Best Practices](#security-best-practices)
6. [Troubleshooting](#troubleshooting)
7. [FAQ](#faq)

---

## What is mTLS?

Mutual TLS (mTLS) is a security protocol where **both** the client and server authenticate each other using X.509 certificates. This provides:

- **Strong Authentication**: Certificate-based identity verification
- **Encryption**: All traffic encrypted with TLS 1.3
- **Zero Trust**: Services must prove their identity
- **Compliance**: Meets SOC2, PCI-DSS, HIPAA requirements

### Standard TLS vs mTLS

| Feature | Standard TLS | mTLS |
|---------|-------------|------|
| Server Authentication | ✅ Yes | ✅ Yes |
| Client Authentication | ❌ No | ✅ Yes |
| Use Case | Public APIs | Service-to-service |
| Security Level | Medium | High |

---

## Quick Start

### Development (5 minutes)

```rust
use grpc_tls::mtls::{MtlsServerConfig, MtlsClientConfig, TlsConfigPaths};
use grpc_tls::cert_generation::generate_dev_certificates;

// 1. Generate development certificates
let bundle = generate_dev_certificates()?;

// 2. Setup server with mTLS
let server_config = MtlsServerConfig::from_dev_bundle(&bundle).await?;
let tls_config = server_config.build_server_tls()?;

Server::builder()
    .tls_config(tls_config)?
    .add_service(my_service)
    .serve(addr)
    .await?;

// 3. Setup client with mTLS
let client_config = MtlsClientConfig::from_dev_bundle(&bundle, "localhost").await?;
let client_tls = client_config.build_client_tls()?;

let channel = Channel::from_static("https://localhost:50051")
    .tls_config(client_tls)?
    .connect()
    .await?;
```

⚠️ **WARNING**: Development certificates are self-signed. Never use in production!

---

## Production Setup

### Step 1: Generate Production Certificates

```bash
cd backend/libs/grpc-tls
./scripts/generate-production-certs.sh ./certs auth-service.nova.internal
```

This generates:
- `ca-cert.pem` - Certificate Authority (public, distribute to all services)
- `ca-key.pem` - CA private key (KEEP SECRET, store in vault)
- `server-cert.pem` - Server certificate
- `server-key.pem` - Server private key (KEEP SECRET)
- `client-cert.pem` - Client certificate
- `client-key.pem` - Client private key (KEEP SECRET)

### Step 2: Store Secrets Securely

**AWS Secrets Manager Example:**

```bash
# Store server credentials
aws secretsmanager create-secret \
  --name /nova/auth-service/server-cert \
  --secret-string file://certs/server-cert.pem

aws secretsmanager create-secret \
  --name /nova/auth-service/server-key \
  --secret-string file://certs/server-key.pem

# Store client credentials
aws secretsmanager create-secret \
  --name /nova/user-service/client-cert \
  --secret-string file://certs/client-cert.pem

aws secretsmanager create-secret \
  --name /nova/user-service/client-key \
  --secret-string file://certs/client-key.pem
```

### Step 3: Server Configuration

```rust
use grpc_tls::mtls::{MtlsServerConfig, TlsConfigPaths};

// Load paths from environment variables
let paths = TlsConfigPaths::from_env()?;

// Or load from AWS Secrets Manager
let paths = TlsConfigPaths {
    ca_cert_path: "/secrets/ca-cert.pem".into(),
    server_cert_path: "/secrets/server-cert.pem".into(),
    server_key_path: "/secrets/server-key.pem".into(),
    client_cert_path: None,
    client_key_path: None,
};

let mtls_config = MtlsServerConfig::from_paths(paths).await?;
let tls_config = mtls_config.build_server_tls()?;

// Use with Tonic server
Server::builder()
    .tls_config(tls_config)?
    .add_service(AuthServiceServer::new(service))
    .serve("[::]:50051".parse()?)
    .await?;
```

### Step 4: Client Configuration

```rust
use grpc_tls::mtls::{MtlsClientConfig, TlsConfigPaths};

let paths = TlsConfigPaths {
    ca_cert_path: "/secrets/ca-cert.pem".into(),
    server_cert_path: "/secrets/dummy.pem".into(), // Not used for client
    server_key_path: "/secrets/dummy.pem".into(),  // Not used for client
    client_cert_path: Some("/secrets/client-cert.pem".into()),
    client_key_path: Some("/secrets/client-key.pem".into()),
};

let mtls_config = MtlsClientConfig::from_paths(
    paths,
    "auth-service.nova.internal".to_string()
).await?;

let client_tls = mtls_config.build_client_tls()?;

let channel = Channel::from_static("https://auth-service:50051")
    .tls_config(client_tls)?
    .connect()
    .await?;

let mut client = AuthServiceClient::new(channel);
```

---

## Certificate Management

### Certificate Rotation (Zero Downtime)

```rust
use grpc_tls::mtls::MtlsServerConfig;
use tokio::time::{interval, Duration};

// Initial config
let mut current_config = MtlsServerConfig::from_paths(paths.clone()).await?;

// Reload certificates every 24 hours
let mut reload_interval = interval(Duration::from_secs(86400));

tokio::spawn(async move {
    loop {
        reload_interval.tick().await;

        match current_config.reload().await {
            Ok(new_config) => {
                current_config = new_config;
                tracing::info!("Certificates reloaded successfully");
            }
            Err(e) => {
                tracing::error!("Certificate reload failed: {}", e);
                // Keep using old config, alert monitoring
            }
        }
    }
});
```

### Certificate Expiration Monitoring

```rust
use grpc_tls::validate_cert_expiration;

// Check certificate validity (warn if < 30 days until expiration)
let server_cert = fs::read_to_string("/secrets/server-cert.pem")?;

match validate_cert_expiration(&server_cert, 30) {
    Ok(_) => tracing::info!("Certificate valid"),
    Err(e) if e.is_warning() => {
        tracing::warn!("Certificate expiring soon: {}", e);
        // Trigger alert to rotate certificates
    }
    Err(e) if e.is_blocker() => {
        tracing::error!("Certificate expired: {}", e);
        // CRITICAL: Service will fail to start
        return Err(e.into());
    }
    Err(e) => tracing::error!("Certificate validation error: {}", e),
}
```

### SAN (Subject Alternative Name) Validation

```rust
use grpc_tls::{validate_san, extract_san_entries};

// Extract SANs from certificate
let cert = fs::read_to_string("/secrets/server-cert.pem")?;
let san_entries = extract_san_entries(&cert)?;

tracing::info!("Certificate SANs: {:?}", san_entries);

// Validate expected SANs
let expected = vec![
    "auth-service.nova.internal".to_string(),
    "*.nova-backend.svc.cluster.local".to_string(),
];

validate_san(&cert, &expected)?;
```

---

## Security Best Practices

### 1. Certificate Storage

✅ **DO:**
- Store private keys in AWS Secrets Manager / HashiCorp Vault
- Use IAM roles for secret access (no hardcoded credentials)
- Encrypt secrets at rest with KMS
- Rotate certificates every 90 days (max 365 days)

❌ **DON'T:**
- Commit certificates to Git (add `*.pem` to `.gitignore`)
- Store keys in environment variables
- Share certificates between services
- Use self-signed certificates in production

### 2. Network Security

```rust
// ✅ GOOD: Enforce mTLS for all connections
let mtls_config = MtlsServerConfig::from_paths(paths).await?;

// ❌ BAD: Optional client certificates (allows unauthenticated access)
let tls_config = ServerTlsConfig::new()
    .identity(identity);  // No client CA = no mTLS
```

### 3. Certificate Validation

```rust
// Always validate on startup
let cert = fs::read_to_string(&paths.server_cert_path)?;

// Check expiration
validate_cert_expiration(&cert, 30)?;

// Verify SAN matches service domain
validate_san(&cert, &["auth-service.nova.internal".to_string()])?;

// Verify certificate chain (optional but recommended)
openssl::verify_cert_chain(&cert, &ca_cert)?;
```

### 4. Monitoring & Alerting

```rust
use opentelemetry::metrics::Counter;

// Track mTLS connection metrics
let mtls_success = meter.u64_counter("mtls.connections.success").init();
let mtls_failure = meter.u64_counter("mtls.connections.failure").init();
let cert_expiry_days = meter.i64_gauge("mtls.cert.days_until_expiry").init();

// Log mTLS events
tracing::info!(
    service = %service_name,
    client_cert_cn = %client_common_name,
    "mTLS connection established"
);
```

---

## Troubleshooting

### Error: "Certificate has expired"

```rust
// Check certificate validity
openssl x509 -in server-cert.pem -noout -enddate

// Fix: Generate new certificate
./scripts/generate-production-certs.sh ./new-certs auth-service.nova.internal
```

### Error: "SAN validation failed"

```rust
// Check certificate SANs
openssl x509 -in server-cert.pem -noout -text | grep -A1 "Subject Alternative Name"

// Fix: Regenerate with correct domain name
./scripts/generate-production-certs.sh ./certs correct-domain.nova.internal
```

### Error: "Client certificate missing"

```rust
// Ensure client cert/key paths are set
let paths = TlsConfigPaths {
    // ...
    client_cert_path: Some("/path/to/client-cert.pem".into()),  // Required!
    client_key_path: Some("/path/to/client-key.pem".into()),    // Required!
};
```

### Error: "Certificate read failed"

```bash
# Check file permissions
ls -la /secrets/*.pem

# Fix: Ensure service has read access
chmod 600 /secrets/*-key.pem  # Private keys (owner only)
chmod 644 /secrets/*-cert.pem # Certificates (world-readable)
chown service-user:service-group /secrets/*.pem
```

---

## FAQ

### Q: How often should I rotate certificates?

**A**: Recommended: Every **90 days**. Maximum: **365 days** (1 year).

### Q: Can I use the same certificate for multiple services?

**A**: No. Each service should have its own certificate with a unique Common Name (CN) and SAN.

### Q: What if my CA certificate expires?

**A**: You must generate a new CA and re-issue all certificates. Plan CA rotation carefully (validity: 5-10 years).

### Q: How do I test mTLS in development?

**A**: Use `generate_dev_certificates()` to create self-signed certificates. They work identically to production certificates.

### Q: Does mTLS work with Kubernetes?

**A**: Yes! Use cert-manager for automatic certificate provisioning:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: auth-service-mtls
spec:
  secretName: auth-service-tls
  issuerRef:
    name: nova-ca-issuer
    kind: ClusterIssuer
  commonName: auth-service.nova-backend.svc.cluster.local
  dnsNames:
    - auth-service
    - auth-service.nova-backend
    - auth-service.nova-backend.svc.cluster.local
```

---

## Additional Resources

- [RFC 5246 - TLS 1.2 Specification](https://tools.ietf.org/html/rfc5246)
- [RFC 8446 - TLS 1.3 Specification](https://tools.ietf.org/html/rfc8446)
- [NIST SP 800-52 - TLS Guidelines](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-52r2.pdf)
- [Tonic Documentation](https://docs.rs/tonic/latest/tonic/)

---

## Support

For issues or questions:
1. Check this guide and troubleshooting section
2. Review test cases in `tests/integration_test.rs`
3. Open an issue on the project repository
