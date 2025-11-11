# Structured Logging Quick Reference

**Quick start guide for developers implementing structured logging**

---

## Basic Pattern

```rust
pub async fn my_handler(...) -> impl Responder {
    let start = std::time::Instant::now();

    // Entry point
    tracing::debug!(
        user_id = %user.id,
        "Handler started"
    );

    // Success case
    tracing::info!(
        user_id = %user.id,
        elapsed_ms = start.elapsed().as_millis() as u32,
        "Operation successful"
    );

    // Error case
    tracing::error!(
        user_id = %user.id,
        error = %e,
        error_type = "database_error",
        elapsed_ms = start.elapsed().as_millis() as u32,
        "Operation failed"
    );
}
```

---

## Log Levels Cheat Sheet

| Level | Use Case | Example |
|-------|----------|---------|
| `error!` | System errors | `"Database connection failed"` |
| `warn!` | Recoverable errors | `"Invalid input: user ID format"` |
| `info!` | Important events | `"User login successful"` |
| `debug!` | Diagnostic info | `"Cache lookup started"` |

---

## Common Structured Fields

| Field Name | Type | Example | Usage |
|------------|------|---------|-------|
| `user_id` | UUID | `%user.id` | Authenticated user |
| `target_user_id` | UUID | `%target_id` | User being queried |
| `follower_id` | UUID | `%follower.id` | User following |
| `elapsed_ms` | u32 | `start.elapsed().as_millis() as u32` | Operation duration |
| `cache_hit` | bool | `true/false` | Cache hit status |
| `error` | String | `%e` | Error message |
| `error_type` | String | `"database_error"` | Error category |
| `method` | String | `%method` | HTTP method |
| `path` | String | `%path` | Request path |

---

## Field Formatting

| Format | Usage | Example |
|--------|-------|---------|
| `%field` | Display format | `user_id = %user.id` |
| `?field` | Debug format (Option) | `requester_id = ?requester` |
| `field` | Direct value | `cache_hit = true` |

---

## Quick Examples

### 1. HTTP Handler
```rust
tracing::info!(
    user_id = %user.id,
    method = %req.method(),
    path = %req.path(),
    elapsed_ms = start.elapsed().as_millis() as u32,
    "Request completed"
);
```

### 2. Database Operation
```rust
tracing::debug!(
    user_id = %user.id,
    query = "SELECT * FROM users WHERE id = $1",
    "Database query started"
);
```

### 3. Cache Operation
```rust
tracing::info!(
    user_id = %user.id,
    cache_key = %key,
    cache_hit = true,
    "Cache lookup successful"
);
```

### 4. Error Handling
```rust
tracing::error!(
    user_id = %user.id,
    error = %e,
    error_type = "network_timeout",
    elapsed_ms = start.elapsed().as_millis() as u32,
    "External service call failed"
);
```

---

## What NOT to Log

❌ **PII (Personally Identifiable Information)**:
- Email addresses
- Phone numbers
- Passwords
- Credit card numbers
- Social security numbers
- Birth dates

✅ **Use UUIDs instead**:
```rust
// ❌ BAD
tracing::info!(email = %user.email, "User logged in");

// ✅ GOOD
tracing::info!(user_id = %user.id, "User logged in");
```

---

## Testing Locally

```bash
# Run service with debug logs and verify JSON format
cd backend/user-service
RUST_LOG=debug cargo run 2>&1 | jq .

# Check for PII leakage
cargo run 2>&1 | jq '.fields' | grep -E "(email|phone|password)"
```

---

## CloudWatch Query Template

```
fields @timestamp, user_id, error, elapsed_ms
| filter @message like /<your search term>/
| filter elapsed_ms > 100
| sort @timestamp desc
| limit 20
```

---

## Complete Handler Example

```rust
use std::time::Instant;

pub async fn follow_user(
    path: web::Path<String>,
    pool: web::Data<PgPool>,
    user: UserId,
) -> HttpResponse {
    let start = Instant::now();

    // Parse target ID
    let target_id = match Uuid::parse_str(&path.into_inner()) {
        Ok(id) => id,
        Err(_) => {
            tracing::warn!(
                follower_id = %user.0,
                error = "invalid_target_id",
                elapsed_ms = start.elapsed().as_millis() as u32,
                "Follow failed: Invalid target ID"
            );
            return HttpResponse::BadRequest().json(
                serde_json::json!({"error": "invalid user id"})
            );
        }
    };

    // Entry log
    tracing::debug!(
        follower_id = %user.0,
        target_id = %target_id,
        "Follow request started"
    );

    // Database operation
    match sqlx::query("INSERT INTO follows ...")
        .bind(user.0)
        .bind(target_id)
        .execute(pool.get_ref())
        .await
    {
        Ok(_) => {
            tracing::info!(
                follower_id = %user.0,
                target_id = %target_id,
                elapsed_ms = start.elapsed().as_millis() as u32,
                "Follow successful"
            );
            HttpResponse::Ok().json(serde_json::json!({"status": "ok"}))
        }
        Err(e) => {
            tracing::error!(
                follower_id = %user.0,
                target_id = %target_id,
                error = %e,
                error_type = "database_error",
                elapsed_ms = start.elapsed().as_millis() as u32,
                "Follow failed: Database error"
            );
            HttpResponse::InternalServerError().json(
                serde_json::json!({"error": "db_error"})
            )
        }
    }
}
```

---

## References

- Full Guide: `docs/STRUCTURED_LOGGING_GUIDE.md`
- Test Script: `scripts/test_structured_logging.sh`
- Implementation Summary: `docs/STRUCTURED_LOGGING_IMPLEMENTATION_SUMMARY.md`
