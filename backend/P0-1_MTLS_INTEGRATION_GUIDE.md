# P0-1: mTLS Integration Guide

## Overview

Based on Codex GPT-5 architectural review, all gRPC service-to-service communication must use mutual TLS (mTLS) to authenticate and encrypt traffic. This prevents CVSS 8.5 "Missing service-to-service authentication" vulnerability.

**Status**:
- ✅ K8s infrastructure (TLS secrets, cert-manager) deployed
- ✅ Dependencies added to 5 gRPC services
- ⏳ Code integration (this guide provides implementation pattern)

---

## Critical Security Issue (Codex Review)

> **"Missing or inconsistent service‑to‑service auth**: Require mTLS between all services and JWT claim propagation; enforce authorization in gRPC interceptors. This is a P0 per 'All endpoints authenticated'."

### Why mTLS?

- **Encryption**: All gRPC traffic encrypted with TLS 1.3
- **Authentication**: Both client and server verify each other's identity
- **Authorization**: Certificates contain service identity (CN/SAN)
- **Zero Trust**: No implicit trust within cluster network

---

## Architecture

### Certificate Management

```
cert-manager (K8s operator)
  ↓
ClusterIssuer (Self-signed CA for dev, real CA for prod)
  ↓
Certificate (wildcard *.nova.svc.cluster.local)
  ↓
Secret (grpc-tls-certs) → mounted to all gRPC services
```

### mTLS Handshake Flow

```
Client                          Server
  |                               |
  |--- ClientHello (TLS 1.3) ---->|
  |<-- ServerHello + Cert --------|  Server sends cert
  |--- Certificate Verify ------->|  Client sends cert
  |<-- Finished ------------------|  Both verify certs
  |                               |
  |=== Encrypted gRPC Traffic ===>|
```

---

## Integration Pattern

### Step 1: Add Dependency (✅ DONE for all gRPC services)

```toml
# Cargo.toml
[dependencies]
grpc-tls = { path = "../libs/grpc-tls" }
```

### Step 2: Server-Side mTLS Integration

**Before (no TLS)**:
```rust
use tonic::transport::Server;

#[tokio::main]
async fn main() -> Result<()> {
    let addr = "0.0.0.0:50051".parse()?;

    Server::builder()
        .add_service(MyServiceServer::new(my_impl))
        .serve(addr)
        .await?;

    Ok(())
}
```

**After (with mTLS)**:
```rust
use tonic::transport::Server;
use grpc_tls::GrpcServerTlsConfig;

#[tokio::main]
async fn main() -> Result<()> {
    let addr = "0.0.0.0:50051".parse()?;

    // Load TLS config from environment (K8s mounts certs to /etc/grpc-tls/)
    let tls_config = GrpcServerTlsConfig::from_env()?;
    let server_tls = tls_config.build_server_tls()?;

    Server::builder()
        .tls_config(server_tls)?  // ✅ Enable mTLS
        .add_service(MyServiceServer::new(my_impl))
        .serve(addr)
        .await?;

    Ok(())
}
```

### Step 3: Client-Side mTLS Integration

**Before (no TLS)**:
```rust
use tonic::transport::Channel;

async fn connect_to_service() -> Result<MyServiceClient<Channel>> {
    let channel = Channel::from_static("http://user-service:50051")
        .connect()
        .await?;

    Ok(MyServiceClient::new(channel))
}
```

**After (with mTLS)**:
```rust
use tonic::transport::Channel;
use grpc_tls::GrpcClientTlsConfig;

async fn connect_to_service() -> Result<MyServiceClient<Channel>> {
    // Load TLS config (K8s mounts certs to /etc/grpc-tls/)
    let tls_config = GrpcClientTlsConfig::from_env()?;
    let client_tls = tls_config.build_client_tls()?;

    let channel = Channel::from_static("https://user-service.nova.svc.cluster.local:50051")  // https://
        .tls_config(client_tls)?  // ✅ Enable mTLS
        .connect()
        .await?;

    Ok(MyServiceClient::new(channel))
}
```

---

## Environment Variables (Kubernetes ConfigMap)

The `grpc-tls` library reads these environment variables:

### Server Configuration

```bash
# Server certificate and key
GRPC_SERVER_CERT_PATH=/etc/grpc-tls/tls.crt
GRPC_SERVER_KEY_PATH=/etc/grpc-tls/tls.key

# Client CA certificate (for verifying client certs in mTLS)
GRPC_CLIENT_CA_CERT_PATH=/etc/grpc-tls/ca.crt

# Require client certificates (mTLS)
GRPC_REQUIRE_CLIENT_CERT=true
```

### Client Configuration

```bash
# Server CA certificate (to verify server identity)
GRPC_SERVER_CA_CERT_PATH=/etc/grpc-tls/ca.crt

# Client certificate and key (for mTLS authentication)
GRPC_CLIENT_CERT_PATH=/etc/grpc-tls/client.crt
GRPC_CLIENT_KEY_PATH=/etc/grpc-tls/client.key

# Server domain name (must match certificate SAN)
GRPC_SERVER_DOMAIN=user-service.nova.svc.cluster.local
```

---

## Kubernetes Deployment Changes

### Update Deployment YAML to Mount TLS Certificates

**Example**: `identity-service-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: identity-service
  namespace: nova
spec:
  template:
    spec:
      containers:
      - name: identity-service
        image: identity-service:v2.0.0
        ports:
        - containerPort: 50051  # gRPC with mTLS
        env:
        # Server TLS config
        - name: GRPC_SERVER_CERT_PATH
          value: /etc/grpc-tls/tls.crt
        - name: GRPC_SERVER_KEY_PATH
          value: /etc/grpc-tls/tls.key
        - name: GRPC_CLIENT_CA_CERT_PATH
          value: /etc/grpc-tls/ca.crt
        - name: GRPC_REQUIRE_CLIENT_CERT
          value: "true"

        # Client TLS config (for outgoing gRPC calls)
        - name: GRPC_SERVER_CA_CERT_PATH
          value: /etc/grpc-tls/ca.crt
        - name: GRPC_CLIENT_CERT_PATH
          value: /etc/grpc-tls/client.crt
        - name: GRPC_CLIENT_KEY_PATH
          value: /etc/grpc-tls/client.key

        volumeMounts:
        - name: grpc-tls-certs
          mountPath: /etc/grpc-tls
          readOnly: true

      volumes:
      - name: grpc-tls-certs
        secret:
          secretName: grpc-tls-certs  # Created by cert-manager
          defaultMode: 0400  # Read-only for security
```

---

## Priority Integration Points

### Phase 1: Critical Path Services (Week 1)

1. **identity-service** (authentication - highest priority)
   - Server: Enable mTLS on port 50051
   - No client calls (leaf service)

2. **user-service** (user profiles, feed generation)
   - Server: Enable mTLS on port 50052
   - Client: Calls identity-service for token validation

3. **content-service** (posts, comments)
   - Server: Enable mTLS on port 50053
   - Client: Calls user-service for user lookups

### Phase 2: Supporting Services (Week 2)

4. **search-service** (Elasticsearch indexing)
   - Server: Enable mTLS on port 50054
   - Client: Calls content-service for content metadata

5. **events-service** (event streaming, Kafka producer)
   - Server: Enable mTLS on port 50055
   - Client: Calls multiple services for event metadata

6. **media-service** (media uploads, S3 management)
   - Server: Enable mTLS on port 50056
   - Client: Calls user-service for quota checks

---

## Development vs Production

### Development Mode

For local development without K8s, use self-signed certificates:

```rust
// ⚠️ WARNING: Development only, NEVER in production
let tls_config = GrpcServerTlsConfig::development()?;
let server_tls = tls_config.build_server_tls()?;
```

This generates ephemeral self-signed certs with `rcgen`.

### Production Mode

Always use environment variables pointing to K8s-mounted certificates:

```rust
// ✅ Production: Load from K8s Secret via env vars
let tls_config = GrpcServerTlsConfig::from_env()
    .context("Failed to load TLS config - ensure K8s Secret is mounted")?;
```

---

## Certificate Rotation

cert-manager automatically rotates certificates 15 days before expiration. Services must handle rotation gracefully:

### Graceful Rotation Pattern

```rust
use grpc_tls::validate_cert_expiration;

// On startup, check certificate expiration
let cert_pem = fs::read_to_string("/etc/grpc-tls/tls.crt")?;
validate_cert_expiration(&cert_pem, 30)?;  // Warn if < 30 days

// Optional: Reload certificates on SIGHUP (advanced)
tokio::spawn(async {
    let mut sighup = tokio::signal::unix::signal(
        tokio::signal::unix::SignalKind::hangup()
    ).unwrap();

    while sighup.recv().await.is_some() {
        info!("Received SIGHUP - reloading TLS certificates");
        // Reload cert from disk, update server config
    }
});
```

---

## Testing mTLS Integration

### Unit Test (Development Certificates)

```rust
#[tokio::test]
async fn test_mtls_server_startup() {
    let tls_config = GrpcServerTlsConfig::development().unwrap();
    let server_tls = tls_config.build_server_tls().unwrap();

    let addr = "127.0.0.1:0".parse().unwrap();

    let server = Server::builder()
        .tls_config(server_tls).unwrap()
        .add_service(MyServiceServer::new(test_impl))
        .serve(addr);

    // Server should start without panicking
    tokio::time::timeout(Duration::from_secs(1), server)
        .await
        .expect_err("Server should not exit immediately");
}
```

### Integration Test (Real Certificates)

```rust
#[tokio::test]
#[ignore]  // Requires K8s environment with real certs
async fn test_mtls_client_server_communication() {
    // Start server with mTLS
    let server_task = tokio::spawn(async {
        let tls_config = GrpcServerTlsConfig::from_env().unwrap();
        // ...
    });

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Client connects with mTLS
    let client_tls = GrpcClientTlsConfig::from_env().unwrap()
        .build_client_tls().unwrap();

    let channel = Channel::from_static("https://localhost:50051")
        .tls_config(client_tls).unwrap()
        .connect()
        .await
        .expect("Client should connect with valid mTLS");

    // Test gRPC call
    let mut client = MyServiceClient::new(channel);
    let response = client.ping(Request::new(PingRequest {}))
        .await
        .expect("gRPC call should succeed with mTLS");

    assert_eq!(response.into_inner().message, "pong");
}
```

---

## Monitoring & Alerting

### Metrics to Track

```rust
// Prometheus metrics (pseudo-code)
counter!("grpc_tls_handshake_errors_total");
counter!("grpc_tls_cert_validation_failures_total");
histogram!("grpc_tls_handshake_duration_seconds");
gauge!("grpc_tls_cert_expiry_days");  // From validate_cert_expiration
```

### Alert Rules

```yaml
# Prometheus alert rules
- alert: GrpcTlsCertificateExpiringSoon
  expr: grpc_tls_cert_expiry_days < 15
  for: 24h
  annotations:
    summary: "gRPC TLS certificate expiring in {{ $value }} days"

- alert: GrpcTlsHandshakeFailures
  expr: rate(grpc_tls_handshake_errors_total[5m]) > 0.01
  for: 5m
  annotations:
    summary: "High gRPC TLS handshake failure rate: {{ $value }}/s"

- alert: GrpcTlsCertValidationFailures
  expr: rate(grpc_tls_cert_validation_failures_total[5m]) > 0
  for: 2m
  annotations:
    summary: "gRPC TLS certificate validation failures detected"
```

---

## Rollout Strategy

### Phase 1: Infrastructure Setup (✅ COMPLETE)
- Deploy cert-manager to Kubernetes cluster
- Create ClusterIssuer (self-signed CA for dev, real CA for prod)
- Generate wildcard certificate via Certificate CRD
- Verify Secret `grpc-tls-certs` populated with valid certs

### Phase 2: Dependencies & Deployments (IN PROGRESS)
- ✅ Add grpc-tls dependency to all gRPC services
- ⏳ Update Deployment YAMLs to mount TLS Secret
- ⏳ Add environment variables for TLS config paths

### Phase 3: Code Integration (Week 1-2)
- identity-service: Integrate server mTLS
- user-service: Integrate server + client mTLS (calls identity)
- content-service: Integrate server + client mTLS
- search-service, events-service, media-service: Same pattern

### Phase 4: Validation (Week 2)
- Verify all gRPC calls use https:// (not http://)
- Test certificate rotation (expire dev cert, verify auto-renewal)
- Run integration tests with mTLS enabled
- Monitor TLS handshake metrics

### Phase 5: Enforcement (Week 3)
- Set `GRPC_REQUIRE_CLIENT_CERT=true` in all services
- Disable non-TLS gRPC ports (if any HTTP fallback existed)
- Update NetworkPolicies to enforce TLS-only traffic

---

## Common Pitfalls

### ❌ DON'T: Mix HTTP and HTTPS URLs
```rust
// BAD: Client uses https:// but server expects http://
let channel = Channel::from_static("https://user-service:50051")
    .tls_config(client_tls)?
    .connect().await?;  // ❌ Will fail if server has no TLS
```

### ✅ DO: Consistent TLS on both sides
```rust
// GOOD: Both client and server use mTLS
// Server: .tls_config(server_tls)?
// Client: .tls_config(client_tls)?
let channel = Channel::from_static("https://user-service.nova.svc.cluster.local:50051")
    .tls_config(client_tls)?
    .connect().await?;  // ✅ Works
```

### ❌ DON'T: Hardcode certificate paths
```rust
// BAD: Hardcoded paths break portability
let cert_pem = fs::read_to_string("/home/user/certs/server.crt")?;
```

### ✅ DO: Use environment variables
```rust
// GOOD: K8s ConfigMap controls cert paths
let tls_config = GrpcServerTlsConfig::from_env()?;
```

### ❌ DON'T: Ignore certificate expiration
```rust
// BAD: Service crashes when cert expires
let tls_config = GrpcServerTlsConfig::from_env()?;
// No validation, service starts with expired cert
```

### ✅ DO: Validate on startup
```rust
// GOOD: Fail fast with clear error
let tls_config = GrpcServerTlsConfig::from_env()?;
let cert_pem = fs::read_to_string(&env::var("GRPC_SERVER_CERT_PATH")?)?;
validate_cert_expiration(&cert_pem, 30)?;  // Warn if < 30 days
```

---

## Troubleshooting

### "TLS handshake failed"

**Cause**: Client and server certs not from same CA, or CN/SAN mismatch.

**Fix**:
```bash
# Verify client and server certs are signed by same CA
openssl x509 -in /etc/grpc-tls/tls.crt -text -noout | grep Issuer
openssl x509 -in /etc/grpc-tls/client.crt -text -noout | grep Issuer

# Verify SAN matches GRPC_SERVER_DOMAIN
openssl x509 -in /etc/grpc-tls/tls.crt -text -noout | grep DNS
```

### "Certificate has expired"

**Cause**: cert-manager didn't rotate certificate, or service didn't reload.

**Fix**:
```bash
# Check Certificate status
kubectl describe certificate grpc-tls-cert -n nova

# Force renewal
kubectl delete secret grpc-tls-certs -n nova
# cert-manager will recreate it

# Restart services to reload new cert
kubectl rollout restart deployment identity-service -n nova
```

### "GRPC_SERVER_CERT_PATH not set"

**Cause**: K8s Secret not mounted, or environment variable missing.

**Fix**:
```yaml
# Deployment YAML
env:
- name: GRPC_SERVER_CERT_PATH
  value: /etc/grpc-tls/tls.crt
volumeMounts:
- name: grpc-tls-certs
  mountPath: /etc/grpc-tls
volumes:
- name: grpc-tls-certs
  secret:
    secretName: grpc-tls-certs
```

---

## Next Steps

1. **Update Deployment YAMLs** for all 5 gRPC services
2. **Integrate mTLS in main.rs** following patterns above
3. **Test in development** with self-signed certs
4. **Deploy to staging** with cert-manager real CA
5. **Monitor metrics** for TLS handshake errors
6. **Enforce mTLS** by setting `GRPC_REQUIRE_CLIENT_CERT=true`

---

## References

- Codex GPT-5 Architecture Review (2025-11-11) - P0 Priority
- `backend/libs/grpc-tls/src/lib.rs` - TLS library implementation
- `k8s/infrastructure/grpc-tls-*.yaml` - K8s TLS resources
- [Tonic TLS Guide](https://github.com/hyperium/tonic/blob/master/examples/src/tls/server.rs)
- [cert-manager Documentation](https://cert-manager.io/docs/)

---

**Author**: Nova Backend Team
**Last Updated**: 2025-11-11
**Status**: Phase 2 - Dependencies Added, Code Integration Pending
