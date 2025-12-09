# Rate Limiting Middleware

Distributed rate limiting middleware for Actix Web using Redis.

## Features

- **Redis-backed distributed rate limiting** - Works across multiple service instances
- **Configurable failure modes** - Fail-open (availability) or fail-closed (security)
- **User-Agent fingerprinting** - Optional enhanced client identification
- **Timeout protection** - Fast fail on Redis slowness (100ms default)
- **Preset configurations** - `auth_strict()` and `api_lenient()` for common use cases

## Usage

### Basic Setup

```rust
use actix_middleware::{RateLimitConfig, RateLimitMiddleware};
use actix_web::{web, App};

let redis_manager = /* your Redis ConnectionManager */;

let app = App::new()
    .wrap(RateLimitMiddleware::new(
        RateLimitConfig::default(),
        redis_manager,
    ))
    .route("/api", web::get().to(handler));
```

### Authentication Endpoints (Strict)

For `/login`, `/register`, and other auth endpoints, use `auth_strict()`:

```rust
let auth_rate_limiter = RateLimitMiddleware::new(
    RateLimitConfig::auth_strict(),
    redis_manager.clone(),
);

web::scope("/auth")
    .wrap(auth_rate_limiter)
    .route("/login", web::post().to(login))
    .route("/register", web::post().to(register))
```

**Auth Strict Preset**:
- 5 requests per minute
- Includes User-Agent in rate limit key (prevents IP rotation bypass)
- Fail-closed mode (denies requests if Redis is down)
- Security > Availability

### General API Endpoints (Lenient)

For general API endpoints, use `api_lenient()`:

```rust
let api_rate_limiter = RateLimitMiddleware::new(
    RateLimitConfig::api_lenient(),
    redis_manager.clone(),
);

web::scope("/api")
    .wrap(api_rate_limiter)
    .route("/users", web::get().to(list_users))
```

**API Lenient Preset**:
- 100 requests per minute
- IP-based rate limiting only
- Fail-open mode (allows requests if Redis is down)
- Availability > Security

### Custom Configuration

```rust
use actix_middleware::{RateLimitConfig, FailureMode};

let custom_config = RateLimitConfig {
    max_requests: 10,
    window_seconds: 60,
    redis_timeout_ms: 100,
    include_user_agent: true,
    failure_mode: FailureMode::FailClosed,
};

let middleware = RateLimitMiddleware::new(custom_config, redis_manager);
```

## Configuration Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_requests` | `u32` | 100 | Maximum requests allowed in time window |
| `window_seconds` | `u64` | 900 | Time window in seconds (15 min default) |
| `redis_timeout_ms` | `u64` | 100 | Redis operation timeout in milliseconds |
| `include_user_agent` | `bool` | false | Include User-Agent in rate limit key |
| `failure_mode` | `FailureMode` | `FailOpen` | Behavior when Redis is unavailable |

### Failure Modes

- **`FailureMode::FailOpen`** (default): Allow requests when Redis is unavailable
  - Use for: General API endpoints
  - Prioritizes: Service availability
  - Risk: Rate limiting is bypassed if Redis goes down

- **`FailureMode::FailClosed`**: Deny requests when Redis is unavailable
  - Use for: Authentication endpoints, sensitive operations
  - Prioritizes: Security
  - Risk: Service unavailable if Redis goes down

## Rate Limit Keys

The middleware generates different Redis keys based on context:

1. **Authenticated users**: `rate_limit:user:{user_id}`
   - Most accurate, no IP-based bypass

2. **Unauthenticated + User-Agent**: `rate_limit:ip_ua:{ip}:{user_agent}`
   - Better protection against distributed attacks
   - Recommended for `/login`, `/register`

3. **Unauthenticated (IP only)**: `rate_limit:ip:{ip}`
   - Simple IP-based limiting
   - Can be bypassed via IP rotation

## Security Considerations

### Authentication Endpoints

**CRITICAL**: Always use `FailureMode::FailClosed` for authentication endpoints.

```rust
// ✅ GOOD: Fail-closed for auth endpoints
let auth_config = RateLimitConfig::auth_strict(); // Uses FailClosed
web::scope("/auth")
    .wrap(RateLimitMiddleware::new(auth_config, redis))
    .route("/login", web::post().to(login))

// ❌ BAD: Fail-open for auth endpoints
let bad_config = RateLimitConfig::api_lenient(); // Uses FailOpen!
web::scope("/auth")
    .wrap(RateLimitMiddleware::new(bad_config, redis)) // VULNERABLE
```

**Why?** If Redis goes down with fail-open:
- Attackers can brute force credentials indefinitely
- No rate limiting protection
- **Security vulnerability**

### User-Agent Fingerprinting

Enable `include_user_agent` for unauthenticated endpoints:

```rust
RateLimitConfig {
    include_user_agent: true,  // ✅ Prevents IP rotation bypass
    // ...
}
```

**Without User-Agent**: Attacker can rotate IPs to bypass rate limits
**With User-Agent**: Attacker must also rotate User-Agent strings

## Response Format

When rate limit is exceeded, the middleware returns:

**HTTP 429 Too Many Requests**
```json
{
  "error": "Rate limit exceeded",
  "max_requests": 5,
  "window_seconds": 60
}
```

When Redis is unavailable (fail-closed):

**HTTP 503 Service Unavailable**
```
Rate limiting service temporarily unavailable
```

## Metrics & Monitoring

The middleware logs warnings when:
- Rate limit is exceeded (with key and path)
- Redis errors occur
- Redis timeouts occur

```
WARN Rate limit exceeded for key=rate_limit:ip_ua:1.2.3.4:Mozilla (/api/v1/auth/login)
WARN Rate limit Redis error (fail-open, allowing request): connection refused
WARN Rate limit Redis timeout (100ms, fail-open, allowing request)
```

## Testing

Unit tests are included in `rate_limit.rs`:

```bash
cd backend/libs/actix-middleware
cargo test rate_limit
```

Integration tests require Redis:

```bash
docker run -d -p 6379:6379 redis:7-alpine
cargo test --test rate_limit_integration
```

## Environment Variables

```bash
# Redis command timeout (affects rate limiting)
REDIS_COMMAND_TIMEOUT_MS=3000  # Default: 3000ms
```

## Examples

### Example 1: E-commerce API

```rust
// Public endpoints (lenient)
web::scope("/api")
    .wrap(RateLimitMiddleware::new(
        RateLimitConfig::api_lenient(),
        redis.clone(),
    ))
    .route("/products", web::get().to(list_products))

// Auth endpoints (strict)
web::scope("/auth")
    .wrap(RateLimitMiddleware::new(
        RateLimitConfig::auth_strict(),
        redis.clone(),
    ))
    .route("/login", web::post().to(login))

// Checkout (custom: 10 req/min)
web::scope("/checkout")
    .wrap(RateLimitMiddleware::new(
        RateLimitConfig {
            max_requests: 10,
            window_seconds: 60,
            include_user_agent: false,
            failure_mode: FailureMode::FailClosed,
            ..Default::default()
        },
        redis.clone(),
    ))
    .route("/submit", web::post().to(submit_order))
```

### Example 2: Different Limits per User Tier

```rust
// Note: Current implementation uses same limit for all users
// For per-user limits, extend the middleware or use separate scopes
```

## Performance

- **Redis overhead**: ~1-2ms per request (INCR + EXPIRE)
- **Timeout protection**: 100ms default (prevents Redis slowness from blocking requests)
- **Connection pooling**: Uses Redis ConnectionManager for efficient connection reuse
- **Async operations**: Non-blocking Redis calls

## Limitations

1. **Fixed time windows**: Uses fixed windows, not sliding windows
   - Example: 5 req/min allows 10 requests if split across minute boundary
   - For stricter limits, use shorter windows

2. **Single Redis instance**: No multi-region support yet
   - Requires Redis replication for HA

3. **No per-user custom limits**: All users share same config
   - Workaround: Create different scopes with different configs

## Migration from No Rate Limiting

1. Add Redis connection to your service
2. Apply `RateLimitMiddleware::new(RateLimitConfig::api_lenient(), redis)` globally
3. Apply `RateLimitMiddleware::new(RateLimitConfig::auth_strict(), redis)` to `/auth` scope
4. Monitor logs for rate limit exceeded events
5. Adjust `max_requests` if needed

## Troubleshooting

### "Rate limiting service temporarily unavailable"

**Cause**: Redis is down or unreachable, and `failure_mode = FailClosed`

**Fix**:
1. Check Redis connectivity: `redis-cli ping`
2. Check Redis logs for errors
3. If Redis is intentionally down, temporarily use `FailOpen` (NOT for auth endpoints!)

### All requests blocked immediately

**Cause**: `max_requests` too low or Redis key not expiring

**Fix**:
1. Check Redis TTL: `redis-cli TTL rate_limit:ip:1.2.3.4`
2. If TTL is stuck at -1, manually delete: `redis-cli DEL rate_limit:ip:1.2.3.4`
3. Increase `max_requests` if legitimate traffic

### Rate limiting bypassed

**Cause**: Redis is down and `failure_mode = FailOpen`

**Fix**:
1. For auth endpoints: Use `FailClosed` (accept downtime over security breach)
2. For general API: Monitor Redis availability, set up alerts

## See Also

- [Redis Connection Pool](../redis-utils/README.md)
- [JWT Authentication Middleware](./jwt_auth.rs)
- [Circuit Breaker Pattern](./circuit_breaker.rs)
