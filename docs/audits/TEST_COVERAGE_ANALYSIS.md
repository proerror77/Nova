# Nova Backend - Test Coverage Analysis Report

**Generated**: 2025-11-22
**Scope**: All backend services
**Risk Level**: MEDIUM-HIGH

---

## Section 1: Coverage Metrics

### 1.1 Quantitative Analysis

```
Total Test Functions:     ~1,657
Total Test LOC:          ~26,368
Test Count by Type:
├── Integration Tests:    ~1,075 (65%) ✅ Good distribution
├── Unit Tests:             ~410 (25%) ⚠️  Below ideal 40-50%
├── Performance Tests:       ~80 (5%)  🔴 Very low
├── Security Tests:          ~92 (5%)  🔴 Insufficient for attack surface

Test Density (LOC/Function): 15.9 lines/test ✅ Reasonable
```

### 1.2 Coverage by Service Tier

```
🟢 GOOD COVERAGE (70%+)
├── user-service         (~150+ tests, 3200+ LOC)
├── grpc-jwt-propagation (~10+ tests, 237 LOC)
└── identity-service     (Solid test fixtures)

🟡 MEDIUM COVERAGE (40-70%)
├── content-service      (~10+ tests, 750+ LOC)
├── graphql-gateway      (~45+ tests, 1200+ LOC)
└── notification-service (~25+ tests, established patterns)

🔴 CRITICAL GAPS (<40%)
├── feed-service         (6 tests, 200 LOC) - Uses string literal checks
├── social-service       (1 test, 70 LOC)   - Only boundary checks
└── chat-service         (0 dedicated tests) - Missing entirely
```

---

## Section 2: Deep Dive - Critical Issues

### 2.1 BLOCKER: Feed Service Test Architecture

**Location**: `/Users/proerror/Documents/nova/backend/feed-service/tests/feed_integration_test.rs`

**Current Implementation** (Lines 18-46):
```rust
#[actix_web::test]
async fn test_feed_endpoint_returns_actual_posts() {
    let source = include_str!("../src/handlers/feed.rs");

    assert!(
        !source.contains("let posts: Vec<Uuid> = vec![];"),
        "Placeholder should be replaced"
    );

    assert!(
        source.contains("get_posts_by_author"),
        "Should call get_posts_by_author"
    );
}
```

**Why This Is Problematic**:
1. Tests code existence, not behavior
2. Refactoring changes = test failures (brittle)
3. No error handling validation
4. No gRPC mocking
5. No actual HTTP requests tested

**Risk**:
- Pagination may silently break
- Error handling may fail in production
- Cache invalidation race conditions undetected

**Fix Required**:
```rust
// ✅ CORRECT APPROACH
#[actix_web::test]
async fn test_feed_endpoint_pagination() {
    let content_client = MockContentClient::new()
        .expect_get_posts_by_author(user_1, vec![post_1, post_2])
        .expect_get_posts_by_author(user_2, vec![post_3, post_4]);

    let handler = FeedHandler::with_clients(
        Box::new(content_client),
        Box::new(MockGraphClient::new()),
    );

    let response = handler.get_feed(
        user_id,
        limit=20,
        cursor=None
    ).await.unwrap();

    assert_eq!(response.posts.len(), 4);
    assert!(response.has_more); // More posts available
    assert!(!response.next_cursor.is_empty());
}
```

---

### 2.2 BLOCKER: Social-Service Zero Integration Tests

**Location**: `/Users/proerror/Documents/nova/backend/social-service/tests/`

**Current State**:
```
total 8
-rw-r--r-- 68 follow_boundary.rs (⚠️  ONLY FILE)
```

**Test Content** (Lines 28-68):
```rust
#[test]
fn follow_writes_only_from_social_or_graph_service() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let backend_root = manifest.parent().unwrap().to_path_buf();

    let allowed = [
        "backend/social-service/src/workers/graph_sync.rs",
        "backend/social-service/src/services/follow.rs",
        "backend/graph-service/src/grpc/server.rs",
        "backend/graph-service/src/repository/graph_repository.rs",
    ];

    // Check that no other files modify follow state
    for file in collect_rs_files(&backend_root) {
        if file_contains(&file, "CreateFollowRequest") {
            // Flag as violation
        }
    }
}
```

**What's Missing**:
1. ❌ No actual follow/unfollow tests
2. ❌ No graph-service integration
3. ❌ No concurrent update tests
4. ❌ No error handling tests
5. ❌ No block list cascade tests
6. ❌ No Kafka event publishing tests

**Risk**:
- Follow operations may corrupt graph state
- Unfollow may not trigger cache invalidation
- Race conditions undetected
- Production failures likely

**Expected Structure**:
```
social-service/tests/
├── integration/
│   ├── follow_operations_test.rs          (20+ tests)
│   ├── follow_with_blocks_test.rs         (8+ tests)
│   ├── graph_sync_test.rs                 (12+ tests)
│   ├── concurrent_updates_test.rs         (10+ tests)
│   └── kafka_events_test.rs               (8+ tests)
├── unit/
│   ├── validation_test.rs
│   └── business_logic_test.rs
└── boundary.rs (keep existing)
```

**Estimated Effort**: 250-350 LOC, 2-3 days

---

### 2.3 BLOCKER: Chat Authorization - Zero Tests

**Location**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/rest_api/chat.rs`

**Code Analysis** (Lines 13-69):

```rust
#[get("/api/v2/chat/conversations")]
pub async fn get_conversations(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<ConversationQuery>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };
    // ⚠️ ONLY checks authentication, not authorization
    // ⚠️ Missing: Does user own these conversations?

    let req = ListConversationsRequest {
        user_id: user_id.clone(),  // Trusts user_id from JWT
        // ⚠️ Missing: Validation that user can see these conversations
    };
}

#[post("/api/v2/chat/messages")]
pub async fn send_chat_message(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    payload: web::Json<SendMessageBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };
    // ⚠️ BLOCKER: Doesn't verify user is member of conversation
    // ⚠️ What if conversation_id in payload != user's conversation?

    let req: SendMessageRequest = payload.0.clone().into();
    // No validation that user_id matches conversation members
}
```

**Security Gap**:
```
Attack Vector 1: Unauthorized Message Send
─────────────────────────────────────────
User A (JWT valid)
  ↓
POST /api/v2/chat/messages {
  conversation_id: "uuid_of_B_and_C_conversation",
  content: "hacked message"
}
  ↓
⚠️ No check: Is User A member of this conversation?
  ↓
Result: User A successfully sends to private conversation!
```

**Missing Test Coverage**:
```rust
// ❌ NOT TESTED - Should fail
test_user_a_sends_message_to_b_c_conversation() -> 403 Forbidden

// ❌ NOT TESTED - Should fail
test_user_a_lists_b_conversations() -> Only A's conversations returned

// ❌ NOT TESTED - Should fail
test_user_a_reads_b_c_messages() -> 403 Forbidden

// ❌ NOT TESTED - Should succeed
test_user_a_reads_own_conversation() -> All messages returned
```

**Estimated Effort**: 200-300 LOC, 1-2 days

---

### 2.4 P1: Feed N+1 Query Pattern - No Performance Tests

**Location**: `/Users/proerror/Documents/nova/backend/feed-service/src/handlers/feed.rs`

**Concern**: Feed aggregation loops through followed users

```rust
pub async fn get_feed(
    user_id: Uuid,
    limit: usize,
) -> Result<FeedResponse> {
    // Get list of followed users (1 query)
    let followed = graph_client.get_followers(user_id).await?;

    // For each user, fetch their posts (N additional queries!)
    for user_id in followed_user_ids.iter() {
        let posts = content_client.get_posts_by_author(user_id).await?;
        // N+1 pattern: 1 + followed_users.len() queries total
    }
}
```

**Risk at Scale**:
```
Followed Users: 1          Queries: 2     Time: ~10ms ✅
Followed Users: 10         Queries: 11    Time: ~100ms ✅
Followed Users: 100        Queries: 101   Time: ~1000ms ⚠️
Followed Users: 1000       Queries: 1001  Time: ~10000ms 🔴 TIMEOUT
```

**Missing Tests**:
```rust
// ❌ NOT TESTED
#[tokio::test]
async fn test_feed_with_1000_followed_users() {
    // Should complete in <5 seconds
    // Should not timeout
    // Should gracefully degrade if some users fail
}

// ❌ NOT TESTED
#[tokio::test]
async fn test_feed_concurrent_user_requests() {
    // Multiple users requesting feed simultaneously
    // Should not exceed Redis connection pool
    // Should not exceed DB connection pool
}

// ❌ NOT TESTED
#[tokio::test]
async fn test_feed_redis_cache_contention() {
    // 100 concurrent requests to same user's feed
    // Should not cause cache key conflicts
    // Should maintain cache hit rate >80%
}
```

**Mitigation**:
1. Batch fetch posts (10 users per batch) ✅
2. Implement Redis caching ✅
3. Add query count monitoring 🔴 MISSING TEST
4. Add latency SLA enforcement 🔴 MISSING TEST

**Estimated Effort**: 150-250 LOC, 1-2 days

---

## Section 3: Security Test Gap Analysis

### 3.1 Authorization Coverage

```
Endpoint                          Tested?   Gap Level
──────────────────────────────────────────────────────
GET /api/v2/feed                  🟡 Partial   Medium
POST /api/v2/chat/messages        🔴 None      CRITICAL
GET /api/v2/chat/conversations    🔴 None      CRITICAL
GET /api/v2/chat/messages         🔴 None      CRITICAL
POST /api/v2/follows              🟡 Partial   High
DELETE /api/v2/follows            🟡 Partial   High
GET /api/v2/user/{id}             🟢 Full      ✅

Total Authorization Tests: 18
Percentage of Critical Paths: 18 / (50+ endpoints) = 36%
```

### 3.2 Input Validation Tests

```
Category                 Count   Expected   Gap
─────────────────────────────────────────────
SQL Injection Tests        5      8+        Medium
JWT Tampering Tests        8      12+       Low-Medium
XSS/Injection Tests        3      10+       High
Rate Limit Tests           4      15+       High
Payload Size Limits        0      5+        CRITICAL
Protocol Buffer Invalid    0      8+        CRITICAL
```

### 3.3 Error Handling Tests

```
Error Type                 Tested?   Notes
──────────────────────────────────────────────
Timeout Scenarios          🟡 Partial  Feed service missing
Connection Pool Exhaustion 🟡 Partial  DB pool has tests
Circuit Breaker Fallback   🔴 None     Missing
Database Unavailable       🟡 Partial  Only user-service
gRPC Unavailable           🔴 None     Feed service missing
Partial Service Failure    🔴 None     Critical for resilience
```

---

## Section 4: Test Pyramid Analysis

### 4.1 Current Distribution

```
           E2E Tests (0%)
           [                ]
        Integration Tests (65%)
        [     ███████████     ]
     Unit Tests (25%)
     [  ██████  ]
Load Tests (5%) [  ]  Security Tests (5%) [  ]
```

**Problems**:
1. Unit tests are 40% below ideal (should be 50-60%)
2. E2E tests missing entirely
3. Load/Security tests scattered, not formalized
4. No clear test responsibilities per layer

### 4.2 Recommended Rebalancing

```
New Target Distribution:
─────────────────────

Unit Tests: 60% (expand from 25%)
├── Models (data validation)
├── Handlers (request processing)
├── Services (business logic)
└── Utils (helper functions)

Integration Tests: 30% (reduce from 65%)
├── gRPC service boundaries
├── Database interactions
├── Cache operations
├── Event publishing
└── Authorization boundaries

E2E Tests: 10% (new)
├── API contract validation
├── Full user journeys
├── Cross-service workflows
└── Performance baselines
```

---

## Section 5: Test Quality Metrics

### 5.1 Code Coverage Estimate

```
Critical Paths:          <30%  🔴 TOO LOW
Happy Path:              70%   🟡 ACCEPTABLE
Error Handling:          40%   🟡 NEEDS WORK
Authorization:           35%   🔴 CRITICAL
Performance Paths:       15%   🔴 CRITICAL

Overall Estimate:        ~52%  🟡 MEDIUM
```

### 5.2 Test Flakiness Indicators

```
Pattern                           Likelihood   Severity
────────────────────────────────────────────────────────
Hardcoded timeouts               High ⚠️       Medium
Include_str! tests               High ⚠️       High
Time-dependent assertions        Medium ⚠️     Medium
Shared test database             Low ✅        Low
Mock sync issues                 Medium ⚠️     Medium
Concurrent test conflicts        Low ✅        Low

Estimated Flakiness Rate: ~5-8% (moderate)
```

### 5.3 Mock Usage Pattern Quality

```
Pattern                          Files   Quality
───────────────────────────────────────────────
Generic mock clients             2       🟢 Good
Proto-specific mocks             5       🟢 Good
Ad-hoc mocking                   8       🟡 Fair
include_str! checks              3       🔴 Bad
No mocking (real services)       2       🔴 Bad

Mock Maturity: MEDIUM (improving)
```

---

## Section 6: Test Organization Quality

### 6.1 Directory Structure Assessment

```
✅ GOOD PATTERNS
├── service/tests/common/          (Shared fixtures)
├── service/tests/integration/     (Clear intent)
└── tests/fixtures/                (Reusable test data)

⚠️  INCONSISTENT
├── Some services use top-level tests/
├── Some services use src/tests
└── No standard directory naming

🔴 PROBLEMS
├── Chat service has zero test directory
├── Social-service missing integration/ subdir
└── No e2e/ directory anywhere
```

### 6.2 Test Documentation

```
Service              Documented?  README   Clarity
────────────────────────────────────────────────
user-service         🟢 Yes       Yes      Clear
content-service      🟡 Partial   No       Moderate
feed-service         🔴 No        No       Confusing
social-service       🔴 No        No       Missing
graphql-gateway      🟡 Yes       Partial  Good
```

---

## Section 7: Dependency Testing Coverage

### 7.1 Service Dependency Matrix

```
Service            Dependencies    Direct Tests    Gap
──────────────────────────────────────────────────
feed-service       5 (content,     🟡 Limited      High
                    graph,
                    analytics,
                    redis,
                    cache-inv)

social-service     4 (graph,       🔴 Missing      Critical
                    content,
                    cache-inv,
                    kafka)

chat-service       3 (user,        🔴 Missing      Critical
                    identity,
                    realtime)

graphql-gateway    12+ (all)       🟡 Partial      High
```

### 7.2 Integration Points Not Tested

```
Feed + Graph        🔴 Missing
├── get_followers() -> get_posts_by_author()

Feed + Cache        🟡 Partial
├── Cache miss -> DB fetch -> Cache write

Social + Graph      🔴 Missing
├── follow request -> graph edge creation -> cache invalidation

Chat + Identity    🔴 Missing
├── send_message -> user validation -> event publishing

Feed + Analytics   🔴 Missing
├── Impressions -> ClickHouse writes under load
```

---

## Section 8: Performance Test Baseline

### 8.1 Load Test Infrastructure

**Status**: Exists but unused
- **File**: `/backend/tests/phase1_load_stress_tests.rs`
- **LOC**: 451
- **Test Functions**: 0 (it's a template)

```rust
// Current state: Infrastructure only, no actual tests
async fn run_load_test<F, Fut>(
    config: LoadTestConfig,  // Has config
    request_fn: F,            // Has harness
) -> LoadTestMetrics {
    // Good metrics collection
    // But no service tests use this!
}
```

### 8.2 Missing Performance Baselines

```
Operation                      Target SLA    Current Test   Status
─────────────────────────────────────────────────────────────────
Get feed (100 posts)           <500ms        ❌ None        🔴
List conversations             <200ms        ❌ None        🔴
Send message                   <100ms        ❌ None        🔴
Create follow                  <50ms         ❌ None        🔴
Query 1000 users' posts        <5s           ❌ None        🔴
Concurrent user requests (100) <2s each      ❌ None        🔴
```

---

## Section 9: Recommendations Priority Matrix

```
                    Effort (Days)
         Low (1-2)   Medium (2-4)   High (4+)
Impact
───────────────────────────────────────────────────
Critical  P0-1       P0-2           P0-3
          Chat Auth  Social Tests   Feed Arch
          Authz      Feed Conv
          (5 tests)  (8 tests)      (12 tests)

High      P1-1       P1-2           P1-3
          Perf Tests Cross-Svc      E2E Suite
          (3 tests)  Auth (4 tests)

Medium    P2-1       P2-2
          Utils      Regression
          Tests      Dashboard
```

### Priority List (Ranked)

```
1. 🔴 Chat Authorization Tests              1-2 days   P0-BLOCKER
2. 🔴 Social-Service Integration Tests      2-3 days   P0-BLOCKER
3. 🔴 Feed Tests Conversion                 1-2 days   P0-BLOCKER
4. 🟠 Feed Performance N+1                  1-2 days   P1-HIGH
5. 🟠 Cross-Service Authorization           1-2 days   P1-HIGH
6. 🟠 Error Path Coverage                   2-3 days   P1-HIGH
7. 🟡 Performance Regression Suite          2-3 days   P2-MEDIUM
8. 🟡 Chaos Engineering Tests               2-3 days   P2-MEDIUM
9. 🟡 E2E API Contract Tests                2-3 days   P2-MEDIUM
```

---

## Section 10: Quick Wins (Can Complete Today)

```
1. Add 2 authorization tests to chat endpoints      (30 min)
   - send_message_to_unauthorized_conversation()
   - list_conversations_filters_by_user()

2. Add 3 follow integration test stubs            (30 min)
   - test_follow_operation_integration()
   - test_unfollow_removes_edge()
   - test_follow_prevents_self_follow()

3. Replace 1 string-literal test with mock       (30 min)
   - Convert test_feed_pagination_logic()

4. Document test gaps in AGENTS.md               (30 min)
   - Add "Testing Requirements" section
   - Link to TESTING_STRATEGY.md

5. Create MockChatClient template                (30 min)
   - Reusable for chat authorization tests
```

---

## Conclusion

**Current State**: Nova has strong integration test foundation (65% of tests) but critical security and performance gaps.

**Blocker Items**: 3 critical gaps preventing production release
- Chat authorization (1-2 days to fix)
- Social-service integration (2-3 days to fix)
- Feed test architecture (1-2 days to fix)

**Overall Risk**: MEDIUM-HIGH → Can be reduced to LOW within 1 week.

**Recommendation**: Implement P0 blockers before v1.0 release. This will be 4-7 days of focused effort.
