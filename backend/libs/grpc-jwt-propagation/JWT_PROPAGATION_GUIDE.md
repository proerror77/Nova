# JWT Propagation Integration Guide

This guide walks through integrating JWT credential propagation across Nova's microservices architecture.

## System Architecture

```
┌─────────────────┐
│   HTTP Client   │
│   (with JWT)    │
└────────┬────────┘
         │ HTTP + Authorization: Bearer {jwt}
         ▼
┌─────────────────────────┐
│   GraphQL Gateway       │
│   - JwtMiddleware       │ ◄── Validates JWT (actix-middleware)
│   - Extracts claims     │
└────────┬────────────────┘
         │ gRPC + metadata[authorization] = Bearer {jwt}
         │ (JwtClientInterceptor)
         ▼
┌─────────────────────────┐
│   Backend Service       │
│   - JwtServerInterceptor│ ◄── Validates JWT again (zero-trust)
│   - Stores claims       │
│   - Authorization       │
└─────────────────────────┘
```

## Key Principles

### 1. Zero-Trust Architecture

Every service validates JWT independently:
- GraphQL Gateway validates incoming HTTP request
- Each backend service validates incoming gRPC request
- No implicit trust between services

### 2. Token Propagation (Not Claims)

- Raw JWT token passed through gRPC metadata
- Each service validates and extracts claims independently
- Prevents tampering between service hops

### 3. Fail-Closed Security

- Missing token = unauthenticated
- Invalid token = unauthenticated
- Expired token = unauthenticated
- Missing permission = permission denied

## Step-by-Step Integration

### Phase 1: Backend Service Setup

#### 1.1 Add Dependency

Add to `backend/{service}/Cargo.toml`:

```toml
[dependencies]
grpc-jwt-propagation = { path = "../libs/grpc-jwt-propagation" }
crypto-core = { path = "../libs/crypto-core" }
```

#### 1.2 Initialize JWT Keys

In `main.rs`, before starting gRPC server:

```rust
use anyhow::Result;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Load JWT public key
    let public_key = crypto_core::jwt::load_validation_key()
        .expect("Failed to load JWT public key");

    // Initialize JWT validation
    crypto_core::jwt::initialize_jwt_validation_only(&public_key)
        .expect("Failed to initialize JWT validation");

    tracing::info!("JWT validation initialized");

    // Start gRPC server...
    start_grpc_server().await
}
```

#### 1.3 Attach Server Interceptor

Wrap your gRPC service with `JwtServerInterceptor`:

```rust
use grpc_jwt_propagation::JwtServerInterceptor;
use tonic::transport::Server;

async fn start_grpc_server() -> Result<()> {
    let addr = "[::1]:50051".parse()?;

    let service = MyServiceServer::with_interceptor(
        MyService::new(),
        JwtServerInterceptor,  // ◄── Add this
    );

    Server::builder()
        .add_service(service)
        .serve(addr)
        .await?;

    Ok(())
}
```

#### 1.4 Update Service Handlers

Add authorization logic to handlers:

```rust
use grpc_jwt_propagation::JwtClaimsExt;
use tonic::{Request, Response, Status};

#[tonic::async_trait]
impl my_service_server::MyService for MyService {
    async fn update_user(
        &self,
        request: Request<UpdateUserRequest>,
    ) -> Result<Response<UpdateUserResponse>, Status> {
        // Extract JWT claims
        let claims = request.jwt_claims()?;

        // Authorization check
        let user_id = Uuid::parse_str(&request.get_ref().user_id)
            .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

        if !claims.is_owner(&user_id) {
            return Err(Status::permission_denied(
                "You can only update your own profile"
            ));
        }

        // Proceed with update...
        Ok(Response::new(UpdateUserResponse {}))
    }
}
```

### Phase 2: GraphQL Gateway Integration

#### 2.1 Extract JWT from Context

The `JwtMiddleware` (from `actix-middleware`) already validates JWT and stores claims in request extensions. We need to extract the raw token for propagation:

```rust
use actix_web::HttpMessage;
use async_graphql::Context;

async fn graphql_resolver(ctx: &Context<'_>) -> Result<User> {
    // Extract JWT token from GraphQL context
    // The token is injected by JwtMiddleware
    let jwt_token = ctx.data::<String>()
        .map_err(|_| "Authentication required")?;

    // Create gRPC client with JWT interceptor
    let interceptor = JwtClientInterceptor::new(jwt_token.clone());

    // Call backend service...
}
```

**Note**: Currently `JwtMiddleware` stores claims but not the raw token. We need to update it:

#### 2.2 Update JwtMiddleware (TODO)

Modify `backend/libs/actix-middleware/src/jwt.rs` to store raw token:

```rust
impl<S, B> Service<ServiceRequest> for JwtMiddleware<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
{
    fn call(&self, req: ServiceRequest) -> Self::Future {
        // ... existing validation code ...

        // Store raw token in extensions (NEW)
        if let Some(auth_header) = req.headers().get("authorization") {
            if let Ok(auth_str) = auth_header.to_str() {
                if let Some(token) = auth_str.strip_prefix("Bearer ") {
                    req.extensions_mut().insert(token.to_string());
                }
            }
        }

        // ... rest of middleware ...
    }
}
```

#### 2.3 Create gRPC Client Helper

Create a helper to construct gRPC clients with JWT:

```rust
use grpc_jwt_propagation::JwtClientInterceptor;
use tonic::transport::Channel;

pub struct AuthenticatedGrpcClient;

impl AuthenticatedGrpcClient {
    pub async fn user_service(
        jwt_token: String,
    ) -> Result<UserServiceClient<impl tower::Service<
        http::Request<tonic::body::BoxBody>,
        Response = http::Response<hyper::Body>,
        Error = Box<dyn std::error::Error + Send + Sync>,
    >>, Box<dyn std::error::Error>> {
        let channel = Channel::from_static("http://[::1]:50051")
            .connect()
            .await?;

        let interceptor = JwtClientInterceptor::new(jwt_token);

        Ok(UserServiceClient::with_interceptor(channel, interceptor))
    }
}
```

#### 2.4 Use in Resolvers

```rust
use async_graphql::{Context, Object, Result};

#[Object]
impl QueryRoot {
    async fn user(&self, ctx: &Context<'_>, id: String) -> Result<User> {
        // Extract JWT
        let jwt_token = ctx.data::<String>()?;

        // Create authenticated client
        let mut client = AuthenticatedGrpcClient::user_service(jwt_token.clone()).await?;

        // Call backend
        let response = client.get_user(Request::new(GetUserRequest {
            user_id: id,
        })).await?;

        Ok(response.into_inner().into())
    }
}
```

### Phase 3: Service-to-Service Calls

When one backend service needs to call another:

```rust
use grpc_jwt_propagation::{JwtClientInterceptor, JwtClaimsExt};

#[tonic::async_trait]
impl content_service_server::ContentService for ContentService {
    async fn create_post(
        &self,
        request: Request<CreatePostRequest>,
    ) -> Result<Response<CreatePostResponse>, Status> {
        // Extract claims from incoming request
        let claims = request.jwt_claims()?;

        // Forward JWT to another service
        let jwt_token = self.extract_jwt_from_request(&request)?;
        let interceptor = JwtClientInterceptor::new(jwt_token);

        let channel = Channel::from_static("http://[::1]:50052")
            .connect()
            .await
            .map_err(|e| Status::internal(format!("Failed to connect: {}", e)))?;

        let mut media_client = MediaServiceClient::with_interceptor(
            channel,
            interceptor,
        );

        // Call media service with same user context
        let media_response = media_client.upload_media(Request::new(
            UploadMediaRequest {
                // ...
            }
        )).await?;

        Ok(Response::new(CreatePostResponse {}))
    }
}
```

**Helper to extract raw JWT from request**:

```rust
impl ContentService {
    fn extract_jwt_from_request<T>(
        &self,
        request: &Request<T>,
    ) -> Result<String, Status> {
        let auth_header = request.metadata()
            .get("authorization")
            .ok_or_else(|| Status::internal("Missing authorization in forwarding"))?;

        let auth_str = auth_header.to_str()
            .map_err(|_| Status::internal("Invalid authorization header"))?;

        let token = auth_str.strip_prefix("Bearer ")
            .ok_or_else(|| Status::internal("Invalid authorization format"))?;

        Ok(token.to_string())
    }
}
```

## Environment Configuration

### Development (.env)

```bash
# JWT Keys (from crypto-core test keys - DO NOT use in production)
JWT_PUBLIC_KEY_FILE=./backend/libs/crypto-core/keys/jwt_public.pem
JWT_PRIVATE_KEY_FILE=./backend/libs/crypto-core/keys/jwt_private.pem
```

### Production (Kubernetes Secrets)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: jwt-keys
type: Opaque
stringData:
  public_key.pem: |
    -----BEGIN PUBLIC KEY-----
    ... (your production public key)
    -----END PUBLIC KEY-----
  private_key.pem: |
    -----BEGIN PRIVATE KEY-----
    ... (your production private key)
    -----END PRIVATE KEY-----
```

Mount in deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: user-service
        env:
        - name: JWT_PUBLIC_KEY_FILE
          value: /secrets/public_key.pem
        volumeMounts:
        - name: jwt-keys
          mountPath: /secrets
          readOnly: true
      volumes:
      - name: jwt-keys
        secret:
          secretName: jwt-keys
```

## Troubleshooting

### "No JWT claims found" Error

**Symptom**: `Status::unauthenticated("No JWT claims found. Ensure JwtServerInterceptor is attached.")`

**Cause**: `JwtServerInterceptor` not attached to service

**Fix**: Ensure you're using `with_interceptor`:
```rust
let service = MyServiceServer::with_interceptor(
    MyService::new(),
    JwtServerInterceptor,  // ◄── Don't forget this
);
```

### "Missing authorization header" Error

**Symptom**: `Status::unauthenticated("Missing authorization header")`

**Cause**: JWT not propagated from client

**Fix**: Ensure GraphQL resolver uses `JwtClientInterceptor`:
```rust
let interceptor = JwtClientInterceptor::new(jwt_token);
let client = UserServiceClient::with_interceptor(channel, interceptor);
```

### "JWT validation failed" Error

**Symptom**: `Status::unauthenticated("JWT validation failed: ...")`

**Possible Causes**:
1. Token signature invalid (wrong key)
2. Token expired
3. Token format malformed

**Debug**:
```rust
// Enable debug logging
RUST_LOG=grpc_jwt_propagation=debug cargo run

// Check JWT expiration
let token_data = crypto_core::jwt::validate_token(token)?;
println!("Expires at: {}", token_data.claims.exp);
```

### Permission Denied Errors

**Symptom**: `Status::permission_denied("You can only delete your own posts")`

**Cause**: Authorization logic correctly rejecting request

**Debug**:
```rust
let claims = request.jwt_claims()?;
tracing::debug!(
    user_id = %claims.user_id,
    resource_owner = %post.author_id,
    "Authorization check"
);
```

## Testing Strategy

### 1. Unit Tests (Per Service)

Test authorization logic in isolation:

```rust
#[tokio::test]
async fn test_user_can_update_own_profile() {
    let user_id = Uuid::new_v4();
    let claims = JwtClaims {
        user_id,
        // ... other fields
    };

    let mut request = Request::new(UpdateUserRequest {
        user_id: user_id.to_string(),
    });
    request.extensions_mut().insert(claims);

    let service = MyService::new();
    let result = service.update_user(request).await;

    assert!(result.is_ok());
}
```

### 2. Integration Tests (With Interceptors)

Test full JWT flow:

```rust
#[tokio::test]
async fn test_end_to_end_authenticated_request() {
    // Initialize JWT keys
    crypto_core::jwt::initialize_jwt_keys(TEST_PRIVATE_KEY, TEST_PUBLIC_KEY)?;

    // Generate token
    let user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id, "test@example.com", "testuser"
    )?;

    // Client side
    let mut client_interceptor = JwtClientInterceptor::new(token);
    let request = client_interceptor.call(Request::new(()))?;

    // Server side
    let mut server_interceptor = JwtServerInterceptor;
    let request = server_interceptor.call(request)?;

    // Verify claims accessible
    let claims = request.jwt_claims()?;
    assert_eq!(claims.user_id, user_id);
}
```

### 3. End-to-End Tests

Test GraphQL → gRPC flow:

```bash
# Start all services
docker-compose up -d

# Generate JWT
TOKEN=$(curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password"}' \
  | jq -r '.access_token')

# Make GraphQL request
curl http://localhost:8080/graphql \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ user(id: \"...\") { id email } }"}'
```

## Migration Checklist

- [ ] Update `Cargo.toml` with `grpc-jwt-propagation` dependency
- [ ] Initialize JWT keys in `main.rs`
- [ ] Attach `JwtServerInterceptor` to gRPC service
- [ ] Update handlers to use `request.jwt_claims()`
- [ ] Add authorization checks (ownership, permissions)
- [ ] Update GraphQL gateway to use `JwtClientInterceptor`
- [ ] Update actix `JwtMiddleware` to store raw token
- [ ] Write unit tests for authorization logic
- [ ] Write integration tests for JWT flow
- [ ] Update deployment configs with JWT key secrets
- [ ] Test in staging environment
- [ ] Monitor authentication errors in production

## Performance Considerations

- **JWT Validation Overhead**: ~50-100μs per request (RSA signature verification)
- **Caching**: Not implemented (tokens are short-lived, caching adds complexity)
- **Connection Pooling**: Use tonic's built-in connection pooling
- **Metadata Overhead**: ~200 bytes per request (Bearer token in metadata)

## Security Best Practices

1. **Token Lifetime**: Keep access tokens short (1 hour default)
2. **Refresh Tokens**: Reject refresh tokens in API endpoints
3. **Key Rotation**: Plan for periodic JWT key rotation
4. **Audit Logging**: Log `user_id` (not raw tokens) for audit trails
5. **Error Messages**: Don't leak token details in error messages
6. **TLS Required**: Always use TLS for gRPC in production
7. **JTI Validation**: Consider implementing JTI blacklist for revocation

## Next Steps

1. Implement token refresh flow
2. Add role-based access control (RBAC)
3. Implement permission system with granular scopes
4. Add JWT revocation/blacklist support
5. Implement token rotation mechanism
6. Add metrics for authentication failures
