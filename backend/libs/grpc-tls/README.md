# grpc-tls

**Production-grade mTLS (Mutual TLS) library for gRPC microservices**

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)]()
[![Security](https://img.shields.io/badge/security-mTLS-blue)]()
[![License](https://img.shields.io/badge/license-MIT-blue)]()

---

## Features

- ✅ **Production mTLS**: Mandatory client certificate verification
- ✅ **Certificate Rotation**: Hot reload without downtime
- ✅ **SAN Validation**: Prevent MITM attacks
- ✅ **Certificate Monitoring**: Automatic expiration warnings
- ✅ **TLS 1.3 Enforcement**: Modern crypto standards
- ✅ **Zero Unsafe Code**: Memory-safe implementation
- ✅ **Comprehensive Testing**: 11 integration tests

---

## Quick Start

### Add Dependency

```toml
[dependencies]
grpc-tls = { path = "../libs/grpc-tls" }
tonic = { version = "0.12", features = ["tls"] }
tokio = { version = "1", features = ["full"] }
```

### Server with mTLS

```rust
use grpc-tls::mtls::{MtlsServerConfig, TlsConfigPaths};
use tonic::transport::Server;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Load mTLS configuration
    let paths = TlsConfigPaths::from_env()?;
    let mtls_config = MtlsServerConfig::from_paths(paths).await?;
    let tls_config = mtls_config.build_server_tls()?;

    // Start gRPC server with mTLS
    Server::builder()
        .tls_config(tls_config)?
        .add_service(my_service)
        .serve("[::]:50051".parse()?)
        .await?;

    Ok(())
}
```

### Client with mTLS

```rust
use grpc-tls::mtls::{MtlsClientConfig, TlsConfigPaths};
use tonic::transport::Channel;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let paths = TlsConfigPaths {
        ca_cert_path: "/certs/ca.crt".into(),
        server_cert_path: "/certs/dummy.crt".into(),
        server_key_path: "/certs/dummy.key".into(),
        client_cert_path: Some("/certs/client.crt".into()),
        client_key_path: Some("/certs/client.key".into()),
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

    let mut client = MyServiceClient::new(channel);

    Ok(())
}
```

---

## Environment Variables

### Required (Server)

```bash
GRPC_CA_CERT_PATH=/certs/ca.crt           # CA certificate
GRPC_SERVER_CERT_PATH=/certs/server.crt   # Server certificate
GRPC_SERVER_KEY_PATH=/certs/server.key    # Server private key
```

### Required (Client with mTLS)

```bash
GRPC_CA_CERT_PATH=/certs/ca.crt           # CA certificate
GRPC_CLIENT_CERT_PATH=/certs/client.crt   # Client certificate
GRPC_CLIENT_KEY_PATH=/certs/client.key    # Client private key
GRPC_SERVER_DOMAIN=auth-service.nova.internal  # Server domain for validation
```

---

## Certificate Generation

### Development Certificates

```rust
use grpc_tls::cert_generation::generate_dev_certificates;

let bundle = generate_dev_certificates()?;
// Use bundle.ca_cert, bundle.server_cert, bundle.client_cert, etc.
```

### Production Certificates

```bash
cd backend/libs/grpc-tls
./scripts/generate-production-certs.sh ./certs auth-service.nova.internal
```

Generated files:
- `ca-cert.pem` - Certificate Authority (distribute to all services)
- `ca-key.pem` - CA private key (KEEP SECRET!)
- `server-cert.pem` - Server certificate
- `server-key.pem` - Server private key (KEEP SECRET!)
- `client-cert.pem` - Client certificate
- `client-key.pem` - Client private key (KEEP SECRET!)

⚠️ **Never commit `*-key.pem` files to version control!**

---

## Security Features

### Mandatory Client Certificate Verification

```rust
// Server ALWAYS requires client certificates
let mtls_config = MtlsServerConfig::from_paths(paths).await?;

// Will reject connections without valid client certificates
```

### SAN Validation

```rust
use grpc_tls::validate_san;

let cert = std::fs::read_to_string("/certs/server.crt")?;
let expected_sans = vec!["auth-service.nova.internal".to_string()];

validate_san(&cert, &expected_sans)?;  // Prevents MITM attacks
```

### Certificate Expiration Monitoring

```rust
use grpc_tls::validate_cert_expiration;

let cert = std::fs::read_to_string("/certs/server.crt")?;

// Warn if certificate expires in < 30 days
validate_cert_expiration(&cert, 30)?;
```

### Hot Certificate Rotation

```rust
let mtls_config = MtlsServerConfig::from_paths(paths).await?;

// Reload certificates without downtime
let new_config = mtls_config.reload().await?;
```

---

## Error Handling

All errors use `thiserror` for structured error types:

```rust
use grpc_tls::{TlsError, TlsResult};

match mtls_config.from_paths(paths).await {
    Ok(config) => { /* Success */ }
    Err(TlsError::CertificateExpiredError { expiry_date }) => {
        eprintln!("Certificate expired on {}", expiry_date);
    }
    Err(TlsError::MtlsClientCertMissing) => {
        eprintln!("Client certificate required for mTLS");
    }
    Err(TlsError::SanValidationError { expected, actual }) => {
        eprintln!("SAN mismatch: expected {} but found {}", expected, actual);
    }
    Err(e) => eprintln!("TLS error: {}", e),
}
```

---

## Testing

### Run All Tests

```bash
cd backend/libs/grpc-tls
cargo test
```

### Run Integration Tests

```bash
cargo test --test integration_test
```

**Test Coverage**:
- ✅ Server/Client mTLS configuration
- ✅ Certificate loading and validation
- ✅ SAN validation (exact match and wildcards)
- ✅ Certificate expiration checks
- ✅ Hot certificate rotation
- ✅ Error handling and edge cases

---

## Documentation

- **[MTLS_GUIDE.md](MTLS_GUIDE.md)** - Complete guide to mTLS implementation
- **API Documentation**: `cargo doc --open`

---

## Architecture

### Module Structure

```
grpc-tls/
├── src/
│   ├── lib.rs                 # Public API
│   ├── mtls.rs                # Production mTLS config
│   ├── san_validation.rs      # SAN validation logic
│   ├── cert_generation.rs     # Dev certificate generation
│   └── error.rs               # Structured error types
├── tests/
│   └── integration_test.rs    # Integration tests
├── scripts/
│   └── generate-production-certs.sh  # Production cert script
├── proto/
│   └── test.proto             # Test protobuf definitions
└── MTLS_GUIDE.md              # Complete usage guide
```

---

## Security Warnings

### ⚠️ NEVER in Production

```rust
// ❌ BAD: Development certificates in production
let bundle = generate_dev_certificates()?;

// ❌ BAD: No client certificate verification
let tls_config = ServerTlsConfig::new().identity(identity);

// ❌ BAD: Skipping SAN validation
// (Always validate SANs to prevent MITM)
```

### ✅ Always in Production

```rust
// ✅ GOOD: Production certificates from secure storage
let paths = TlsConfigPaths::from_env()?;
let mtls_config = MtlsServerConfig::from_paths(paths).await?;

// ✅ GOOD: Mandatory client certificate verification
let tls_config = mtls_config.build_server_tls()?;

// ✅ GOOD: Validate SANs
validate_san(&cert, &expected_sans)?;

// ✅ GOOD: Monitor certificate expiration
validate_cert_expiration(&cert, 30)?;
```

---

## License

MIT License - See [LICENSE](LICENSE) file for details

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit changes (`git commit -m 'Add my feature'`)
4. Push to branch (`git push origin feature/my-feature`)
5. Open a Pull Request

---

## Support

For questions or issues:
1. Review [MTLS_GUIDE.md](MTLS_GUIDE.md)
2. Check test cases in `tests/integration_test.rs`
3. Open an issue on the repository
