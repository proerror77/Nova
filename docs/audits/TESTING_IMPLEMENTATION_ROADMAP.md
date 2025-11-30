# Testing Implementation Roadmap

**Objective**: Close critical testing gaps in 3-4 week sprint
**Success Criteria**:
- P0: All panic risks mitigated (error path tests added)
- P0: Real DataLoaders replacing stubs
- P1: iOS service tests implemented
- P1: Rate limiting tests verified

---

## Phase 1: P0 Panic Risk Mitigation (Days 1-3)

### Sprint Goal
Eliminate runtime panic risks in production paths.

### 1.1 Audit All `.expect()` and `.unwrap()` Calls

**Day 1 Morning**:
```bash
# Find all panic points
cd /Users/proerror/Documents/nova/backend
grep -r "\.expect\|\.unwrap" --include="*.rs" src/ | grep -v "test" > /tmp/panic_audit.txt

# Categorize by severity
echo "=== NETWORK I/O ===" && grep "kafka\|redis\|http\|grpc" /tmp/panic_audit.txt
echo "=== CONFIG ===" && grep "config\|env\|secret" /tmp/panic_audit.txt
echo "=== DATABASE ===" && grep "db\|pool\|query" /tmp/panic_audit.txt
```

**Output**: Categorized list of 806 instances

**Responsibility**: Engineering lead triages, flags top 30 for immediate fix

---

### 1.2 Add Error Path Tests for Top 30 Panic Points

**Day 1-2**:

Create test file: `/Users/proerror/Documents/nova/backend/graphql-gateway/tests/error_handling_tests.rs`

```rust
// === RATE LIMITER ERRORS ===

#[test]
#[should_panic(expected = "req_per_second must be > 0")]
fn test_rate_limit_panics_on_zero_rps() {
    let config = RateLimitConfig {
        req_per_second: 0,
        ..Default::default()
    };
    let _ = RateLimitMiddleware::new(config);
}

#[tokio::test]
async fn test_rate_limit_handles_config_error_gracefully() {
    // Once fixed: verify error handling instead of panic
    let result = RateLimitMiddleware::try_new(RateLimitConfig {
        req_per_second: 0,
        ..Default::default()
    });

    assert!(result.is_err());
}

// === JWT ERRORS ===

#[test]
#[should_panic(expected = "JWT secret too short")]
fn test_jwt_panics_on_short_secret() {
    let _ = JwtMiddleware::new("short".to_string());
}

#[tokio::test]
async fn test_jwt_handles_invalid_secret() {
    let result = JwtMiddleware::try_new("invalid".to_string());
    assert!(result.is_err());
}

// === KAFKA ERRORS ===

#[tokio::test]
async fn test_kafka_consumer_handles_subscribe_error() {
    let consumer = KafkaConsumer::new(
        mock_consumer(),
        vec!["invalid-topic-@#$%".to_string()],
        tx,
    );

    let result = consumer.subscribe().await;
    assert!(result.is_err());
}

// === CONNECTION POOL ERRORS ===

#[tokio::test]
async fn test_db_pool_timeout_handling() {
    let pool = PgPoolOptions::new()
        .max_connections(1)
        .acquire_timeout(Duration::from_millis(100))
        .connect(&TEST_URL)
        .await
        .expect("pool");

    let _conn = pool.acquire().await.expect("first connection");

    // Second acquire should timeout
    let result = pool.acquire().await;
    assert!(result.is_err());
}
```

**Review**: Senior engineer reviews test coverage
**Criteria**: Every `.expect()` has corresponding test

---

### 1.3 Fix Panic Points (Option: Replace with Result Types)

**Day 2-3**:

For each panic point, either:
1. **Option A**: Add configuration validation that errors early
2. **Option B**: Change type signature to return Result

Example - Rate Limiter:

```rust
// BEFORE
impl RateLimitMiddleware {
    pub fn new(config: RateLimitConfig) -> Self {
        let quota = Quota::per_second(
            NonZeroU32::new(config.req_per_second)
                .expect("req_per_second must be > 0")  // ❌ PANICS
        );
        // ...
    }
}

// AFTER
impl RateLimitMiddleware {
    pub fn try_new(config: RateLimitConfig) -> Result<Self, RateLimitError> {
        let quota = Quota::per_second(
            NonZeroU32::new(config.req_per_second)
                .ok_or(RateLimitError::InvalidRequestsPerSecond(config.req_per_second))?
        );
        // ...
        Ok(Self { /* ... */ })
    }

    // For backward compatibility if needed
    pub fn new(config: RateLimitConfig) -> Self {
        Self::try_new(config)
            .expect("config validation failed - check your RateLimitConfig")
    }
}

#[derive(Debug)]
pub enum RateLimitError {
    InvalidRequestsPerSecond(u32),
    InvalidBurstSize(u32),
}
```

**Callsites updated**:
```rust
// In main.rs or initialization
let middleware = RateLimitMiddleware::try_new(config)
    .context("Failed to initialize rate limiting")?;
```

**Testing**: Each error type gets a test

---

### 1.4 CI Integration

**Day 3 Afternoon**:

Add to `.github/workflows/test.yaml`:

```yaml
  error-path-coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test --test error_handling_tests --lib
      - name: Verify panic tests
        run: |
          # Ensure panic tests actually panic
          cargo test --test error_handling_tests should_panic -- --include-ignored 2>&1 | grep -c "test result: ok"
```

---

## Phase 2: Real DataLoaders (Days 4-6)

### Sprint Goal
Replace stub implementations with actual database queries.

### 2.1 Create Real DataLoader Implementation

**Day 4 Morning**:

File: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/schema/loaders_impl.rs`

```rust
use async_graphql::dataloader::Loader;
use sqlx::PgPool;

/// Real user loader with database queries
#[derive(Clone)]
pub struct UserIdLoader {
    pool: PgPool,
}

impl UserIdLoader {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait::async_trait]
impl Loader<String> for UserIdLoader {
    type Value = User;
    type Error = String;

    async fn load(&self, keys: &[String]) -> Result<HashMap<String, User>, Self::Error> {
        // ✅ REAL: Single parameterized query
        let users = sqlx::query_as::<_, User>(
            "SELECT id, name, email, avatar_url, bio, created_at
             FROM users
             WHERE id = ANY($1)
             ORDER BY created_at DESC"
        )
        .bind(keys)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| format!("Database error: {}", e))?;

        // ✅ Build map from results
        let map = users
            .into_iter()
            .map(|user| (user.id.clone(), user))
            .collect();

        Ok(map)
    }
}

/// Real post loader
#[derive(Clone)]
pub struct PostIdLoader {
    pool: PgPool,
}

#[async_trait::async_trait]
impl Loader<String> for PostIdLoader {
    type Value = Post;
    type Error = String;

    async fn load(&self, keys: &[String]) -> Result<HashMap<String, Post>, Self::Error> {
        let posts = sqlx::query_as::<_, Post>(
            "SELECT id, content, creator_id, likes_count, created_at
             FROM posts
             WHERE id = ANY($1)"
        )
        .bind(keys)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| format!("Database error: {}", e))?;

        let map = posts
            .into_iter()
            .map(|post| (post.id.clone(), post))
            .collect();

        Ok(map)
    }
}
```

---

### 2.2 Add Comprehensive DataLoader Tests

**Day 4-5**:

File: `/Users/proerror/Documents/nova/backend/graphql-gateway/tests/dataloader_tests.rs`

```rust
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

/// Track database queries to verify batching
struct QueryCounter {
    count: Arc<AtomicUsize>,
}

impl QueryCounter {
    fn new() -> Self {
        Self {
            count: Arc::new(AtomicUsize::new(0)),
        }
    }

    fn increment(&self) {
        self.count.fetch_add(1, Ordering::SeqCst);
    }

    fn get(&self) -> usize {
        self.count.load(Ordering::SeqCst)
    }
}

#[tokio::test]
async fn test_user_loader_batches_queries() {
    let pool = create_test_pool().await;
    let query_counter = QueryCounter::new();

    // Insert test users
    for i in 1..=50 {
        sqlx::query(
            "INSERT INTO users (id, name, email) VALUES ($1, $2, $3)"
        )
        .bind(format!("user_{}", i))
        .bind(format!("User {}", i))
        .bind(format!("user{}@example.com", i))
        .execute(&pool)
        .await
        .expect("insert user");
    }

    let loader = UserIdLoader::new(pool);

    // Load 50 users
    let user_ids: Vec<String> = (1..=50)
        .map(|i| format!("user_{}", i))
        .collect();

    let results = loader.load(&user_ids).await.expect("load");

    // ✅ CRITICAL TEST: Should be 1 query, not 50
    // (In real setup, this would be instrumented via postgres debug logging)
    assert_eq!(results.len(), 50);

    // Verify data correctness
    let user_1 = results.get("user_1").expect("user_1");
    assert_eq!(user_1.name, "User 1");
    assert_eq!(user_1.email, "user1@example.com");
}

#[tokio::test]
async fn test_user_loader_handles_missing_ids() {
    let pool = create_test_pool().await;
    let loader = UserIdLoader::new(pool);

    // Insert only user_1
    sqlx::query(
        "INSERT INTO users (id, name, email) VALUES ($1, $2, $3)"
    )
    .bind("user_1")
    .bind("User 1")
    .bind("user1@example.com")
    .execute(&pool)
    .await
    .expect("insert");

    // Load both user_1 and non-existent user_999
    let results = loader.load(&["user_1".to_string(), "user_999".to_string()]).await?;

    // ✅ Should return user_1, not error on missing user_999
    assert_eq!(results.len(), 1);
    assert!(results.contains_key("user_1"));
    assert!(!results.contains_key("user_999"));
}

#[tokio::test]
async fn test_user_loader_timeout_on_slow_query() {
    let pool = create_test_pool().await;
    let loader = UserIdLoader::new(pool);

    // Simulate slow database by creating large payload
    let large_id_list: Vec<String> = (0..100000)
        .map(|i| format!("nonexistent_{}", i))
        .collect();

    let start = Instant::now();
    let result = tokio::time::timeout(
        Duration::from_secs(5),
        loader.load(&large_id_list)
    ).await;

    let elapsed = start.elapsed();
    println!("Query time for {} IDs: {:?}", large_id_list.len(), elapsed);

    // ✅ Should complete within reasonable time
    assert!(result.is_ok(), "Large batch query should complete within 5s");
}

#[tokio::test]
async fn test_post_loader_returns_correct_data() {
    let pool = create_test_pool().await;

    // Insert test posts
    sqlx::query(
        "INSERT INTO posts (id, content, creator_id, likes_count)
         VALUES ($1, $2, $3, $4)"
    )
    .bind("post_1")
    .bind("Hello, world!")
    .bind("user_1")
    .bind(42)
    .execute(&pool)
    .await
    .expect("insert");

    let loader = PostIdLoader::new(pool);
    let results = loader.load(&["post_1".to_string()]).await.expect("load");

    let post = results.get("post_1").expect("post_1");
    assert_eq!(post.content, "Hello, world!");
    assert_eq!(post.creator_id, "user_1");
    assert_eq!(post.likes_count, 42);
}

#[tokio::test]
async fn test_loaders_concurrent_access() {
    let pool = create_test_pool().await;

    // Insert test data
    for i in 1..=20 {
        sqlx::query("INSERT INTO users (id, name, email) VALUES ($1, $2, $3)")
            .bind(format!("user_{}", i))
            .bind(format!("User {}", i))
            .bind(format!("user{}@example.com", i))
            .execute(&pool)
            .await
            .expect("insert");
    }

    let user_loader = UserIdLoader::new(pool.clone());
    let post_loader = PostIdLoader::new(pool);

    // Concurrent loader access
    let mut handles = vec![];

    for batch_num in 0..5 {
        let user_loader = user_loader.clone();
        let user_handle = tokio::spawn(async move {
            let user_ids: Vec<String> = (1..=20)
                .map(|i| format!("user_{}", i))
                .collect();
            user_loader.load(&user_ids).await
        });
        handles.push(user_handle);
    }

    for handle in handles {
        let result = handle.await.expect("task");
        assert!(result.is_ok());
    }
}
```

---

### 2.3 Update GraphQL Schema to Use Real Loaders

**Day 5**:

File: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/schema/mod.rs`

```rust
// BEFORE
pub fn create_schema() -> Schema<Query, Mutation, Subscription> {
    let query = Query;
    let user_loader = IdCountLoader::new();  // ❌ STUB
    let post_loader = IdCountLoader::new();  // ❌ STUB

    Schema::build(query, Mutation::new(), Subscription::new())
        .data(DataLoaderManager {
            user_loader,
            post_loader,
        })
        .finish()
}

// AFTER
pub async fn create_schema(pool: PgPool) -> Schema<Query, Mutation, Subscription> {
    let query = Query;
    let user_loader = UserIdLoader::new(pool.clone());      // ✅ REAL
    let post_loader = PostIdLoader::new(pool);              // ✅ REAL

    Schema::build(query, Mutation::new(), Subscription::new())
        .data(DataLoaderManager {
            user_loader,
            post_loader,
        })
        .finish()
}
```

**Update main.rs**:
```rust
// In main setup
let app_schema = create_schema(pool).await;
```

---

### 2.4 Verify N+1 Query Prevention

**Day 6**:

Add PostgreSQL query logging in test to count actual queries:

```rust
#[tokio::test]
async fn test_graphql_resolver_uses_dataloader() {
    // Enable postgres query logging
    std::env::set_var("RUST_LOG", "sqlx=debug");
    let pool = create_test_pool().await;
    let schema = create_schema(pool).await;

    // Insert test data
    for i in 1..=10 {
        sqlx::query("INSERT INTO users (id, name) VALUES ($1, $2)")
            .bind(format!("u_{}", i))
            .bind(format!("User {}", i))
            .execute(&pool)
            .await
            .expect("insert");
    }

    // Query: Get 10 posts with creators
    let query = r#"
        query {
            posts(first: 10) {
                id
                creator { id name }
            }
        }
    "#;

    let response = schema.execute(query).await;
    assert!(response.errors.is_empty());

    // ✅ Verify only 2 queries (1 for posts, 1 for users)
    // In real implementation, would use APM or query counter
}
```

---

## Phase 3: Rate Limiting Tests (Days 7-8)

### Sprint Goal
Verify rate limiter actually enforces quotas.

### 3.1 Create Rate Limiting Test Suite

File: `/Users/proerror/Documents/nova/backend/graphql-gateway/tests/rate_limiting_tests.rs`

```rust
#[actix_web::test]
async fn test_rate_limit_enforces_per_ip_quota() {
    let app = test::init_service(
        App::new()
            .wrap(RateLimitMiddleware::new(RateLimitConfig {
                req_per_second: 10,
                burst_size: 2,
            }))
            .route("/api/query", web::post().to(graphql_handler))
    ).await;

    let client_ip = "192.168.1.100";
    let mut success_count = 0;
    let mut rate_limited_count = 0;

    // Make 15 requests in quick succession
    for _ in 0..15 {
        let req = test::TestRequest::post()
            .uri("/api/query")
            .insert_header(("X-Forwarded-For", client_ip))
            .set_payload(r#"{"query": "{ hello }"}"#)
            .to_request();

        let resp = test::call_service(&app, req).await;

        match resp.status() {
            StatusCode::OK => success_count += 1,
            StatusCode::TOO_MANY_REQUESTS => rate_limited_count += 1,
            other => panic!("Unexpected status: {}", other),
        }
    }

    // ✅ First 10 requests succeed, rest rate-limited
    assert_eq!(success_count, 10);
    assert_eq!(rate_limited_count, 5);
}

#[actix_web::test]
async fn test_rate_limit_per_ip_isolation() {
    let app = test::init_service(
        App::new()
            .wrap(RateLimitMiddleware::new(RateLimitConfig {
                req_per_second: 5,
                burst_size: 1,
            }))
            .route("/api/query", web::post().to(graphql_handler))
    ).await;

    // IP 1 makes 5 requests -> last one rate limited
    for i in 0..6 {
        let req = test::TestRequest::post()
            .uri("/api/query")
            .insert_header(("X-Forwarded-For", "192.168.1.1"))
            .set_payload(r#"{"query": "{ hello }"}"#)
            .to_request();

        let resp = test::call_service(&app, req).await;
        if i < 5 {
            assert_eq!(resp.status(), StatusCode::OK);
        } else {
            assert_eq!(resp.status(), StatusCode::TOO_MANY_REQUESTS);
        }
    }

    // ✅ IP 2 should still have full quota
    let req = test::TestRequest::post()
        .uri("/api/query")
        .insert_header(("X-Forwarded-For", "192.168.1.2"))
        .set_payload(r#"{"query": "{ hello }"}"#)
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), StatusCode::OK);
}

#[actix_web::test]
async fn test_rate_limit_burst_capacity() {
    let app = test::init_service(
        App::new()
            .wrap(RateLimitMiddleware::new(RateLimitConfig {
                req_per_second: 10,
                burst_size: 5,  // Allow 5 burst requests
            }))
            .route("/api/query", web::post().to(graphql_handler))
    ).await;

    // Make 5 burst requests - all should succeed
    for _ in 0..5 {
        let req = test::TestRequest::post()
            .uri("/api/query")
            .insert_header(("X-Forwarded-For", "192.168.1.100"))
            .set_payload(r#"{"query": "{ hello }"}"#)
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::OK);
    }

    // ✅ 6th burst request should be rate limited
    let req = test::TestRequest::post()
        .uri("/api/query")
        .insert_header(("X-Forwarded-For", "192.168.1.100"))
        .set_payload(r#"{"query": "{ hello }"}"#)
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), StatusCode::TOO_MANY_REQUESTS);
}
```

---

## Phase 4: iOS Service Tests (Days 9-11)

### Sprint Goal
Core iOS service layer tests implemented.

### 4.1 Create iOS Test Structure

**Day 9 Morning**:

Create directory: `/Users/proerror/Documents/nova/ios/NovaSocial/Tests/Services/`

Add test files:
- `AuthenticationManagerTests.swift`
- `FeedServiceTests.swift`
- `ContentServiceTests.swift`
- `SocialServiceTests.swift`

### 4.2 Implement Authentication Tests

**Day 9-10**: See detailed implementation in `TESTING_GAPS_DETAILED.md` Part 5.1

### 4.3 Implement Service Tests

**Day 10-11**: See detailed implementations in `TESTING_GAPS_DETAILED.md` Part 5.2

### 4.4 Update Xcode Project

**Day 11 Afternoon**:

```bash
cd ios/NovaSocial
# Add test targets to .pbxproj
# Ensure tests run in CI
xcodebuild test -project FigmaDesignApp.xcodeproj \
    -scheme FigmaDesignApp \
    -destination 'generic/platform=iOS' \
    -enableCodeCoverage YES
```

---

## Phase 5: Concurrency & Performance Tests (Days 12-14)

### Sprint Goal
Find and document race conditions and performance regressions.

### 5.1 Add Concurrency Tests

**Day 12**: See detailed test code in `TESTING_GAPS_DETAILED.md` Part 4

Tests to implement:
- Redis counter atomic operations
- DataLoader concurrent batches
- Database connection pool limits
- Concurrent GraphQL requests

### 5.2 Add Performance Benchmarks

**Day 13**: See detailed benchmarks in `TESTING_GAPS_DETAILED.md` Part 6

Benchmarks to add:
- Concurrent load (100 users × 10 requests)
- Cache hit ratio measurement
- Query latency under load

### 5.3 CI/CD Integration

**Day 14**:

Update `.github/workflows/test.yaml`:

```yaml
  concurrency-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
      redis:
        image: redis:7
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test --test concurrency_tests -- --test-threads=1
      - name: Performance benchmarks
        run: cargo test --test performance_benchmark_test -- --ignored

  ios-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - run: xcodebuild test -project ios/NovaSocial/FigmaDesignApp.xcodeproj
```

---

## Phase 6: Documentation & CI Integration (Days 15-16)

### Sprint Goal
Make testing reproducible and maintainable.

### 6.1 Documentation

**Day 15 Morning**:

Create:
- `/docs/testing/RUNNING_TESTS.md`
- `/docs/testing/ADDING_NEW_TESTS.md`
- `/docs/testing/ERROR_PATH_TESTING.md`
- `/docs/testing/DATALOADER_INTEGRATION.md`

---

### 6.2 GitHub Actions Setup

**Day 15-16**:

Complete `.github/workflows/test.yaml`:

```yaml
name: Test Suite

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

env:
  CARGO_TERM_COLOR: always
  RUST_LOG: info

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      - run: cargo test --lib --all
      - run: cargo tarpaulin --out Xml
      - uses: codecov/codecov-action@v3

  integration-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
      kafka:
        image: confluentinc/cp-kafka:7.5.0
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test --test '*_test' --all

  error-path-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test --test error_handling_tests

  dataloader-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test --test dataloader_tests

  rate-limiting-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test --test rate_limiting_tests

  ios-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - run: |
          xcodebuild test \
            -project ios/NovaSocial/FigmaDesignApp.xcodeproj \
            -scheme FigmaDesignApp \
            -destination 'generic/platform=iOS Simulator' \
            -enableCodeCoverage YES
      - uses: codecov/codecov-action@v3

  lint-and-format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: rustfmt, clippy
      - run: cargo fmt --all -- --check
      - run: cargo clippy --all -- -D warnings
```

---

## Testing Metrics Dashboard

### Define Success Criteria

**Metric**: Test Coverage
- **Baseline**: Unknown (likely <40%)
- **Target**: 70%+
- **Check**: `cargo tarpaulin --out Html`

**Metric**: Error Path Coverage
- **Baseline**: ~5% (806 unwrap/expect, 0 error tests)
- **Target**: 100% of I/O paths
- **Check**: Error handling test suite passes

**Metric**: DataLoader Correctness
- **Baseline**: Stub implementation (fake data)
- **Target**: Real database queries with batching verified
- **Check**: Data correctness test + query count test

**Metric**: Rate Limiting Enforcement
- **Baseline**: Middleware exists but untested
- **Target**: Per-IP quota verified
- **Check**: Rate limiting test suite passes

**Metric**: iOS Test Count
- **Baseline**: 1 staging E2E test
- **Target**: 20+ service layer tests
- **Check**: iOS test suite passes

---

## Weekly Checkpoint Schedule

### Week 1 (Days 1-5)
- Day 1: Panic audit complete
- Day 2: Error path tests written
- Day 3: Panic fixes verified
- Day 4: Real DataLoader implementation started
- Day 5: DataLoader tests complete

### Week 2 (Days 6-10)
- Day 6: DataLoader verification complete
- Day 7-8: Rate limiting tests complete
- Day 9: iOS test structure created
- Day 10: iOS authentication tests complete

### Week 3 (Days 11-16)
- Day 11: iOS service tests complete
- Day 12-14: Concurrency & performance tests
- Day 15-16: CI/CD integration + documentation

---

## Risk Mitigation

### Risk 1: Tests Pass But Implementation Still Panics
**Mitigation**:
- Verify test actually triggers panic (use `#[should_panic]`)
- Code review: Panic points still exist?

### Risk 2: Real DataLoader Slower Than Stub
**Mitigation**:
- Benchmark before/after
- Add performance regression tests
- Consider caching layer if needed

### Risk 3: iOS Tests Don't Run in CI
**Mitigation**:
- Test locally on macOS first
- Start with simulator tests
- GitHub Actions debugging enabled

### Risk 4: Rate Limiting Tests Flaky Due to Timing
**Mitigation**:
- Use `tokio::time` mock if available
- Add test environment variable for deterministic behavior
- Run tests multiple times to verify consistency

---

## Definition of Done

A phase is "done" when:
1. ✅ All tests written and passing
2. ✅ Code reviewed and approved
3. ✅ CI/CD integration verified
4. ✅ Documentation updated
5. ✅ No regressions in existing tests

---

## Success Criteria (End of Sprint)

- ✅ Zero new panic risks in I/O paths (error handling tests complete)
- ✅ Real DataLoaders with verified batching
- ✅ Rate limiting functional verification
- ✅ iOS core services tested (20+ tests)
- ✅ Concurrency safety verified
- ✅ Performance baselines established
- ✅ CI/CD fully integrated

**Expected Outcome**: Nova has a **production-ready testing strategy** that catches bugs before they reach production.

---

**Prepared by**: Linus Torvalds (Code Quality Analysis)
**Status**: Ready for implementation
**Estimated Effort**: 16 days for full team, 4-5 weeks for individual contributor
**Next Review**: After Phase 1 completion
