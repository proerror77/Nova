# Testing Gaps - Detailed Analysis & Code Examples

**Purpose**: Specific code locations, error scenarios, and test implementation guide

---

## Part 1: Panic Risk Inventory

### 1.1 GraphQL Gateway Risks (High Panic Density)

#### Location 1: Rate Limiter Configuration
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/middleware/rate_limit.rs:64-69`

```rust
let quota = Quota::per_second(
    NonZeroU32::new(config.req_per_second).expect("req_per_second must be > 0"),
);
```

**Panic Trigger**: `req_per_second: 0`

**Current Tests**: ❌ None

**Missing Test**:
```rust
#[test]
#[should_panic(expected = "req_per_second must be > 0")]
fn test_rate_limit_config_zero_rps_panics() {
    let config = RateLimitConfig {
        req_per_second: 0,
        burst_size: 10,
    };
    let _ = RateLimitMiddleware::new(config);
}
```

---

#### Location 2: JWT Secret Validation
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/middleware/jwt.rs`

**Code Pattern**:
```rust
pub fn new(secret: String) -> Self {
    assert!(secret.len() >= 32, "JWT secret too short");  // ❌ Panics
    Self { secret }
}
```

**Current Tests**: ✅ Partially covered in `security_auth_tests.rs:38-68`
**Gap**: Only tests `should_panic`, doesn't test error handling path

---

#### Location 3: Kafka Consumer Subscription
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/kafka/consumer.rs:87-89`

```rust
self.consumer
    .subscribe(&topics)
    .map_err(|e| KafkaError::ConsumerError(e.to_string()))?;
```

**Status**: ✅ Uses `?` operator (good)
**Gap**: No test for subscription failure scenarios

**Missing Test**:
```rust
#[tokio::test]
async fn test_kafka_consumer_handles_invalid_topic() {
    let consumer = KafkaConsumer::new(
        create_mock_consumer(),
        vec!["invalid-topic-@#$%".to_string()],
        tx,
    );

    let result = consumer.subscribe().await;

    // ✅ Should error gracefully, not panic
    assert!(result.is_err());
    if let Err(KafkaError::ConsumerError(msg)) = result {
        assert!(msg.contains("topic"));
    }
}
```

---

### 1.2 Connection Pool Configuration Risks

#### Location: DB Pool Setup
**File**: `/Users/proerror/Documents/nova/backend/libs/db-pool/Cargo.toml`

**Tests Exist**: `/Users/proerror/Documents/nova/backend/libs/db-pool/tests/` (3 files)

**Gap**: Tests likely don't cover:
- ❌ Max connections = 0
- ❌ Timeout = 0
- ❌ Pool exhaustion under load

**Missing Test Pattern**:
```rust
#[tokio::test]
async fn test_db_pool_max_connections_limit() {
    let pool = PgPoolOptions::new()
        .max_connections(2)
        .connect(&TEST_DATABASE_URL)
        .await
        .expect("pool created");

    // Acquire 2 connections
    let conn1 = pool.acquire().await.expect("conn 1");
    let conn2 = pool.acquire().await.expect("conn 2");

    // Try to acquire 3rd with timeout
    let result = tokio::time::timeout(
        Duration::from_millis(100),
        pool.acquire()
    ).await;

    // ✅ Should timeout waiting for available connection
    assert!(result.is_err());
}
```

---

### 1.3 DataLoader Stub Risk

#### Location: User Loader
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/schema/loaders.rs:80-94`

```rust
async fn load(&self, keys: &[String]) -> Result<HashMap<String, Self::Value>, Self::Error> {
    // In production: would query database like:
    // SELECT id, COUNT(*) as count FROM table WHERE id IN (keys) GROUP BY id
    //
    // For demo: simulate with enumeration
    let counts: HashMap<String, i32> = keys
        .iter()
        .enumerate()
        .map(|(idx, id)| (id.clone(), (idx as i32 + 1) * 10))  // ❌ FAKE DATA
        .collect();

    Ok(counts)
}
```

**Current Tests**: ✅ Tests exist but test fake implementation

**Gap**: No test validates:
- ❌ Correct data from database
- ❌ Batch loading actually used (1 query vs N queries)
- ❌ Handling of missing IDs
- ❌ Timeout on slow queries

**Replacement Implementation**:
```rust
#[derive(Clone)]
pub struct UserIdLoader {
    pool: PgPool,
}

#[async_trait::async_trait]
impl Loader<String> for UserIdLoader {
    type Value = User;
    type Error = String;

    async fn load(&self, keys: &[String]) -> Result<HashMap<String, Self::Value>, Self::Error> {
        // ✅ REAL: Query database
        let users = sqlx::query_as::<_, User>(
            "SELECT id, name, email, created_at FROM users WHERE id = ANY($1)"
        )
        .bind(keys)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| e.to_string())?;

        Ok(users.into_iter().map(|u| (u.id.clone(), u)).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_user_loader_batches_queries() {
        let mut query_count = std::sync::atomic::AtomicUsize::new(0);
        let pool = create_test_pool_with_spy(&query_count);
        let loader = UserIdLoader { pool };

        // Load 50 users
        let user_ids: Vec<String> = (1..=50)
            .map(|i| format!("user_{}", i))
            .collect();

        let results = loader.load(&user_ids).await.expect("load");

        // ✅ Should be 1 query, not 50
        assert_eq!(query_count.load(Ordering::SeqCst), 1);
        assert_eq!(results.len(), 50);
    }

    #[tokio::test]
    async fn test_user_loader_returns_correct_data() {
        let pool = create_test_pool().await;
        let loader = UserIdLoader { pool };

        // Insert test user
        sqlx::query("INSERT INTO users (id, name, email) VALUES ($1, $2, $3)")
            .bind("test-user-1")
            .bind("John Doe")
            .bind("john@example.com")
            .execute(&loader.pool)
            .await
            .expect("insert");

        let results = loader.load(&["test-user-1".to_string()]).await.expect("load");

        let user = results.get("test-user-1").expect("user found");
        assert_eq!(user.name, "John Doe");
        assert_eq!(user.email, "john@example.com");
    }
}
```

---

## Part 2: Error Path Coverage

### 2.1 Rate Limiting - Missing Test Scenarios

#### Scenario 1: Per-IP Quota Enforcement
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/middleware/rate_limit.rs`

**Gap**: No test verifies actual rate limiting

**Test to Add**:
```rust
#[actix_web::test]
async fn test_rate_limit_enforces_per_ip_quota() {
    let middleware = RateLimitMiddleware::new(RateLimitConfig {
        req_per_second: 10,
        burst_size: 2,
    });

    let app = test::init_service(
        App::new()
            .wrap(middleware)
            .route("/api/query", web::post().to(graphql_handler))
    ).await;

    // Make 10 requests in quick succession
    let mut success_count = 0;
    let mut rate_limited_count = 0;

    for i in 0..12 {
        let req = test::TestRequest::post()
            .uri("/api/query")
            .insert_header(("X-Forwarded-For", "192.168.1.1"))
            .set_payload(r#"{"query": "{ hello }"}"#)
            .to_request();

        let resp = test::call_service(&app, req).await;

        match resp.status() {
            200 => success_count += 1,
            429 => rate_limited_count += 1,
            status => panic!("Unexpected status: {}", status),
        }
    }

    // First 10 requests succeed, remaining get 429
    assert_eq!(success_count, 10, "First 10 requests should succeed");
    assert_eq!(rate_limited_count, 2, "Next 2 should be rate limited");
}
```

---

#### Scenario 2: X-Forwarded-For Header Parsing
**Gap**: What if header is malformed?

```rust
#[test]
fn test_rate_limit_handles_invalid_forwarded_header() {
    let middleware = RateLimitMiddleware::new(RateLimitConfig::default());

    let req = test::TestRequest::get()
        .insert_header(("X-Forwarded-For", "not-an-ip"))
        .to_request();

    // ✅ Should gracefully handle, not panic
    let result = middleware.process_request(&req);
    assert!(result.is_ok());
}
```

---

### 2.2 Connection Pool - Missing Load Test

#### Scenario: Pool Exhaustion Under Load
**File**: `/Users/proerror/Documents/nova/backend/libs/db-pool/tests/`

```rust
#[tokio::test]
async fn test_db_pool_timeout_under_load() {
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_millis(100))
        .connect(&TEST_DATABASE_URL)
        .await
        .expect("pool created");

    // Spawn 10 tasks each holding a connection
    let mut handles = vec![];
    for _ in 0..10 {
        let pool = pool.clone();
        let handle = tokio::spawn(async move {
            let _conn = pool.acquire().await;
            tokio::time::sleep(Duration::from_secs(1)).await;
        });
        handles.push(handle);
    }

    // Let first 5 acquire connections
    tokio::time::sleep(Duration::from_millis(50)).await;

    // 6th attempt should timeout
    let result = tokio::time::timeout(
        Duration::from_millis(50),
        pool.acquire()
    ).await;

    assert!(result.is_err(), "Should timeout waiting for available connection");

    // Cleanup
    for handle in handles {
        let _ = handle.await;
    }
}
```

---

## Part 3: Security Test Coverage Gaps

### 3.1 Input Validation - Missing Tests

#### Scenario 1: GraphQL Query Depth Limit
**Gap**: No test for depth bomb attack

```rust
// File: /backend/graphql-gateway/tests/security_integration_tests.rs
// ADD THIS TEST:

#[tokio::test]
async fn test_graphql_query_depth_limit_prevents_bomb() {
    let app = create_test_app().await;

    // Create deeply nested query (depth bomb)
    let depth_bomb = r#"
        query {
            post {
                creator {
                    followers {
                        followers {
                            followers {
                                followers {
                                    followers { id }
                                }
                            }
                        }
                    }
                }
            }
        }
    "#;

    let resp = test::call_service(&app, graphql_request(depth_bomb)).await;

    // ✅ Should reject depth bomb
    assert_eq!(resp.status(), 400);
    let body = String::from_utf8(to_bytes(resp.into_body()).await.unwrap()).unwrap();
    assert!(body.contains("depth limit") || body.contains("too deep"));
}
```

---

#### Scenario 2: Query Complexity Limit
```rust
#[tokio::test]
async fn test_graphql_query_complexity_limit() {
    let app = create_test_app().await;

    // Create complex query with many fields
    let complex_query = r#"
        query {
            user { id name email }
            posts(first: 1000) {
                id title content
                comments(first: 100) {
                    id text author { name email }
                }
            }
        }
    "#;

    let resp = test::call_service(&app, graphql_request(complex_query)).await;

    // ✅ Should reject if complexity exceeds limit
    assert!(resp.status().is_client_error());
}
```

---

### 3.2 SQL Injection Prevention - Missing Tests

#### Scenario: Verify Parameterized Queries
```rust
#[tokio::test]
async fn test_feed_api_prevents_sql_injection() {
    let pool = create_test_pool().await;
    let api = FeedApi::new(pool);

    let malicious_user_id = "'; DROP TABLE users; --";

    // ✅ Should safely escape, not execute SQL
    let result = api.get_user_feed(malicious_user_id, 50).await;

    // Should error gracefully, not drop table
    assert!(result.is_err());

    // Verify table still exists
    let table_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users')"
    )
    .fetch_one(&pool)
    .await
    .expect("query");

    assert!(table_exists, "Table should still exist after SQL injection attempt");
}
```

---

### 3.3 CORS Policy - Missing Tests

```rust
#[actix_web::test]
async fn test_cors_blocks_unauthorized_origin() {
    let app = test::init_service(create_app_with_cors()).await;

    let req = test::TestRequest::post()
        .uri("/graphql")
        .insert_header(("Origin", "https://evil.com"))
        .set_payload(r#"{"query": "{ hello }"}"#)
        .to_request();

    let resp = test::call_service(&app, req).await;

    // ✅ Should reject evil.com origin
    assert_eq!(resp.status(), 403);
    assert!(!resp.headers().contains_key("Access-Control-Allow-Origin"));
}

#[actix_web::test]
async fn test_cors_allows_authorized_origin() {
    let app = test::init_service(create_app_with_cors()).await;

    let req = test::TestRequest::post()
        .uri("/graphql")
        .insert_header(("Origin", "https://nova.app"))
        .set_payload(r#"{"query": "{ hello }"}"#)
        .to_request();

    let resp = test::call_service(&app, req).await;

    // ✅ Should allow nova.app origin
    assert_eq!(resp.status(), 200);
    assert_eq!(
        resp.headers().get("Access-Control-Allow-Origin").and_then(|h| h.to_str().ok()),
        Some("https://nova.app")
    );
}
```

---

## Part 4: Concurrency Test Coverage

### 4.1 Redis Counter Race Condition
**File**: Create new test file
**Path**: `/Users/proerror/Documents/nova/backend/graphql-gateway/tests/concurrency_tests.rs`

```rust
use std::sync::Arc;
use tokio::task::JoinSet;

#[tokio::test]
async fn test_redis_counter_increments_atomically() {
    let redis = create_test_redis_client().await;
    let counter_key = "test:counter";

    // Initialize counter
    redis.del(counter_key).await.expect("del");
    redis.set(counter_key, 0).await.expect("set");

    // Spawn 100 concurrent tasks each incrementing counter 10 times
    let mut set = JoinSet::new();
    for _ in 0..100 {
        let redis = redis.clone();
        set.spawn(async move {
            for _ in 0..10 {
                // ⚠️ This pattern is NOT atomic!
                let current = redis.get::<i32>(counter_key).await.expect("get");
                redis.set(counter_key, current + 1).await.expect("set");
            }
        });
    }

    while let Some(result) = set.join_next().await {
        result.expect("task");
    }

    let final_value = redis.get::<i32>(counter_key).await.expect("get");

    // ❌ BUG: This will fail because increments are not atomic!
    // Expected: 1000, Actual: 200-500 (race condition)
    // assert_eq!(final_value, 1000);

    // ✅ SOLUTION: Use INCR command (atomic)
    redis.del(counter_key).await.expect("del");
    let mut set = JoinSet::new();
    for _ in 0..100 {
        let redis = redis.clone();
        set.spawn(async move {
            for _ in 0..10 {
                redis.incr(counter_key, 1).await.expect("incr");
            }
        });
    }

    while let Some(result) = set.join_next().await {
        result.expect("task");
    }

    let final_value = redis.get::<i32>(counter_key).await.expect("get");
    assert_eq!(final_value, 1000, "INCR command is atomic");
}
```

---

### 4.2 Concurrent DataLoader Requests
```rust
#[tokio::test]
async fn test_dataloader_handles_concurrent_batches() {
    let pool = create_test_pool().await;
    let loader = UserIdLoader { pool };

    // Simulate concurrent GraphQL requests
    let mut handles = vec![];
    for batch_num in 0..10 {
        let loader = loader.clone();
        let handle = tokio::spawn(async move {
            let user_ids: Vec<String> = (0..100)
                .map(|i| format!("user_{}_{}", batch_num, i))
                .collect();

            loader.load(&user_ids).await
        });
        handles.push(handle);
    }

    let mut total_users = 0;
    for handle in handles {
        let result = handle.await.expect("task");
        total_users += result.len();
    }

    // ✅ All concurrent batches should load successfully
    assert_eq!(total_users, 10 * 100);
}
```

---

## Part 5: iOS Service Testing

### 5.1 AuthenticationManager Tests

**File**: Create `/Users/proerror/Documents/nova/ios/NovaSocial/Tests/Services/AuthenticationManagerTests.swift`

```swift
import XCTest
@testable import NovaSocial

final class AuthenticationManagerTests: XCTestCase {
    private var authManager: AuthenticationManager!
    private var mockAPIClient: MockAPIClient!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        authManager = AuthenticationManager(apiClient: mockAPIClient)
    }

    // MARK: - Login Tests

    @MainActor
    func testLoginSuccessStoresTokenAndUser() async throws {
        let testUser = User(id: "user-123", name: "John Doe", email: "john@example.com")
        let testToken = "jwt-token-123"
        mockAPIClient.loginResponse = .success(LoginResponse(user: testUser, token: testToken))

        try await authManager.login(email: "john@example.com", password: "password123")

        XCTAssertEqual(authManager.currentToken, testToken)
        XCTAssertEqual(authManager.currentUser?.id, "user-123")
    }

    @MainActor
    func testLoginFailureDoesNotStoreToken() async throws {
        mockAPIClient.loginResponse = .failure(APIError.unauthorized)

        do {
            try await authManager.login(email: "john@example.com", password: "wrongpass")
            XCTFail("Should have thrown unauthorized error")
        } catch {
            XCTAssertNil(authManager.currentToken)
            XCTAssertNil(authManager.currentUser)
        }
    }

    @MainActor
    func testLoginNetworkErrorHandling() async throws {
        mockAPIClient.loginResponse = .failure(APIError.networkError("Connection timeout"))

        do {
            try await authManager.login(email: "john@example.com", password: "password123")
            XCTFail("Should have thrown network error")
        } catch let APIError.networkError(msg) {
            XCTAssertTrue(msg.contains("timeout"))
        }
    }

    // MARK: - Token Refresh Tests

    @MainActor
    func testTokenRefreshUpdatesToken() async throws {
        mockAPIClient.refreshTokenResponse = .success(RefreshResponse(token: "new-jwt-token"))
        authManager.currentToken = "old-token"

        try await authManager.refreshToken()

        XCTAssertEqual(authManager.currentToken, "new-jwt-token")
    }

    @MainActor
    func testTokenRefreshFailureClearsAuth() async throws {
        mockAPIClient.refreshTokenResponse = .failure(APIError.unauthorized)
        authManager.currentToken = "expired-token"

        do {
            try await authManager.refreshToken()
        } catch {
            XCTAssertNil(authManager.currentToken)
        }
    }

    // MARK: - Logout Tests

    @MainActor
    func testLogoutClearsAuthState() async {
        authManager.currentToken = "token-123"
        authManager.currentUser = User(id: "u1", name: "Test", email: "test@example.com")

        await authManager.logout()

        XCTAssertNil(authManager.currentToken)
        XCTAssertNil(authManager.currentUser)
    }
}

// MARK: - Mock API Client

final class MockAPIClient: APIClient {
    var loginResponse: Result<LoginResponse, APIError> = .failure(.unknown)
    var refreshTokenResponse: Result<RefreshResponse, APIError> = .failure(.unknown)

    func login(email: String, password: String) async -> Result<LoginResponse, APIError> {
        loginResponse
    }

    func refreshToken(token: String) async -> Result<RefreshResponse, APIError> {
        refreshTokenResponse
    }
}
```

---

### 5.2 FeedService Tests

```swift
final class FeedServiceTests: XCTestCase {
    private var feedService: FeedService!
    private var mockAPIClient: MockAPIClient!
    private var mockCache: MockCache!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        mockCache = MockCache()
        feedService = FeedService(apiClient: mockAPIClient, cache: mockCache)
    }

    // MARK: - Feed Loading Tests

    func testLoadFeedSuccessfullyCachesResults() async throws {
        let mockPosts = [
            Post(id: "p1", content: "Hello", creator: "u1"),
            Post(id: "p2", content: "World", creator: "u2"),
        ]
        mockAPIClient.feedResponse = .success(mockPosts)

        let posts = try await feedService.loadFeed(userId: "user-1", limit: 50)

        XCTAssertEqual(posts.count, 2)
        XCTAssertEqual(mockCache.cachedKey, "feed:user-1")
    }

    func testLoadFeedReturnssCachedDataOnError() async throws {
        let cachedPosts = [Post(id: "p1", content: "Cached", creator: "u1")]
        mockAPIClient.feedResponse = .failure(APIError.networkError("Offline"))
        mockCache.cachedValue = cachedPosts

        let posts = try await feedService.loadFeed(userId: "user-1", limit: 50)

        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts[0].id, "p1")
    }

    func testLoadFeedRetryOnTransientError() async throws {
        var attemptCount = 0
        mockAPIClient.feedResponseProvider = {
            attemptCount += 1
            if attemptCount < 3 {
                return .failure(APIError.serverError(503, "Service Unavailable"))
            }
            return .success([Post(id: "p1", content: "Retry Success", creator: "u1")])
        }

        let posts = try await feedService.loadFeed(userId: "user-1", limit: 50, maxRetries: 3)

        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(attemptCount, 3)
    }

    // MARK: - Cache Tests

    func testLoadFeedUsesCache() async throws {
        mockCache.cachedValue = [Post(id: "p1", content: "Cached", creator: "u1")]
        mockAPIClient.feedResponse = .success([])  // Different from cache

        let posts = try await feedService.loadFeed(userId: "user-1", limit: 50, useCache: true)

        XCTAssertEqual(posts[0].id, "p1")  // ✅ Uses cache, not API
    }

    func testLoadFeedBypassesCache() async throws {
        mockCache.cachedValue = [Post(id: "p1", content: "Cached", creator: "u1")]
        let apiPosts = [Post(id: "p2", content: "Fresh", creator: "u2")]
        mockAPIClient.feedResponse = .success(apiPosts)

        let posts = try await feedService.loadFeed(userId: "user-1", limit: 50, useCache: false)

        XCTAssertEqual(posts[0].id, "p2")  // ✅ Uses API, not cache
    }
}
```

---

## Part 6: Performance Test Enhancements

### 6.1 Add Concurrent Load Benchmark

**File**: `/Users/proerror/Documents/nova/tests/performance_benchmark_test.rs`

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 10)]
#[ignore]  // Run with: cargo test --test performance_benchmark_test -- --ignored
async fn test_feed_api_concurrent_load() {
    let env = TestEnvironment::new().await;

    let start = Instant::now();
    let mut handles = vec![];

    // 100 concurrent users each making 10 requests
    for user_id in 0..100 {
        let api = FeedApiClient::new(&env.api_url);
        let handle = tokio::spawn(async move {
            for _ in 0..10 {
                let _ = api.get_feed(&format!("user_{}", user_id), 50).await;
            }
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.await.expect("task");
    }

    let elapsed = start.elapsed();
    let total_requests = 100 * 10;
    let throughput = total_requests as f64 / elapsed.as_secs_f64();

    println!("Concurrent load test:");
    println!("  Total requests: {}", total_requests);
    println!("  Duration: {:?}", elapsed);
    println!("  Throughput: {:.0} req/sec", throughput);

    // ✅ Verify throughput doesn't degrade
    assert!(throughput > 100.0, "Throughput should be > 100 req/sec");
}
```

---

### 6.2 Add Cache Hit Ratio Measurement

```rust
#[tokio::test]
async fn test_redis_cache_hit_ratio() {
    let cache = SubscriptionCache::new("redis://localhost", 60).await.expect("cache");
    let mut hit_count = 0;
    let mut miss_count = 0;
    let test_iterations = 1000;

    for i in 0..test_iterations {
        let key = format!("feed:{}", i % 100);  // 100 unique keys, 1000 requests

        if let Some(_) = cache.get_feed_item(&key).await.expect("get") {
            hit_count += 1;
        } else {
            miss_count += 1;
            let item = FeedItem { /* ... */ };
            cache.cache_feed_item(&key, &item).await.expect("cache");
        }
    }

    let hit_ratio = hit_count as f64 / test_iterations as f64;
    println!("Cache hit ratio: {:.2}%", hit_ratio * 100.0);

    // ✅ After warmup, hit ratio should be ~90%
    assert!(hit_ratio > 0.85, "Cache hit ratio should exceed 85%");
}
```

---

## Summary Table: Gap Locations

| Category | File | Line | Issue | Severity |
|----------|------|------|-------|----------|
| Panic | `rate_limit.rs` | 64 | `.expect("req_per_second")` | 🔴 P0 |
| Panic | `jwt.rs` | ~30 | `assert!(secret.len())` | 🔴 P0 |
| Panic | Kafka | ~88 | No error test | 🔴 P0 |
| DataLoader | `loaders.rs` | 80-94 | Stub implementation | 🔴 P0 |
| RateLimit | Various | N/A | No functional tests | 🔴 P1 |
| Concurrency | N/A | N/A | No race condition tests | 🔴 P1 |
| iOS | `AuthenticationManager` | N/A | No unit tests | 🔴 P1 |
| iOS | `FeedService` | N/A | No unit tests | 🔴 P1 |
| Security | N/A | N/A | No SQL injection test | 🟡 P2 |
| Security | N/A | N/A | No CORS test | 🟡 P2 |
| Performance | N/A | N/A | No concurrent load test | 🟡 P2 |

---

**Total Gaps Identified**: 65+ specific test scenarios
**Implementation Time**: 10-15 days for all P0 + P1
**Testing Framework Status**: Ready for implementation
