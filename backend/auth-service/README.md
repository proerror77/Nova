# Nova Auth Service

A production-grade authentication and authorization service for the Nova platform, built with Rust and gRPC.

## Overview

The Auth Service handles all user authentication, identity verification, and access control for Nova services. It provides:

- **User Registration and Login** - Secure account creation and authentication
- **JWT Token Management** - RS256-signed access and refresh tokens
- **Password Security** - Argon2id hashing with zxcvbn strength validation
- **Account Lockout** - Brute-force protection (5 failed attempts → 15 minute lockout)
- **Session Management** - Stateless JWT with configurable expiration
- **gRPC API** - High-performance inter-service communication
- **Observability** - Prometheus metrics and structured logging

## Quick Start

### Prerequisites

- Rust 1.75+
- PostgreSQL 15+
- Redis 7+

### Environment Variables

```bash
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/nova_auth

# Redis
REDIS_URL=redis://localhost:6379

# JWT Keys (RS256)
JWT_PRIVATE_KEY_PEM="-----BEGIN PRIVATE KEY-----\n..."
JWT_PUBLIC_KEY_PEM="-----BEGIN PUBLIC KEY-----\n..."

# Service Configuration
AUTH_SERVICE_PORT=50051
LOG_LEVEL=info
```

### Running the Service

```bash
# Development
cargo run

# Production
cargo build --release
./target/release/auth-service
```

## gRPC API

### Register - Create New Account

```protobuf
rpc Register(RegisterRequest) returns (RegisterResponse);

message RegisterRequest {
    string email = 1;        // User email (must be valid format)
    string username = 2;     // Username (3-32 alphanumeric + underscore)
    string password = 3;     // Password (validated by zxcvbn score >= 3)
}

message RegisterResponse {
    string user_id = 1;         // UUID of newly created user
    string token = 2;           // JWT access token (expires in 3600s)
    string refresh_token = 3;   // Refresh token (30-day validity)
    int64 expires_in = 4;       // Token expiration in seconds
}
```

**Example - Register:**

```rust
let client = AuthServiceClient::new(channel);

let request = RegisterRequest {
    email: "user@example.com".to_string(),
    username: "john_doe".to_string(),
    password: "MySecurePassword2025!".to_string(),
};

let response = client.register(request).await?;
println!("User created: {}", response.user_id);
println!("Token: {}", response.token);
```

**Possible Responses:**
- `Status::Ok` - Registration successful (HTTP 200)
- `Status::InvalidArgument` - Invalid email, username, or weak password (HTTP 400)
- `Status::AlreadyExists` - Email already registered (HTTP 409)
- `Status::Internal` - Database error (HTTP 500)

### Login - Authenticate User

```protobuf
rpc Login(LoginRequest) returns (LoginResponse);

message LoginRequest {
    string email = 1;      // User email address
    string password = 2;   // User password (plain text, validated against hash)
}

message LoginResponse {
    string user_id = 1;         // UUID of authenticated user
    string token = 2;           // JWT access token (expires in 3600s)
    string refresh_token = 3;   // Refresh token
    int64 expires_in = 4;       // Token expiration in seconds
}
```

**Example - Login:**

```rust
let request = LoginRequest {
    email: "user@example.com".to_string(),
    password: "MySecurePassword2025!".to_string(),
};

let response = client.login(request).await?;
println!("Login successful: {}", response.user_id);
println!("Token: {}", response.token);
```

**Security Features:**
- Account lockout after 5 failed attempts (15 minute lockout period)
- Constant-time password comparison (prevents timing attacks)
- Failed attempt tracking with automatic reset after successful login

**Possible Responses:**
- `Status::Ok` - Login successful (HTTP 200)
- `Status::Unauthenticated` - Invalid email or wrong password (HTTP 401)
- `Status::PermissionDenied` - Account locked due to failed attempts (HTTP 403)

### Refresh - Get New Access Token

```protobuf
rpc Refresh(RefreshTokenRequest) returns (RefreshTokenResponse);

message RefreshTokenRequest {
    string refresh_token = 1;   // Refresh token from previous login/register
}

message RefreshTokenResponse {
    string token = 1;           // New JWT access token (expires in 3600s)
    int64 expires_in = 2;       // Token expiration in seconds
}
```

**Example - Refresh Token:**

```rust
let request = RefreshTokenRequest {
    refresh_token: previous_refresh_token.clone(),
};

let response = client.refresh(request).await?;
println!("New token issued: {}", response.token);
```

**Possible Responses:**
- `Status::Ok` - New token issued (HTTP 200)
- `Status::Unauthenticated` - Refresh token expired or invalid (HTTP 401)

## JWT Token Format

All tokens use **RS256 (RSA with SHA-256)** for signing.

### Access Token (1 hour validity)

```json
{
    "sub": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "username": "john_doe",
    "token_type": "access",
    "iat": 1672531200,
    "exp": 1672534800
}
```

### Refresh Token (30 day validity)

```json
{
    "sub": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "username": "john_doe",
    "token_type": "refresh",
    "iat": 1672531200,
    "exp": 1675209600
}
```

## Validation Services

Additional gRPC methods for other services to validate tokens:

- `VerifyToken(token) → VerifyTokenResponse` - Validate JWT and extract claims
- `GetUser(user_id) → User` - Get user details
- `CheckUserExists(user_id) → bool` - Check if user exists
- `CheckPermission(user_id, permission) → bool` - Check user permission

## Metrics (Prometheus)

The service exports the following metrics:

```
# HELP register_requests_total Total number of Register RPC requests
# TYPE register_requests_total counter
register_requests_total 1234

# HELP login_requests_total Total number of Login RPC requests
# TYPE login_requests_total counter
login_requests_total 5678

# HELP login_failures_total Total failed login attempts (wrong password or user not found)
# TYPE login_failures_total counter
login_failures_total 892

# HELP account_lockouts_total Total account lockouts (5+ failed attempts)
# TYPE account_lockouts_total counter
account_lockouts_total 45
```

**Metrics Endpoint:** `http://localhost:9090/metrics`

## Security

### Password Hashing

Passwords are hashed using **Argon2id** (memory-hard, resistant to GPU attacks):
- Memory: 19 MB
- Time iterations: 2
- Parallelism: 1 thread

### JWT Key Rotation

RSA keys should be rotated regularly for security:

1. Generate new RSA 2048-bit key pair
2. Update `JWT_PRIVATE_KEY_PEM` and `JWT_PUBLIC_KEY_PEM` environment variables
3. Restart service (existing tokens remain valid until expiration)
4. Archive old public key for backward compatibility with long-lived refresh tokens

**Recommendation:** Rotate keys quarterly or after security incident.

### Failed Login Attempts

Account lockout mechanism prevents brute-force attacks:

1. User fails to login (wrong password)
2. Failed attempt counter increments
3. After 5 failed attempts, account is locked for 15 minutes
4. Locked users receive: `Status::PermissionDenied` with lock expiry timestamp
5. Lock automatically expires after 15 minutes
6. Successful login resets counter to 0

## Database Schema

### Users Table

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(32) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT true,
    failed_login_attempts INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
```

### Session Management

- **Stateless**: No session table needed (tokens are self-contained)
- **Token Validation**: Public key verification only (no database lookup)
- **Performance**: Sub-millisecond validation latency

## Performance

Service targets are met with significant margin:

| Operation | Target | Actual P95 | Status |
|-----------|--------|------------|--------|
| Register  | < 200ms | ~15ms | ✅ |
| Login | < 200ms | ~10ms | ✅ |
| Token Validation | < 50ms | ~0.04ms | ✅ |
| Full Auth Cycle | < 200ms | ~1.86ms | ✅ |

## Testing

### Run All Tests

```bash
cargo test -p auth-service
```

### Run Integration Tests

```bash
cargo test -p auth-service --test auth_register_login_test -- --nocapture
```

### Run Performance Tests

```bash
cargo test -p auth-service --test performance_jwt_test -- --nocapture
```

Sample output:
```
=== JWT Token Generation Latency (μs) ===
P50:  869 μs (0.87 ms)
P95:  995 μs (0.99 ms)
P99:  1807 μs (1.81 ms)
```

## Troubleshooting

### "JWT keys not initialized" Error

Ensure `initialize_jwt_keys()` is called during service startup with valid PEM keys:

```rust
#[tokio::main]
async fn main() {
    let private_key = std::env::var("JWT_PRIVATE_KEY_PEM")
        .expect("JWT_PRIVATE_KEY_PEM not set");
    let public_key = std::env::var("JWT_PUBLIC_KEY_PEM")
        .expect("JWT_PUBLIC_KEY_PEM not set");

    jwt::initialize_jwt_keys(&private_key, &public_key)
        .expect("Failed to initialize JWT keys");
}
```

### "Invalid email format" or "Weak password" Errors

These validation errors indicate:
- Email doesn't contain `@` character
- Password zxcvbn score is < 3 (too weak)
- Username is < 3 or > 32 characters

Check validation requirements in the request.

### Account Locked

If you see `Status::PermissionDenied` with message `account_locked_until_<timestamp>`:
1. Wait until the timestamp expires (default 15 minutes)
2. Or contact administrator to manually unlock the account

## Development

### Build

```bash
cargo build
```

### Format Code

```bash
cargo fmt
```

### Lint

```bash
cargo clippy
```

### Watch for Changes

```bash
cargo watch -x "test -p auth-service"
```

## Deployment

### Docker

```dockerfile
FROM rust:latest as builder
WORKDIR /app
COPY . .
RUN cargo build --release -p auth-service

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y libssl3 ca-certificates
COPY --from=builder /app/target/release/auth-service /usr/local/bin/
EXPOSE 50051
CMD ["auth-service"]
```

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
    spec:
      containers:
      - name: auth-service
        image: nova/auth-service:latest
        ports:
        - containerPort: 50051
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: database
              key: url
        - name: JWT_PRIVATE_KEY_PEM
          valueFrom:
            secretKeyRef:
              name: jwt-keys
              key: private
```

## License

Copyright © 2024 Nova Platform. All rights reserved.

## Support

For issues or questions:
1. Check the [troubleshooting section](#troubleshooting)
2. Review [specification](../../specs/009-p0-auth-register-login/)
3. Open an issue in the repository

