# Claude Code Review Standards

**Version**: 2.0 (AI-Powered Review)
**Last Updated**: 2025-11-06
**Scope**: Deep security & architecture review for Claude Code

---

## Core Principles

### 1. Security First - Never Compromise
- **Credentials**: Zero tolerance for hardcoded secrets, API keys, or PII in logs
- **Authentication**: Every endpoint MUST have auth enforcement (no exceptions)
- **Unsafe Operations**: No `unwrap()` in I/O paths, no SQL concat, no eval
- **Output**: Always flag with `[BLOCKER]` if P0/P1 risk found

### 2. Minimalist Fixes - Suggest Only Essential Changes
- Prefer `context()` over `.expect()`
- Recommend typed errors over string errors
- Suggest enum over bool flags
- Point out missing tests for new public APIs
- Provide exact code snippets for recommended changes

### 3. Backward Compatibility - Never Break Userspace
- Database migrations MUST follow expand-contract pattern
- API changes require deprecation period
- Feature flags for all experimental code
- Test rollback scenarios

---

## Review Checklist (Security Focus)

### P0 Blockers (MUST FIX before merge)
- [ ] Credentials in code/logs/comments
- [ ] Missing authentication on HTTP endpoints
- [ ] SQL injection risk (raw string concatenation)
- [ ] RCE risk (eval, exec, system calls with user input)
- [ ] Breaking database schema changes
- [ ] Unsafe crypto (weak algorithms, no salting)

### P1 High Priority
- [ ] `.unwrap()` in I/O paths
- [ ] Missing timeout on network/DB operations
- [ ] Unhandled errors (`.ok()` without logging)
- [ ] Missing input validation
- [ ] Access control bypass risk
- [ ] Connection pool exhaustion (no limits)

### P2 Code Quality
- [ ] Missing tests for new functions
- [ ] Error messages unclear
- [ ] Complex branching (>3 levels)
- [ ] Performance: N+1 queries
- [ ] Code duplication (>20 lines)

---

## Review Output Format

### Finding Template
```
**[BLOCKER] Category: <Issue>**
  Location: `path/to/file.rs:line`

  Current:
  ```rust
  <current code snippet>
  ```

  Risk: <Specific risk explanation>

  Recommended:
  ```rust
  <suggested fix>
  ```

  Reasoning: <Why this matters>
```

### Suggestion Template (Non-Blocking)
```
**Category: <Issue>**
  Consider: <suggestion>

  Example:
  ```rust
  <code example>
  ```
```

---

## gRPC Microservices Review Specifics

### Service Architecture
- [ ] Health check endpoint implemented
- [ ] Auth interceptor validates JWT/credentials
- [ ] Metrics interceptor logs requests
- [ ] Tracing interceptor propagates correlation ID
- [ ] Max message size configured
- [ ] Error codes map to gRPC Status (not all Internal)

### Database Interaction
- [ ] Connection pool has timeout + max connections
- [ ] All queries parameterized (no string concat)
- [ ] Foreign keys explicitly defined (RESTRICT preferred)
- [ ] Soft-delete for audit trails (not hard delete)
- [ ] Outbox pattern for event reliability

### Async/Concurrency
- [ ] No blocking operations in async code
- [ ] `spawn_blocking` used for CPU-intensive work
- [ ] Correlation ID propagated through async chain
- [ ] Timeout wrapping all external calls

---

## Rust-Specific Deep Dives

### Error Handling Hierarchy
```rust
// ✅ Best: Custom error type with context
pub enum UserServiceError {
    NotFound(UserId),
    InvalidEmail(String),
    DatabaseError(String),
}

// ✅ Good: anyhow with context
let user = db.find_user(id)
    .await
    .context("Failed to find user in database")?;

// ⚠️ Acceptable with justification: expect
let pool = db_pool.get_connection()
    .expect("Pool initialized in main; always valid");

// ❌ NEVER in production: unwrap
let user = db.find_user(id).await.unwrap();  // PANICS!
```

### Connection Pooling
```rust
// ✅ GOOD
let pool = PgPoolOptions::new()
    .max_connections(50)
    .connect_timeout(Duration::from_secs(5))
    .idle_timeout(Duration::from_secs(300))
    .acquire_timeout(Duration::from_secs(10))
    .connect(&url)
    .await?;

// ❌ BAD: No timeouts
let pool = PgPool::connect(&url).await?;
```

### Logging (Structured, No PII)
```rust
// ✅ GOOD
tracing::info!(user_id=%user.id, "User authenticated");
tracing::warn!(error=?err, "Request failed");

// ❌ BAD: PII, unstructured
println!("User {} logged in", user.email);  // PII!
tracing::info!("Error: {}", format!("{:?}", error));  // Unstructured
```

---

## Database Review

### Migration Strategy
- **Expand**: Add new column/table
- **Contract**: App code adapts to new structure
- **Migrate**: Backfill data (in separate job or migration)
- **Deprecate**: Old column/table marked as unused
- **Remove**: Drop after 1-2 release cycles

**Blocking**: Direct column drops, renames, type changes (no expand-contract).

### Foreign Keys
```sql
-- ✅ GOOD: Explicit strategy
ALTER TABLE messages
  ADD CONSTRAINT fk_user
  FOREIGN KEY (user_id) REFERENCES users(id)
  ON DELETE RESTRICT;

-- ❌ BAD: Implicit (default CASCADE)
ALTER TABLE messages
  ADD CONSTRAINT fk_user
  FOREIGN KEY (user_id) REFERENCES users(id);
```

---

## Testing Expectations

### Unit Tests
- **Required**: All public functions
- **Coverage**: Happy path + error cases
- **Focus**: Business logic, error handling

### Integration Tests
- **Required**: gRPC endpoints
- **Coverage**: Auth, timeout, error responses
- **Focus**: Service boundaries, external calls

### Example Test Structure
```rust
#[tokio::test]
async fn test_create_user_invalid_email() {
    let service = UserService::new(mock_db());
    let req = CreateUserRequest {
        email: "invalid".to_string(),
        ..Default::default()
    };

    let result = service.create_user(Request::new(req)).await;

    assert!(result.is_err());
    let status = result.unwrap_err();
    assert_eq!(status.code(), Code::InvalidArgument);
}
```

---

## Code Style & Readability

### Function Size Rule
- Target: < 50 lines
- Max: 100 lines (complex logic only)
- Reasoning: Easier to test, understand, and maintain

### Nesting Depth
- ❌ > 4 levels: Refactor into helper functions
- ✅ Prefer guard clauses and early returns

```rust
// ❌ BAD: 4+ nesting levels
pub async fn process_request(req: Request) -> Result<Response> {
    if let Some(user_id) = extract_user_id(&req) {
        if let Ok(user) = db.get_user(user_id).await {
            if user.is_active {
                if user.has_permission("write") {
                    return Ok(process(req).await?);
                }
            }
        }
    }
    Err(Error::Unauthorized)
}

// ✅ GOOD: Guard clauses
pub async fn process_request(req: Request) -> Result<Response> {
    let user_id = extract_user_id(&req)?;
    let user = db.get_user(user_id).await?;

    if !user.is_active {
        return Err(Error::Inactive);
    }

    user.assert_permission("write")?;
    process(req).await
}
```

---

## Diff Review Tips

1. **Read commit message first** - Understand intent
2. **Check database migrations** - Highest risk
3. **Find auth layers** - Every endpoint touch
4. **Scan for unwrap/panic** - Runtime bombs
5. **Review error handling** - All paths covered?
6. **Check timeouts** - Network ops have limits?
7. **Verify tests added** - New code has coverage

---

## Communication Style

### For Blockers
```
**[BLOCKER] Security: Hardcoded API Key**

Location: `backend/user-service/src/main.rs:42`

This will be caught in production and rejected. Must use environment variables.

Fix: Change to `env::var("ANTHROPIC_API_KEY")?`
```

### For Suggestions
```
**Suggestion: Error Handling**

Consider using `.context()` instead of `.expect()`:

Before:
```rust
let config = load_config().expect("config");
```

After:
```rust
let config = load_config().context("Failed to load config")?;
```

This provides better error messages in logs.
```

---

## Integration with AI Review Workflow

When triggered by `.github/workflows/ai-code-review.yml`:

1. **Read PR description** - Understand scope
2. **Get full diff** - Context matters
3. **Check for AGENTS.md** - Apply team standards
4. **Deep security review** - Blocker detection
5. **Comment with findings** - Clear, actionable
6. **Link to AGENTS.md** - Standards reference

---

## Self-Check Before Commenting

- [ ] Have I read the entire PR context?
- [ ] Is this a real issue or false positive?
- [ ] Did I provide a fix, not just criticism?
- [ ] Is the suggestion actionable?
- [ ] Have I referenced the relevant standard (AGENTS.md)?

