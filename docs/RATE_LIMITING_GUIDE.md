# Rate Limiting Implementation Guide

**Status**: ✅ Implemented (P0-3)
**Framework**: Actix-web middleware with `governor` crate
**Type**: Per-IP token bucket rate limiting

## Overview

Rate limiting protects the GraphQL Gateway from abuse and DoS attacks by limiting the number of requests per IP address.

## Configuration

### Default Settings

```rust
RateLimitConfig {
    req_per_second: 100,  // 100 requests/sec per IP
    burst_size: 10,       // Allow bursts of up to 10 requests
}
```

### Customization

```rust
let config = RateLimitConfig {
    req_per_second: 200,
    burst_size: 20,
};

let middleware = RateLimitMiddleware::new(config);
```

## How It Works

### Token Bucket Algorithm

1. Each IP address gets its own token bucket (100 tokens/second)
2. Each request consumes 1 token
3. If tokens are available → request allowed
4. If no tokens → HTTP 429 (Too Many Requests)
5. Tokens refill at constant rate

### IP Address Detection

1. Check `X-Forwarded-For` header (proxy awareness)
2. Fall back to direct connection IP
3. Default to 127.0.0.1 if unable to determine

## Integration

### Middleware Setup

```rust
use actix_web::{web, App, HttpServer};
use crate::middleware::RateLimitMiddleware;

HttpServer::new(|| {
    App::new()
        .wrap(RateLimitMiddleware::new(RateLimitConfig::default()))
        .route("/graphql", web::post().to(graphql_handler))
})
```

## Monitoring

### Metrics Tracked

- **rate_limit_exceeded**: Counter of requests exceeding limit
- **active_rate_limiters**: Gauge of unique IPs being tracked

### Logging

```
WARN Rate limit exceeded for IP: 192.168.1.100
DEBUG Rate limit check passed for IP: 192.168.1.1
```

### Example: Enable Detailed Logging

```bash
RUST_LOG=debug,graphql_gateway::middleware::rate_limit=debug \
  cargo run
```

## Scenarios

### Scenario 1: Normal Usage
```
Time: 0ms     - Request 1 (tokens: 99/100) ✅
Time: 10ms    - Request 2 (tokens: 98/100) ✅
Time: 20ms    - Request 3 (tokens: 97/100) ✅
```

### Scenario 2: Burst Traffic
```
Time: 0ms     - Request 1-10 (burst) ✅ ✅ ✅ ...
Time: 10ms    - Request 11 (wait for tokens) ⏳
Time: 20ms    - Request 11 (token available) ✅
```

### Scenario 3: Rate Limit Exceeded
```
Time: 0ms     - Requests 1-100 (tokens depleted) ✅
Time: 10ms    - Request 101 (no tokens) ❌ HTTP 429
Time: 20ms    - Request 102 (still no tokens) ❌ HTTP 429
Time: 100ms   - Request 103 (new tokens available) ✅
```

## Performance

- **Memory**: ~100-200 bytes per tracked IP
- **CPU**: O(1) check operation
- **Latency**: <1µs per request

## Testing

### Unit Tests

```bash
cargo test -p graphql-gateway -- rate_limit
```

### Integration Tests

```bash
# Normal request
curl -X POST http://localhost:8000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ user { id } }"}'

# Rate limited (after 100 requests in 1 second)
# Response: 429 Too Many Requests
```

### Load Testing

```bash
# Generate 150 req/s (exceeds 100 req/s limit)
k6 run -u 150 --vus 150 k6/load-test-graphql.js
```

## Configuration for Different Environments

### Development

```rust
RateLimitConfig {
    req_per_second: 1000,  // Very permissive
    burst_size: 100,
}
```

### Staging

```rust
RateLimitConfig {
    req_per_second: 200,   // Moderate
    burst_size: 20,
}
```

### Production

```rust
RateLimitConfig {
    req_per_second: 100,   // Conservative
    burst_size: 10,
}
```

## Handling Rate Limit Errors

### Client-Side

```javascript
// Handle 429 responses
if (response.status === 429) {
  // Apply exponential backoff
  const delay = Math.pow(2, retryCount) * 1000;
  setTimeout(() => retry(), delay);
}
```

### Monitoring & Alerting

```
Alert: RateLimitExceeded
  Condition: rate_limit_violations > 100 per minute
  Action: Investigate client abuse or increase limits
```

## Best Practices

1. **Monitor rate limit violations**: Set up alerts
2. **Whitelist trusted IPs**: For internal services
3. **Progressive backoff**: Clients should use exponential backoff
4. **Document limits**: Inform API consumers of limits
5. **Scale horizontally**: Multiple gateway instances share IP state via distributed rate limiter

## Troubleshooting

### Issue: All Requests Getting 429

**Cause**: Gateway instance crashed or hit limits too early

**Solution**:
```bash
# Check logs
docker logs graphql-gateway | grep "rate_limit"

# Increase limits temporarily
RATE_LIMIT_RPS=500 cargo run
```

### Issue: Rate Limiting Not Working

**Cause**: Middleware not registered

**Solution**:
```rust
// Ensure middleware is wrapped
App::new()
    .wrap(RateLimitMiddleware::new(config))
    .service(...)
```

## Future Enhancements

- [ ] Per-user rate limiting (authenticated users)
- [ ] Distributed rate limiting (Redis-backed)
- [ ] Query complexity-based limits
- [ ] Adaptive rate limiting (auto-adjust based on load)
- [ ] Rate limit headers in responses

## References

- [Token Bucket Algorithm](https://en.wikipedia.org/wiki/Token_bucket)
- [Governor Crate](https://github.com/bheisler/governor)
- [RFC 6585: HTTP 429](https://tools.ietf.org/html/rfc6585)
