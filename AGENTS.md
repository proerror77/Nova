# Code Review Guidelines for Codex

**Version**: 1.0
**Last Updated**: 2025-11-06
**Audience**: AI Code Agents (Codex, etc.)

---

## 📋 Review Standards

### Security & Compliance

#### 1. Credential & Secret Management
- ❌ **DENY**: Passwords, API keys, tokens in code, comments, or logs
- ❌ **DENY**: Hardcoded connection strings or database URLs
- ✅ **REQUIRE**: All secrets passed via environment variables or vaults (Kubernetes Secrets, AWS Secrets Manager)
- ✅ **REQUIRE**: Log output sanitized (no PII: emails, SSNs, phone numbers, credit cards)

**Audit Point**:
```rust
// ❌ BAD
let db_url = "postgres://user:password@localhost:5432/nova";
println!("User email: {}", user.email);  // ❌ PII in logs

// ✅ GOOD
let db_url = env::var("DATABASE_URL")?;
tracing::info!(user_id=%user.id, "User authenticated");  // No PII
```

---

#### 2. Authentication & Authorization
- ❌ **DENY**: Any HTTP endpoint without auth middleware
- ✅ **REQUIRE**: All HTTP endpoints validated with JWT or OAuth2
- ✅ **REQUIRE**: gRPC services use interceptors for auth (e.g., `tonic` middleware)
- ✅ **REQUIRE**: Service-to-service calls authenticated (mTLS or signed tokens)

**Audit Point**:
```rust
// ❌ BAD
pub async fn get_user(req: Request<UserId>) -> Result<UserResponse> {
    // No auth check!
}

// ✅ GOOD
pub async fn get_user(req: Request<UserId>) -> Result<UserResponse> {
    let claims = extract_claims(&req)?;  // Validate JWT
    assert_permission(&claims, "user:read")?;
    Ok(get_from_db(req.into_inner()).await?)
}
```

---

### Database & Schema

#### 3. Zero Downtime Migrations (Expand-Contract Pattern)
- ❌ **DENY**: Direct column drops, renames, or type changes
- ❌ **DENY**: Dropping constraints without alternate enforcement
- ✅ **REQUIRE**: Add new column → Backfill → Old code adapts → Drop old column (3 releases min)
- ✅ **REQUIRE**: All migrations versioned (YYYYMMDD_description.sql) with no gaps
- ✅ **REQUIRE**: Rollback plan documented in PR description

**Audit Point**:
```sql
-- ❌ BAD (breaks running apps)
ALTER TABLE users DROP COLUMN phone;

-- ✅ GOOD (Step 1: Add)
ALTER TABLE users ADD COLUMN phone_v2 VARCHAR(20);

-- ✅ GOOD (Step 2: Backfill - in app code or separate migration)
UPDATE users SET phone_v2 = phone WHERE phone IS NOT NULL;

-- ✅ GOOD (Step 3: App code reads from phone_v2, writes to both)
-- (After 1-2 releases)

-- ✅ GOOD (Step 4: Drop old column - 3+ releases later)
ALTER TABLE users DROP COLUMN phone;
```

---

#### 4. Foreign Key Constraints
- ✅ **REQUIRE**: All FKs explicitly defined with strategy
- ✅ **PREFER**: `ON DELETE RESTRICT` (default) for microservices
- ✅ **PREFER**: Use Outbox pattern + event-driven deletion for CASCADE behavior
- ❌ **AVOID**: `ON DELETE CASCADE` unless single-responsibility guarantee

**Audit Point**:
```sql
-- ✅ GOOD
ALTER TABLE messages
  ADD CONSTRAINT fk_user_id
  FOREIGN KEY (user_id) REFERENCES users(id)
  ON DELETE RESTRICT;  -- App handles via Outbox + Event

-- For user deletion, emit event:
-- UserDeleted event → Notification service subscribes → Soft-delete messages
```

---

### Feature Flags & Runtime Configuration

#### 5. Feature Flags (Runtime, NOT Compile-Time)
- ❌ **DENY**: Compile-time feature gates controlling production behavior
- ✅ **REQUIRE**: All experimental features gated by runtime flags
- ✅ **REQUIRE**: Flags queryable from admin API or config service
- ✅ **REQUIRE**: Gradual rollout: 1% → 10% → 50% → 100%

**Audit Point**:
```rust
// ❌ BAD (compile-time)
#[cfg(feature = "new_search_v2")]
pub fn search(...) { v2_impl(...) }

// ✅ GOOD (runtime)
pub fn search(...) {
    if feature_flag_enabled("search.v2") {
        v2_impl(...)
    } else {
        v1_impl(...)
    }
}
```

---

### Rust Specifics

#### 6. Error Handling & Unsafe Code
- ✅ **REQUIRE**: `cargo clippy -- -D warnings` passes (no warnings)
- ❌ **DENY**: `.unwrap()` in I/O, network, or database code paths
- ❌ **DENY**: `unsafe` without explicit comment justifying and // SAFETY doc
- ✅ **REQUIRE**: Custom error types with `thiserror` or `anyhow`

**Audit Point**:
```rust
// ❌ BAD
let conn = db_pool.get_connection().unwrap();  // Panics!
let response = http_client.get(url).unwrap();

// ✅ GOOD
let conn = db_pool.get_connection()
    .context("Failed to get DB connection")?;
let response = http_client.get(url)
    .await
    .map_err(|e| anyhow!("HTTP request failed: {}", e))?;
```

---

#### 7. Connection Pools & Timeouts
- ✅ **REQUIRE**: All connection pools (DB, Redis, HTTP) configured with:
  - Connection timeout (default: 5s)
  - Request timeout (default: 30s)
  - Pool size limits
- ✅ **REQUIRE**: Explicit timeout in `tokio::time::timeout` for critical paths

**Audit Point**:
```rust
// ✅ GOOD
let pool = PgPoolOptions::new()
    .max_connections(50)
    .connect_timeout(Duration::from_secs(5))
    .idle_timeout(Duration::from_secs(300))
    .connect(&database_url)
    .await?;

// ✅ GOOD
tokio::time::timeout(Duration::from_secs(30),
    expensive_operation()
).await??;
```

---

#### 8. Async/Await Patterns
- ✅ **REQUIRE**: All blocking operations spawn on `spawn_blocking`
- ✅ **REQUIRE**: Async context preserved across `.await` boundaries
- ❌ **DENY**: Blocking sleeps in async code (use `tokio::time::sleep`)
- ✅ **REQUIRE**: Distributed trace context (correlation ID) propagated through async chain

**Audit Point**:
```rust
// ❌ BAD
pub async fn heavy_compute() {
    std::thread::sleep(Duration::from_secs(1));  // Blocks runtime!
}

// ✅ GOOD
pub async fn heavy_compute() {
    tokio::time::sleep(Duration::from_secs(1)).await;

    // Spawn blocking operation
    tokio::task::spawn_blocking(|| cpu_intensive_work()).await?;
}

// ✅ GOOD - Trace context propagated
#[tracing::instrument(skip(req))]
pub async fn handle_request(req: Request) {
    let correlation_id = req.correlation_id().clone();
    // Pass to all spawned tasks
}
```

---

### gRPC Specific

#### 9. gRPC Service Design
- ✅ **REQUIRE**: All services include health check (tonic-health)
- ✅ **REQUIRE**: Proper error codes (NOT all `Status::internal`)
- ✅ **REQUIRE**: Request/response logged (excluding sensitive fields)
- ✅ **REQUIRE**: Interceptors for:
  - Authentication (JWT validation)
  - Tracing (OpenTelemetry)
  - Metrics (request count, latency)

**Audit Point**:
```rust
// ✅ GOOD gRPC server setup
let svc = UserServiceServer::new(UserService::new())
    .max_decoding_message_size(10 * 1024 * 1024)
    .max_encoding_message_size(10 * 1024 * 1024);

let server = Server::builder()
    .add_service(HealthServer::new(health_service))
    .add_service(svc)
    .layer(AuthInterceptor)
    .layer(MetricsInterceptor)
    .layer(TracingInterceptor)
    .serve(addr)
    .await?;
```

---

#### 10. Message Size & Streaming
- ✅ **REQUIRE**: gRPC max message size configured (default 4MB, adjust if needed)
- ✅ **REQUIRE**: Server-streaming endpoints for large result sets (>1000 items)
- ✅ **REQUIRE**: Pagination or cursor-based if streaming not applicable

---

### Testing & Code Quality

#### 11. Test Coverage
- ✅ **REQUIRE**: New public functions have unit tests
- ✅ **REQUIRE**: Integration tests for gRPC endpoints
- ✅ **REQUIRE**: Error paths tested (invalid input, timeout, DB error)
- ✅ **REQUIRE**: Code coverage >= 70% for service logic

**Audit Point**:
```rust
#[tokio::test]
async fn test_create_user_with_invalid_email() {
    let service = UserService::new(mock_db());
    let result = service.create_user(Request::new(CreateUserRequest {
        email: "invalid".to_string(),
        ..Default::default()
    })).await;

    assert!(result.is_err());
    assert_eq!(result.unwrap_err().code(), Code::InvalidArgument);
}
```

---

#### 12. Code Style & Formatting
- ✅ **REQUIRE**: `cargo fmt` passes
- ✅ **REQUIRE**: Lines < 100 characters (readability)
- ✅ **REQUIRE**: Comments explain "why", not "what"
- ✅ **REQUIRE**: Function length < 50 lines (prefer small, composable functions)

---

### Performance & Observability

#### 13. Logging & Tracing
- ✅ **REQUIRE**: Use `tracing` crate (structured logging)
- ✅ **REQUIRE**: Request correlation ID in all logs
- ✅ **REQUIRE**: Log levels: DEBUG for dev, INFO for prod
- ❌ **DENY**: Unstructured `println!()` or `eprintln!()`

---

#### 14. Metrics
- ✅ **REQUIRE**: gRPC endpoints expose Prometheus metrics
- ✅ **REQUIRE**: Key metrics: request count, latency, errors
- ✅ **REQUIRE**: Database query metrics (count, duration, errors)
- ✅ **REQUIRE**: Resource usage (CPU, memory, goroutines/tasks)

---

## 🚨 BLOCKING Issues (STOP & Fix)

If ANY of these are found, reject the PR and request fixes:

| Level | Category | Condition |
|-------|----------|-----------|
| P0 | Security | Credentials in code/logs |
| P0 | Security | Missing auth on any endpoint |
| P0 | Data | Breaking schema change (no expand-contract) |
| P1 | Rust | `.unwrap()` in I/O paths |
| P1 | Rust | `cargo clippy` fails |
| P1 | Error Handling | Unhandled errors (`.ok()`, `.ignore()`) |

---

## ✅ Non-Blocking Suggestions

These can be noted but won't block merge:

- [ ] Add test for edge case X
- [ ] Consider using enum instead of bool
- [ ] Error message could be more descriptive
- [ ] Performance: Consider batching these queries
- [ ] Documentation: Add doc comment to public function

---

## Review Checklist for Codex

For every PR, verify:

- [ ] No secrets (API keys, passwords, tokens)
- [ ] All HTTP endpoints authenticated
- [ ] Database changes follow expand-contract
- [ ] No `unwrap()` in async I/O paths
- [ ] gRPC servers include health checks & interceptors
- [ ] Error handling is explicit (no `.ok()` in critical paths)
- [ ] Logging is structured + has correlation ID
- [ ] Tests cover happy path + error cases
- [ ] `cargo fmt` and `cargo clippy -- -D warnings` pass

---

## Tool Commands

**For local validation before PR**:

```bash
# Format
cargo fmt --all

# Lint
cargo clippy --all -- -D warnings

# Security audit
cargo audit

# Test
cargo test --all

# Coverage (with tarpaulin)
cargo tarpaulin --out Html --output-dir coverage/
```

---

## Questions & Escalation

- **Q**: Can I use `.unwrap()` if I "know it's safe"?
  - **A**: No. Use `context()` or `.expect("reason")` with explicit justification.

- **Q**: Do I need tests for helper functions?
  - **A**: If public, yes. If private and < 5 lines, suggest adding only if complex logic.

- **Q**: Can I do `ON DELETE CASCADE` for convenience?
  - **A**: Only if you can guarantee single responsibility + no data orphaning risk. Prefer Outbox pattern + events.

---

## References

- [CLAUDE.md](./CLAUDE.md) - Team principles & practices
- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
- [gRPC Best Practices](https://grpc.io/docs/guides/performance-best-practices/)
- [Outbox Pattern](https://microservices.io/patterns/data/transactional-outbox.html)

