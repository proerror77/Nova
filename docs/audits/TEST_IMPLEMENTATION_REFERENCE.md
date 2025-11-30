# Test Implementation Reference Guide

**Quick Reference**: File locations, test patterns, and implementation examples
**Status**: P0/P1 implementation guide

---

## Part 1: Where to Add Tests

### Current Test Files (Reference)

```
backend/
├── feed-service/tests/
│   ├── common/
│   │   ├── mock_auth_client.rs       ✅ REFERENCE PATTERN
│   │   └── mod.rs
│   ├── feed_integration_test.rs      🔴 NEEDS REPLACEMENT
│   ├── boundary.rs                   🔴 NEEDS EXPANSION
│   └── feed_cleaner_test.rs
│
├── social-service/tests/
│   └── follow_boundary.rs            🔴 NEEDS 20+ MORE TESTS
│       └── Create: integration/
│           ├── follow_operations_test.rs
│           ├── follow_with_blocks_test.rs
│           ├── concurrent_updates_test.rs
│           └── kafka_events_test.rs
│
├── graphql-gateway/tests/
│   ├── auth_middleware_tests.rs      ✅ REFERENCE PATTERN
│   ├── authentication_integration_tests.rs  ✅ GOOD EXAMPLE
│   ├── security_auth_tests.rs        ✅ GOOD EXAMPLE
│   ├── security_integration_tests.rs ✅ GOOD EXAMPLE
│   ├── security_logging_tests.rs     ✅ GOOD EXAMPLE
│   └── chat_authorization_tests.rs   🔴 NEEDS CREATION
│
├── libs/grpc-jwt-propagation/tests/
│   └── integration_tests.rs          ✅ EXCELLENT EXAMPLE
│       └── Study for authorization patterns
│
└── user-service/tests/
    ├── common/fixtures.rs           ✅ REFERENCE PATTERN
    ├── integration/
    │   ├── security_test.rs         ✅ GOOD PATTERN
    │   ├── circuit_breaker_test.rs  ✅ ERROR HANDLING PATTERN
    │   └── ... (many other good examples)
    └── 2fa_test.rs
```

---

## Part 2: Key Files to Study (Copy Patterns From)

### Pattern 1: Mock Client Setup
**Source**: `/Users/proerror/Documents/nova/backend/feed-service/tests/common/mock_auth_client.rs`

```rust
// ✅ PATTERN TO COPY
pub struct MockAuthClient {
    expected_token: String,
    expected_user_id: Option<Uuid>,
}

impl MockAuthClient {
    pub fn new() -> Self {
        Self {
            expected_token: "valid_token".to_string(),
            expected_user_id: Some(Uuid::new_v4()),
        }
    }

    pub fn with_token(mut self, token: String) -> Self {
        self.expected_token = token;
        self
    }
}

// USE IN TESTS:
let auth_client = MockAuthClient::new()
    .with_token("invalid_token".to_string());
```

### Pattern 2: Authorization Test
**Source**: `/Users/proerror/Documents/nova/backend/libs/grpc-jwt-propagation/tests/integration_tests.rs`

```rust
// ✅ PATTERN TO COPY
#[tokio::test]
async fn test_ownership_check_failure() {
    let user_id = Uuid::new_v4();
    let other_user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id, "test@example.com", "testuser"
    )?;

    let request = simulate_grpc_flow(&token)?;

    // Check ownership with DIFFERENT user ID
    let result = request.require_ownership(&other_user_id);

    assert!(result.is_err());
    assert_eq!(result.unwrap_err().code(), tonic::Code::PermissionDenied);
}
```

### Pattern 3: gRPC Integration Test
**Source**: `/Users/proerror/Documents/nova/backend/graphql-gateway/tests/authentication_integration_tests.rs`

```rust
// ✅ PATTERN TO COPY
#[actix_web::test]
async fn test_graphql_endpoint_requires_auth() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new(SECRET.to_string()))
            .service(graphql),
    )
    .await;

    // Missing JWT
    let req = test::TestRequest::post()
        .uri("/graphql")
        .set_json(&GraphQLRequest { query: "..." })
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 401);  // Unauthorized
}
```

### Pattern 4: Error Handling Test
**Source**: `/Users/proerror/Documents/nova/backend/user-service/tests/integration/circuit_breaker_test.rs`

```rust
// ✅ PATTERN TO COPY
#[tokio::test]
async fn test_circuit_breaker_opens_after_threshold() {
    let mut mock_db = MockDatabase::new();

    // Fail 5 requests in a row
    mock_db.expect_query()
        .times(5)
        .returning(|| Err(DatabaseError::Connection));

    let service = UserService::new(mock_db);

    // Requests 1-4: Return error
    for _ in 0..4 {
        service.get_user(user_id).await
            .expect_err("Should fail");
    }

    // Request 5: Circuit breaker opens
    let result = service.get_user(user_id).await;
    assert!(result.is_err());
    assert_eq!(result.unwrap_err(), "Circuit breaker open");
}
```

### Pattern 5: Security Test
**Source**: `/Users/proerror/Documents/nova/backend/graphql-gateway/tests/security_auth_tests.rs`

```rust
// ✅ PATTERN TO COPY - JWT Secret Validation
#[test]
#[should_panic(expected = "JWT secret too short")]
fn test_jwt_middleware_rejects_weak_secret_too_short() {
    let _ = JwtMiddleware::new("weak".to_string());  // Should panic!
}

#[test]
fn test_jwt_middleware_accepts_32_byte_secret() {
    let secret = "a".repeat(32);
    let middleware = JwtMiddleware::new(secret);
    assert!(middleware.is_ok());  // ✅ Passes
}
```

---

## Part 3: Test Implementation Checklist

### For Chat Authorization Tests (P0-1)

```
File: backend/graphql-gateway/tests/chat_authorization_tests.rs
Effort: 1-2 days | LOC: 250-300

Required Tests:
☐ test_send_message_requires_conversation_membership()
☐ test_list_conversations_filters_by_user()
☐ test_get_messages_validates_conversation_access()
☐ test_send_message_to_unauthorized_conversation_fails()
☐ test_conversation_members_only_can_modify()
☐ test_block_list_prevents_messaging()
☐ test_group_chat_permissions_validated()

Mock Setup:
☐ MockChatClient with expect_* methods
☐ Test user with JWT token generation
☐ Conversation fixtures (private, group)
☐ Member/non-member scenarios
```

### For Social-Service Integration Tests (P0-2)

```
File: backend/social-service/tests/integration/follow_operations_test.rs
Effort: 2-3 days | LOC: 350-450

Required Tests:
☐ test_follow_creates_graph_edge()
☐ test_follow_prevents_self_follow()
☐ test_follow_prevents_duplicate_follows()
☐ test_unfollow_removes_graph_edge()
☐ test_unfollow_with_blocking()
☐ test_follow_triggers_cache_invalidation()
☐ test_follow_publishes_kafka_event()
☐ test_concurrent_follow_operations()
☐ test_follow_with_nonexistent_user_fails()
☐ test_follow_respects_privacy_settings()

Mock Setup:
☐ MockDatabase with expect_* methods
☐ MockGraphClient for edge operations
☐ MockKafkaProducer for event publishing
☐ MockCache for invalidation testing
```

### For Feed Test Conversion (P0-3)

```
File: backend/feed-service/tests/feed_integration_test.rs (REPLACE)
Effort: 1-2 days | LOC: 400-500

Required Tests:
☐ test_feed_respects_limit_parameter()
☐ test_feed_pagination_with_cursor()
☐ test_feed_handles_partial_failure_gracefully()
☐ test_feed_with_large_followed_list()
☐ test_feed_returns_ranked_posts()
☐ test_feed_caches_aggregated_results()
☐ test_feed_timeout_on_slow_service()
☐ test_feed_graceful_degradation_redis_down()
☐ test_feed_pagination_edge_cases()
☐ test_feed_concurrent_requests()

Mock Setup:
☐ MockContentClient with post data
☐ MockGraphClient with follow relationships
☐ MockRedisClient for cache operations
☐ MockAnalyticsClient for impression tracking
```

---

## Part 4: Quick Reference - Import/Setup Pattern

### Standard Test Setup (Copy Template)

```rust
// File: backend/YOUR_SERVICE/tests/integration/YOUR_TESTS.rs

use tokio::test;
use uuid::Uuid;
use your_service::{Handler, Request, Response};

// Import mocks
mod common {
    pub use super::super::super::tests::common::*;
}

// Re-export frequently used types
use common::*;

#[tokio::test]
async fn test_your_feature_here() {
    // 1. Setup
    let mock_client = MockClient::new();
    let handler = YourHandler::new(mock_client);

    // 2. Execute
    let req = YourRequest { /* ... */ };
    let result = handler.process(req).await;

    // 3. Assert
    assert!(result.is_ok());
    let response = result.unwrap();
    assert_eq!(response.status, 200);
}
```

### Mock Client Template (Copy This)

```rust
// backend/YOUR_SERVICE/tests/common/mock_YOUR_client.rs

pub struct Mock<YourClient> {
    expectations: Vec<(Matcher, Box<dyn Fn() -> Result<Response>>)>,
}

impl Mock<YourClient> {
    pub fn new() -> Self {
        Self { expectations: Vec::new() }
    }

    pub fn expect_operation(&mut self) -> ExpectationBuilder {
        ExpectationBuilder::new(self)
    }

    pub async fn operation(&self, request: Request) -> Result<Response> {
        // Match expectations and return
        for (matcher, responder) in &self.expectations {
            if matcher.matches(&request) {
                return responder();
            }
        }
        Err("No matching expectation".into())
    }
}
```

---

## Part 5: Running Tests Locally

### Run All Tests
```bash
cd backend
cargo test
```

### Run Specific Service Tests
```bash
cd backend/chat-service
cargo test

# Or specific test
cargo test test_send_message_requires_conversation_membership
```

### Run With Output
```bash
cargo test -- --nocapture
cargo test -- --test-threads=1  # Sequential
cargo test -- --ignored         # Only #[ignore] tests
```

### Generate Coverage (if tool installed)
```bash
# Install: cargo install tarpaulin
cargo tarpaulin --out Html
```

---

## Part 6: Common Test Errors & Solutions

### Error 1: Mock Not Matching
```
Error: No matching expectation found

Solution:
// Ensure matcher conditions are correct
mock.expect_operation()
    .with(
        eq(expected_arg),  // Exact match required
        predicate::in_set!(allowed_values),  // Or predicate
    )
```

### Error 2: Async/Await Issues
```
Error: `test_your_feature` future does not implement `Send`

Solution:
// Use #[tokio::test] not #[test]
#[tokio::test]  // ✅ Correct
async fn test_your_feature() { }

#[test]         // ❌ Wrong
async fn test_your_feature() { }
```

### Error 3: JWT Token Generation
```
Error: Failed to initialize test keys

Solution:
// Call init_test_keys() once
#[tokio::test]
async fn test_something() {
    init_test_keys();  // Add this line
    let token = crypto_core::jwt::generate_access_token(...)?;
}
```

### Error 4: Database Cleanup
```
Error: Unique constraint violation (test data not cleaned)

Solution:
// Cleanup after each test
#[tokio::test]
async fn test_something() {
    let result = operation().await;
    cleanup_test_data().await;  // Always cleanup
}
```

---

## Part 7: Code Review Checklist for Test PRs

### For Chat Authorization PR
```
☐ Authorization logic tested (not just auth headers)
☐ Conversation ownership validated
☐ Both member and non-member scenarios tested
☐ No hardcoded test data in assertions
☐ Proper mock setup/teardown
☐ Error messages clear
☐ Tests are independent (order-independent)
☐ No flaky timing dependencies
☐ Documentation comments present
☐ Naming follows pattern test_*_success/failure
```

### For Social-Service PR
```
☐ gRPC integration tested (not just unit)
☐ Graph service mock responses realistic
☐ Kafka event publishing validated
☐ Cache invalidation tested
☐ Concurrent operations handled
☐ Edge cases covered (self-follow, duplicates)
☐ Error paths exercised
☐ Database mock properly configured
☐ Test database cleanup working
☐ Integration points validated
```

### For Feed Test Conversion PR
```
☐ All old tests replaced with functional ones
☐ include_str!() removed entirely
☐ gRPC mocks working
☐ Pagination tested with multiple pages
☐ Error handling for service failures
☐ Cache operations tested
☐ Timeout scenarios covered
☐ Partial failure (some users) handled
☐ Performance baseline established
☐ No regression in test execution time
```

---

## Part 8: Performance Baseline Setup

### Add to Phase 1 Load Tests

```rust
// File: backend/tests/phase1_load_stress_tests.rs

#[tokio::test]
async fn test_feed_aggregation_performance_1000_users() {
    let config = LoadTestConfig {
        concurrency: 10,
        total_requests: 100,
        rate_limit: None,
        duration: Duration::from_secs(60),
    };

    let metrics = run_load_test(config, || async {
        let user_id = create_test_user();
        let start = Instant::now();

        feed_handler
            .get_feed(user_id, limit=20)
            .await?;

        Ok(start.elapsed())
    }).await;

    // Assert within SLA
    assert!(metrics.avg_latency < Duration::from_millis(500));
    assert!(metrics.p99_latency < Duration::from_secs(2));

    print_load_test_report("Feed Aggregation (1000 users)", &metrics);
}
```

---

## Part 9: Git Workflow for Test PRs

### Branch Naming
```bash
git checkout -b test/p0-chat-authorization
git checkout -b test/p0-social-integration
git checkout -b test/p0-feed-conversion
```

### Commit Message Format
```
test(chat): Add conversation ownership validation tests

- test_send_message_requires_conversation_membership()
- test_list_conversations_filters_by_user()
- test_get_messages_validates_conversation_access()

Covers BLOCKER: Authorization bypass in chat endpoints
Fixes: #123
```

### PR Template
```markdown
## What This PR Tests
Chat authorization gaps (conversation ownership)

## Tests Added
- 7 new authorization tests
- 250 LOC of test code
- MockChatClient pattern reusable

## How to Test
cargo test test_send_message_requires_conversation_membership

## Related Issues
Fixes #BLOCKER-123
Relates to TESTING_STRATEGY.md P0-1
```

---

## Part 10: Documentation Template

### Test File Header
```rust
//! Chat Authorization Tests
//!
//! Tests the authorization requirements for chat operations:
//! - Users can only send messages in conversations they're members of
//! - Users can only read conversations they're members of
//! - Conversation ownership is validated before modifications
//!
//! OWASP A01:2021 - Broken Access Control
//! Coverage: graphql-gateway/src/rest_api/chat.rs
```

### Test Function Documentation
```rust
/// Verify that User A cannot send messages to User B's private conversation
///
/// This test validates the critical authorization boundary: sending a message
/// requires proving membership in the target conversation.
///
/// Attack Vector: User A has valid JWT but conversation_id belongs to User B
/// Expected Behavior: Request rejected with 403 Forbidden
/// Actual Without Fix: Message sent successfully (SECURITY BUG)
#[tokio::test]
async fn test_send_message_requires_conversation_membership() {
    // ...
}
```

---

## Summary: P0 Implementation Timeline

```
DAY 1-2:  Chat Authorization Tests
├─ Create: graphql-gateway/tests/chat_authorization_tests.rs
├─ Add: 5-7 test functions
├─ Mock: MockChatClient with expectations
└─ Review & Merge

DAY 2-3:  Social-Service Integration
├─ Create: social-service/tests/integration/ directory
├─ Create: follow_operations_test.rs
├─ Add: 20+ test functions
├─ Setup: MockDatabase, MockGraphClient, MockKafka
└─ Review & Merge

DAY 3-4:  Feed Test Conversion
├─ Backup: Existing feed_integration_test.rs
├─ Create: New functional test suite
├─ Replace: All include_str!() tests
├─ Add: Error handling, pagination, performance
└─ Review & Merge

DAY 5:    Validation & Documentation
├─ Run: Full test suite
├─ Verify: All P0 tests passing
├─ Update: TESTING_STRATEGY.md with results
└─ Mark: P0 complete, move to P1
```

---

**Last Updated**: 2025-11-22
**Status**: Ready for Implementation
