# grpc-jwt-propagation - Quick Reference Card

## One-Page Cheat Sheet

### Setup (One Time)

```rust
// main.rs - Initialize keys before starting server
let public_key = crypto_core::jwt::load_validation_key()?;
crypto_core::jwt::initialize_jwt_validation_only(&public_key)?;
```

### Server Side (Backend Service)

```rust
// 1. Add interceptor to service
let service = MyServiceServer::with_interceptor(
    MyService::new(),
    JwtServerInterceptor,  // ◄── Add this
);

// 2. Use in handlers
use grpc_jwt_propagation::JwtClaimsExt;

async fn handler(request: Request<MyReq>) -> Result<Response<MyRes>, Status> {
    let claims = request.jwt_claims()?;  // ◄── Extract claims

    // Check ownership
    if !claims.is_owner(&resource_owner_id) {
        return Err(Status::permission_denied("Access denied"));
    }

    // Proceed...
}
```

### Client Side (GraphQL Gateway)

```rust
use grpc_jwt_propagation::JwtClientInterceptor;

async fn resolver(ctx: &Context<'_>) -> Result<User> {
    let jwt = ctx.data::<String>()?;  // From JwtMiddleware

    let interceptor = JwtClientInterceptor::new(jwt.clone());
    let channel = Channel::from_static("http://[::1]:50051").connect().await?;
    let mut client = UserServiceClient::with_interceptor(channel, interceptor);

    // All requests auto-include JWT
    let resp = client.get_user(Request::new(GetUserRequest { ... })).await?;
    Ok(resp.into_inner())
}
```

### Common Patterns

#### Pattern 1: Owner-Only Access
```rust
request.require_ownership(&resource_owner_id)?;
```

#### Pattern 2: Access Token Only
```rust
request.require_access_token()?;
```

#### Pattern 3: Custom Logic
```rust
let claims = request.jwt_claims()?;
if !claims.is_owner(&id) && !has_admin_role(&claims.user_id) {
    return Err(Status::permission_denied("No access"));
}
```

### Error Codes

| Error | Code | Meaning |
|-------|------|---------|
| Missing header | `Unauthenticated` | Client didn't send JWT |
| Invalid token | `Unauthenticated` | Token expired/tampered |
| Not owner | `PermissionDenied` | User lacks ownership |
| Refresh token | `PermissionDenied` | Used refresh instead of access |

### Testing

```rust
#[tokio::test]
async fn test_authorization() {
    // Initialize keys
    crypto_core::jwt::initialize_jwt_keys(PRIV_KEY, PUB_KEY)?;

    // Generate token
    let user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id, "test@example.com", "testuser"
    )?;

    // Simulate flow
    let mut client_int = JwtClientInterceptor::new(token);
    let req = client_int.call(Request::new(()))?;

    let mut server_int = JwtServerInterceptor;
    let req = server_int.call(req)?;

    // Verify
    assert_eq!(req.jwt_claims()?.user_id, user_id);
}
```

### Environment Variables

```bash
# Development
JWT_PUBLIC_KEY_FILE=./keys/jwt_public.pem
JWT_PRIVATE_KEY_FILE=./keys/jwt_private.pem  # Only for auth-service

# Production (Kubernetes)
JWT_PUBLIC_KEY_PEM=<base64-encoded-pem>
JWT_PRIVATE_KEY_PEM=<base64-encoded-pem>  # Only for auth-service
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| "No JWT claims found" | Add `with_interceptor(service, JwtServerInterceptor)` |
| "Missing authorization header" | Client not using `JwtClientInterceptor` |
| "JWT validation failed" | Check token expiration or wrong public key |
| Permission denied | Check `is_owner()` logic or resource owner ID |

### Dependencies

```toml
[dependencies]
grpc-jwt-propagation = { path = "../libs/grpc-jwt-propagation" }
crypto-core = { path = "../libs/crypto-core" }
```

### Key Metrics

- **Code**: 1331 lines (5 modules)
- **Tests**: 31 tests (21 unit + 10 integration)
- **Coverage**: 100% public API
- **Performance**: ~50-100μs validation overhead per request

### Security Checklist

- ✅ RS256 only (no HS256)
- ✅ Signature validation
- ✅ Expiration checking
- ✅ JTI required (replay protection)
- ✅ Zero-trust (each service validates)
- ✅ Fail-closed (invalid = unauthenticated)

---

**Need more details?** See:
- [README.md](./README.md) - Full documentation
- [JWT_PROPAGATION_GUIDE.md](./JWT_PROPAGATION_GUIDE.md) - Integration guide
- `cargo doc --open` - API documentation
