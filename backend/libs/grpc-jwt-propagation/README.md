# grpc-jwt-propagation

JWT credential propagation for gRPC microservices. Transparently passes user authentication between services while maintaining zero-trust security boundaries.

## Design Philosophy

> "Good programmers worry about data structures and their relationships." - Linus Torvalds

This library follows Linus-style engineering principles:

- **Zero special cases**: Every request flows through the same validation path
- **Fail-fast**: Invalid tokens rejected immediately with clear errors
- **No magic**: Explicit interceptor attachment, explicit claim extraction
- **Zero-copy where possible**: Token passed by reference, claims extracted once

## Core Components

### JwtClaims

Structured JWT claims with built-in authorization helpers:

```rust
pub struct JwtClaims {
    pub user_id: Uuid,
    pub email: String,
    pub username: String,
    pub token_type: String,  // "access" or "refresh"
    pub iat: i64,
    pub exp: i64,
    pub jti: Option<String>,
}
```

### JwtClientInterceptor

Injects JWT tokens into outgoing gRPC requests via metadata:

```rust
let interceptor = JwtClientInterceptor::new(jwt_token);
let mut client = UserServiceClient::with_interceptor(channel, interceptor);
```

### JwtServerInterceptor

Validates incoming JWT tokens and stores claims in request extensions:

```rust
let service = MyServiceServer::with_interceptor(
    MyService,
    JwtServerInterceptor,
);
```

### JwtClaimsExt

Request extension trait for ergonomic claim access:

```rust
use grpc_jwt_propagation::JwtClaimsExt;

async fn handler(request: Request<MyRequest>) -> Result<Response<MyResponse>, Status> {
    let claims = request.jwt_claims()?;
    println!("User: {}", claims.user_id);
    Ok(Response::new(MyResponse {}))
}
```

## Quick Start

### 1. Initialize JWT Keys

All services must initialize JWT keys at startup:

```rust
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Services that only validate tokens (most backend services)
    let public_key = std::env::var("JWT_PUBLIC_KEY_PEM")?;
    crypto_core::jwt::initialize_jwt_validation_only(&public_key)?;

    // Services that also generate tokens (auth-service, graphql-gateway)
    let private_key = std::env::var("JWT_PRIVATE_KEY_PEM")?;
    let public_key = std::env::var("JWT_PUBLIC_KEY_PEM")?;
    crypto_core::jwt::initialize_jwt_keys(&private_key, &public_key)?;

    // Start your gRPC server...
    Ok(())
}
```

### 2. Client Side (GraphQL Gateway)

Extract JWT from HTTP context and propagate to backend services:

```rust
use grpc_jwt_propagation::JwtClientInterceptor;

async fn graphql_resolver(
    ctx: &Context<'_>,
) -> Result<User> {
    // JWT token injected by JwtMiddleware (actix-middleware)
    let jwt_token = ctx.data::<String>()?;

    // Create interceptor
    let interceptor = JwtClientInterceptor::new(jwt_token.clone());

    // Connect to backend service
    let channel = Channel::from_static("http://[::1]:50051")
        .connect()
        .await?;

    let mut client = UserServiceClient::with_interceptor(
        channel,
        interceptor,
    );

    // All requests automatically include JWT
    let response = client.get_user(Request::new(GetUserRequest {
        user_id: user_id.to_string(),
    })).await?;

    Ok(response.into_inner())
}
```

### 3. Server Side (Backend Service)

Validate JWT and extract claims for authorization:

```rust
use grpc_jwt_propagation::{JwtServerInterceptor, JwtClaimsExt};
use tonic::{Request, Response, Status};

pub struct ContentService {
    // ...
}

#[tonic::async_trait]
impl content_service_server::ContentService for ContentService {
    async fn delete_post(
        &self,
        request: Request<DeletePostRequest>,
    ) -> Result<Response<DeletePostResponse>, Status> {
        // 1. Extract validated JWT claims
        let claims = request.jwt_claims()?;

        // 2. Fetch post from database
        let post = self.get_post_by_id(request.get_ref().post_id).await
            .map_err(|e| Status::not_found(format!("Post not found: {}", e)))?;

        // 3. Authorization check: only author or admin can delete
        if !claims.is_owner(&post.author_id) {
            return Err(Status::permission_denied(
                "You can only delete your own posts"
            ));
        }

        // 4. Execute deletion
        self.delete_post_by_id(post.id).await
            .map_err(|e| Status::internal(format!("Failed to delete post: {}", e)))?;

        Ok(Response::new(DeletePostResponse { success: true }))
    }
}

// Attach interceptor in main()
fn main() {
    let service = ContentServiceServer::with_interceptor(
        ContentService::new(),
        JwtServerInterceptor,
    );

    Server::builder()
        .add_service(service)
        .serve(addr)
        .await?;
}
```

## Authorization Patterns

### 1. Resource Ownership Check

```rust
async fn update_profile(
    request: Request<UpdateProfileRequest>,
) -> Result<Response<UpdateProfileResponse>, Status> {
    let user_id = Uuid::parse_str(&request.get_ref().user_id)
        .map_err(|_| Status::invalid_argument("Invalid user ID"))?;

    // Require ownership
    request.require_ownership(&user_id)?;

    // User is confirmed owner, proceed with update
    Ok(Response::new(UpdateProfileResponse {}))
}
```

### 2. Access Token Validation

```rust
async fn get_user_data(
    request: Request<GetUserDataRequest>,
) -> Result<Response<GetUserDataResponse>, Status> {
    // Reject refresh tokens (only access tokens allowed)
    request.require_access_token()?;

    // Proceed with data access
    Ok(Response::new(GetUserDataResponse {}))
}
```

### 3. Custom Permission Logic

```rust
async fn delete_comment(
    request: Request<DeleteCommentRequest>,
) -> Result<Response<DeleteCommentResponse>, Status> {
    let claims = request.jwt_claims()?;
    let comment = get_comment_by_id(request.get_ref().comment_id).await?;

    // Allow deletion if:
    // - User is comment author
    // - User is post author
    // - User is admin
    if !claims.is_owner(&comment.author_id)
        && !claims.is_owner(&comment.post_author_id)
        && !claims.is_admin() {
        return Err(Status::permission_denied(
            "Insufficient permissions to delete comment"
        ));
    }

    // Proceed with deletion
    Ok(Response::new(DeleteCommentResponse {}))
}
```

## Error Handling

### Client Errors

- `Status::internal("Invalid JWT token format")` - Token contains invalid ASCII (should never happen with valid JWTs)

### Server Errors

- `Status::unauthenticated("Missing authorization header")` - No JWT token provided
- `Status::unauthenticated("Invalid authorization format")` - Header not in "Bearer {token}" format
- `Status::unauthenticated("JWT validation failed: ...")` - Token signature invalid, expired, or malformed
- `Status::internal("Failed to parse JWT claims: ...")` - Token valid but claims structure invalid

### Extension Errors

- `Status::unauthenticated("No JWT claims found. Ensure JwtServerInterceptor is attached.")` - Server interceptor not configured
- `Status::permission_denied("You do not have permission to access this resource")` - User is not resource owner
- `Status::permission_denied("Access token required (refresh tokens not allowed)")` - Refresh token used for API access

## Security Guarantees

- **RS256 only**: No symmetric algorithms, prevents algorithm confusion attacks
- **Signature validation**: All tokens verified using crypto-core (RS256 with SHA-256)
- **Expiration checking**: Expired tokens automatically rejected
- **Replay protection**: JTI (JWT ID) required in all tokens
- **No token leakage**: Tokens not logged (use `user_id` for audit trails)
- **Fail-closed**: Any validation error returns unauthenticated

## Testing

Run unit tests:
```bash
cargo test -p grpc-jwt-propagation --lib
```

Run integration tests:
```bash
cargo test -p grpc-jwt-propagation --test integration
```

All tests:
```bash
cargo test -p grpc-jwt-propagation
```

## Performance Characteristics

- **Client interceptor**: O(1) - Pre-parsed metadata value, zero allocation per request
- **Server interceptor**: O(1) - Single JWT validation, claims stored in extensions
- **Claim extraction**: O(1) - Direct reference from extensions, zero copy

## Dependencies

- `tonic` - gRPC framework
- `crypto-core` - JWT validation (RS256)
- `uuid` - User ID parsing
- `serde` - Claims serialization
- `tracing` - Structured logging

## License

MIT

## Contributing

Follow the existing code style:
- No special cases
- Fail-fast on errors
- Clear error messages
- Comprehensive tests
