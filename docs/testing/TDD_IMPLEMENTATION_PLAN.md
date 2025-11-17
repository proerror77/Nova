# TDD Implementation Plan: PR #59 Testing

**Goal**: Implement 129 missing tests using Test-Driven Development (Red-Green-Refactor)
**Timeline**: 2-3 weeks
**Team Size**: 1-2 engineers
**Success Metric**: 60%+ code coverage, all P0 tests passing

---

## Phase 1: Foundation (Week 1) - 55 Tests

### Sprint 1.1: Authentication (Mon-Tue, 8 tests)

#### Objective: Enforce JWT authentication on all endpoints

**TDD Cycle 1: Endpoint Requires Token**

```
RED (2 hours)
├─ Write test: test_graphql_requires_auth_header
├─ Test fails: endpoint returns 200 (no auth check)
└─ Run: cargo test -- --nocapture

GREEN (1 hour)
├─ Add middleware: JwtAuthMiddleware::new()
├─ Add to App: .wrap(middleware)
└─ Run test: ✅ PASSES

REFACTOR (0.5 hours)
├─ Extract middleware config to separate module
├─ Add documentation
└─ Verify test still passes
```

**TDD Cycle 2: Malformed Token Rejected**

```
RED: test_malformed_token_returns_401
├─ Token: "invalid-xyz"
├─ Expected: 401 response
└─ Actual: 200 (middleware not validating)

GREEN:
├─ Add JWT decoding to middleware
├─ Validate signature
└─ Return 401 if invalid

REFACTOR:
├─ Extract JWT validation to crypto-core
├─ Add error type
└─ Test passes with cleaner code
```

**Repeat for:**
- test_expired_token_returns_401
- test_token_signature_validation
- test_missing_authorization_header
- test_bearer_prefix_required
- test_token_claims_extracted_to_context
- test_multiple_auth_attempts

**Metrics After Sprint 1.1:**
- Tests written: 8
- Tests passing: 8
- Cycles completed: 8
- Average cycle time: 3.5 hours
- Code added: ~200 lines (middleware + validation)

---

### Sprint 1.2: Authorization (Wed, 20 tests)

#### Objective: Verify users can only modify their own resources

**TDD Cycle 1: Cannot Update Other User's Post**

```
RED (2 hours):
├─ Setup:
│  ├─ Alice creates post (post_id = "alice-1")
│  ├─ Bob logged in (user_id = "bob")
│  └─ Bob attempts: updatePost(id: "alice-1", content: "HACKED")
├─ Expected: 403 Forbidden
└─ Actual: 200 OK (no permission check)

GREEN (1.5 hours):
├─ In resolver: check post.user_id == current_user_id
├─ If not equal: return Err(Unauthorized)
└─ Test passes ✅

REFACTOR (0.5 hours):
├─ Extract: fn require_ownership(owner, user) -> Result<()>
├─ Reuse in: update_post, delete_post
└─ All tests still pass
```

**Repeat pattern for 19 more scenarios:**
- test_cannot_delete_other_user_post
- test_cannot_update_other_user_profile
- test_cannot_access_private_profile_fields
- test_follow_user_permission
- test_block_user_permission
- test_create_post_requires_auth
- test_create_post_authorization
- ... (total 20 variants covering all mutations)

**Implementation Pattern for Each Test:**

1. **Setup** (3 lines)
   ```rust
   let alice = register_user("alice@example.com").await;
   let bob = register_user("bob@example.com").await;
   let post_id = create_post_as(&alice, "Alice's post").await;
   ```

2. **Action** (2 lines)
   ```rust
   let result = update_post_as(&bob, &post_id, "HACKED").await;
   ```

3. **Assert** (1 line)
   ```rust
   assert_eq!(result.status, 403);
   ```

**Metrics After Sprint 1.2:**
- Tests written: 20
- Tests passing: 20 (after implementation)
- Average cycle time: 2 hours/test (pattern repetition speeds up)
- Code added: ~150 lines (permission check logic)

---

### Sprint 1.3: Input Validation (Thu, 10 tests)

#### Objective: Validate all user inputs

**TDD Cycle 1: Email Format Validation**

```
RED (1 hour):
├─ Test cases:
│  ├─ "notanemail" → 400
│  ├─ "@example.com" → 400
│  ├─ "user@" → 400
│  └─ "valid@example.com" → 200
└─ Actual: All return 200 (no validation)

GREEN (1 hour):
├─ Add validation: email.contains('@') && email.contains('.')
├─ Return 400 if invalid
└─ All 4 tests pass ✅

REFACTOR (0.5 hours):
├─ Use regex for email validation
├─ Add detailed error messages
└─ Reusable in all auth endpoints
```

**Repeat for:**
- Password strength validation (8 test cases)
  - Too short, no uppercase, no lowercase, no numbers, no special chars
  - Valid password formats
- Post content length (2 test cases)
  - Empty content → 400
  - > 5000 chars → 400
  - Valid content → 200

**Test Template for Validation:**

```rust
#[tokio::test]
async fn test_{field}_validation() {
    let invalid_cases = vec![
        ("case1", "reason1"),
        ("case2", "reason2"),
    ];

    for (input, reason) in invalid_cases {
        let result = make_request(input).await;
        assert_eq!(result.status, 400, "Failed for: {}", reason);
    }

    let valid_case = "valid_input";
    let result = make_request(valid_case).await;
    assert_eq!(result.status, 200);
}
```

**Metrics After Sprint 1.3:**
- Tests written: 10
- Tests passing: 10
- Average cycle time: 1.5 hours/test
- Code added: ~100 lines (validation logic)

---

### Sprint 1.4: Connection Pooling (Fri, 5 tests)

#### Objective: Verify connections are reused, not recreated

**TDD Cycle 1: Connections Reused**

```
RED (2 hours):
├─ Test:
│  ├─ Make 10 requests
│  ├─ Track connection count
│  └─ Assert count == 1 (reused)
├─ Actual: 10 new connections (BUG: creating per request)
└─ Test fails as expected

GREEN (2 hours):
├─ Change clients.rs:
│  ├─ FROM: Channel::from_shared(url).connect() per request
│  ├─ TO: Cached channel in Arc<Mutex<_>>
├─ Share channel across requests
└─ Test passes ✅

REFACTOR (1 hour):
├─ Add ChannelPool struct
├─ Implement Clone, Debug
├─ Documentation
└─ All tests pass
```

**Remaining tests:**
- test_connection_pool_max_size (50 concurrent requests, ≤10 connections)
- test_connections_reused_after_request (verify same channel ID)
- test_new_connection_after_timeout (auto-reconnect)
- test_connection_timeout_enforced (5s max)

**Code Changes in clients.rs:**

```rust
// BEFORE (Creating connection per request)
pub async fn auth_client(&self) -> Result<AuthServiceClient<Channel>> {
    let channel = Channel::from_shared(self.auth_endpoint.clone())?
        .connect()
        .await?;
    Ok(AuthServiceClient::new(channel))
}

// AFTER (Reusing connection)
pub async fn auth_client(&self) -> Result<AuthServiceClient<Channel>> {
    let mut channels = self.channels.lock().await;

    if let Some(channel) = channels.get("auth") {
        return Ok(AuthServiceClient::new(channel.clone()));
    }

    let channel = Channel::from_shared(self.auth_endpoint.clone())?
        .connect()
        .await?;
    channels.insert("auth".to_string(), channel.clone());

    Ok(AuthServiceClient::new(channel))
}
```

**Metrics After Sprint 1.4:**
- Tests written: 5
- Tests passing: 5
- Average cycle time: 2 hours/test
- Code added: ~80 lines (connection pooling)

---

### Week 1 Summary

```
Monday-Friday:
├─ Mon-Tue: Auth tests (8) - 16 hours
├─ Wed: Authorization tests (20) - 16 hours
├─ Thu: Input validation tests (10) - 8 hours
└─ Fri: Connection pooling tests (5) - 8 hours

Total: 55 tests, 48 hours
Code added: 530 lines
Average cycle time: 52 minutes/test

Coverage improvement:
├─ GraphQL Gateway: 1.4% → 28%
├─ Overall backend: 23.7% → 32%
└─ Security-critical paths: 0% → 90%
```

---

## Phase 2: Core Resolvers (Week 2) - 40 Tests

### Sprint 2.1: Auth Resolver (Mon-Tue, 15 tests)

#### Test Patterns for Auth Resolver

```rust
// Pattern 1: Happy Path
#[test]
async fn test_login_success() {
    // Setup: User registered
    let email = "user@example.com";
    register_user(email, "ValidPass123!").await;

    // Action: Login
    let result = login(email, "ValidPass123!").await;

    // Assert: Token returned
    assert!(result.is_ok());
    assert!(!result.token.is_empty());
}

// Pattern 2: Error Case
#[test]
async fn test_login_invalid_credentials() {
    let email = "user@example.com";
    register_user(email, "ValidPass123!").await;

    // Wrong password
    let result = login(email, "WrongPass123!").await;

    // Must return generic error (no user enumeration)
    assert!(result.is_err());
    assert!(result.error.contains("Invalid credentials"));
}

// Pattern 3: Edge Case
#[test]
async fn test_login_user_not_found() {
    let result = login("nonexistent@example.com", "anything").await;

    // Same error as wrong password (prevents enumeration)
    assert!(result.is_err());
    assert_eq!(
        login("user@example.com", "wrong").error,
        login("nonexistent@example.com", "any").error
    );
}
```

**Test Checklist for Auth Resolver:**
- ✅ Login success
- ✅ Login invalid email
- ✅ Login wrong password
- ✅ Login user not found (same error as wrong password)
- ✅ Logout invalidates token
- ✅ Logout already logged out user (idempotent)
- ✅ Refresh token success
- ✅ Refresh expired token
- ✅ Refresh invalid token
- ✅ Rate limit on 5 failed attempts
- ✅ Rate limit reset after success
- ✅ Concurrent login requests
- ✅ Concurrent logout requests
- ✅ Token expiration enforcement
- ✅ Token claims validation

**Implementation Pattern:**

```rust
// Step 1: Implement login resolver
#[Object]
impl AuthMutation {
    async fn login(
        &self,
        email: String,
        password: String,
    ) -> Result<LoginResponse> {
        // 1. Validate input
        if !is_valid_email(&email) {
            return Err(Error::InvalidEmail);
        }

        // 2. Query user
        let user = db.get_user_by_email(&email).await?;

        // 3. Verify password
        if !verify_password(&password, &user.password_hash) {
            return Err(Error::InvalidCredentials);
        }

        // 4. Generate tokens
        let access_token = generate_access_token(&user.id)?;
        let refresh_token = generate_refresh_token(&user.id)?;

        Ok(LoginResponse {
            access_token,
            refresh_token,
            expires_in: 3600,
        })
    }
}

// Step 2: Run tests
cargo test test_login_*
```

---

### Sprint 2.2: Content Resolver (Wed-Thu, 15 tests)

#### Critical Test: N+1 Query Prevention

```rust
#[tokio::test]
async fn test_feed_query_makes_exactly_three_rpc_calls() {
    let client = setup_graphql_client().await;
    let token = login(&client).await;

    // Enable request tracking
    let tracker = RequestTracker::new();
    client.set_request_tracker(&tracker);

    // Execute feed query for 10 posts
    let response = graphql_query(r#"
        query {
            feed(limit: 10) {
                posts {
                    id
                    content
                    author { username }
                }
            }
        }
    "#)
    .with_auth(&token)
    .execute(&client)
    .await;

    // Check RPC call count
    let calls = tracker.get_calls_by_service();

    // Should make EXACTLY 3 calls (not 13):
    // 1. Feed service (get feed)
    // 2. Content service (batch load posts)
    // 3. User service (batch load authors)

    assert_eq!(calls.get("feed_service"), Some(&1), "Should call feed_service once");
    assert_eq!(calls.get("content_service"), Some(&1), "Should batch load posts");
    assert_eq!(calls.get("user_service"), Some(&1), "Should batch load authors");

    let total_calls: usize = calls.values().sum();
    assert_eq!(total_calls, 3, "Should make exactly 3 RPC calls, not {}", total_calls);
}
```

**Test Checklist for Content Resolver:**
- ✅ Feed query returns posts
- ✅ Feed query N+1 protection
- ✅ Feed pagination cursor validation
- ✅ Feed empty list handling
- ✅ Create post requires auth
- ✅ Create post requires authorization
- ✅ Update post permission check
- ✅ Update post idempotent
- ✅ Delete post soft delete
- ✅ Delete post idempotent
- ✅ Delete post check ownership
- ✅ Content length validation
- ✅ Service timeout graceful failure
- ✅ Service error propagation
- ✅ GraphQL error handling

---

### Sprint 2.3: User Resolver (Thu-Fri, 10 tests)

**Test Checklist:**
- ✅ Get user profile public fields
- ✅ Get user profile private fields (auth required)
- ✅ Update own profile success
- ✅ Cannot update other user profile
- ✅ Follow user success
- ✅ Follow user idempotent
- ✅ Unfollow user success
- ✅ Block user success
- ✅ Block user prevents messages
- ✅ User not found returns 404

**Week 2 Total: 40 tests, 40 hours**

---

## Phase 3: Integration & iOS (Week 3) - 30 Tests

### Sprint 3.1: End-to-End Flows (Mon-Tue, 15 tests)

**Test Pattern: Complete User Journey**

```rust
#[tokio::test]
async fn test_complete_user_registration_and_first_post() {
    // Step 1: User registers
    let client = setup_graphql_client().await;
    let register = graphql_query(r#"
        mutation {
            register(email: "alice@example.com", password: "SecurePass123!") {
                access_token
                user { id username }
            }
        }
    "#).execute(&client).await;

    assert!(register.is_ok());
    let token = register.access_token;
    let user_id = register.user.id;

    // Step 2: User creates post
    let post = graphql_query(r#"
        mutation {
            createPost(content: "Hello world!") {
                id
                createdAt
                author { username }
            }
        }
    "#)
    .with_auth(&token)
    .execute(&client)
    .await;

    assert_eq!(post.author.username, "alice");

    // Step 3: Other user sees post in feed
    let bob_token = graphql_query(r#"
        mutation {
            register(email: "bob@example.com", password: "SecurePass123!") {
                access_token
            }
        }
    "#).execute(&client).await.access_token;

    // Bob follows Alice
    graphql_query(&format!(r#"
        mutation {{
            followUser(userId: "{}") {{ success }}
        }}
    "#, user_id))
    .with_auth(&bob_token)
    .execute(&client)
    .await;

    // Bob's feed includes Alice's post
    let feed = graphql_query(r#"
        query {
            feed(limit: 10) {
                posts { id author { username } }
            }
        }
    "#)
    .with_auth(&bob_token)
    .execute(&client)
    .await;

    assert!(feed.posts.iter().any(|p| p.author.username == "alice"));
}
```

**Other E2E Tests:**
- test_concurrent_post_creation (race condition)
- test_follow_affects_feed (social graph)
- test_block_prevents_interaction (privacy)
- test_message_conversation (messaging)
- ... (15 total)

---

### Sprint 3.2: iOS Security (Wed-Fri, 15 tests)

**Swift Test Template:**

```swift
class FeedViewModelTests: XCTestCase {
    func testFetchFeedUpdatesState() {
        // Given
        let mockAPIClient = MockAPIClient()
        let viewModel = FeedViewModel(apiClient: mockAPIClient)

        mockAPIClient.mockFeedResponse = [
            Post(id: "1", content: "Hello", author: User(id: "u1", username: "alice"))
        ]

        // When
        viewModel.fetchFeed()

        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.posts.count, 1)
            XCTAssertFalse(self.viewModel.loading)
            XCTAssertNil(self.viewModel.error)
        }
    }
}
```

**iOS Test Checklist (15 tests):**
- ✅ FeedViewModel fetch success
- ✅ FeedViewModel fetch error handling
- ✅ FeedViewModel pagination
- ✅ FeedViewModel refresh
- ✅ FeedViewModel concurrent requests
- ✅ APIClient token in Keychain
- ✅ APIClient token refresh on 401
- ✅ APIClient retry on timeout
- ✅ APIClient certificate pinning
- ✅ APIClient no token in logs
- ✅ Login flow integration
- ✅ Logout clears token
- ✅ Token expiration handling
- ✅ Network error recovery
- ✅ Concurrent user interactions

---

## Metrics Tracking

### Daily Standup Template

```
Date: 2025-11-[XX]
Engineer: [Name]
Sprint: [1.1-3.2]

Completed Today:
  ├─ Tests written: [N]
  ├─ Tests passing: [N]
  ├─ Tests failing: [N]
  └─ Lines of code: [N]

Cycle Metrics:
  ├─ RED time: [M] minutes
  ├─ GREEN time: [M] minutes
  ├─ REFACTOR time: [M] minutes
  └─ Total cycle: [M] minutes

Coverage:
  ├─ Statement coverage: [N]%
  ├─ Branch coverage: [N]%
  └─ Function coverage: [N]%

Blockers:
  ├─ Mock framework issues
  ├─ Database setup complexity
  └─ Service integration

Next 24 hours:
  ├─ Tests to write: [N]
  ├─ Cycles to complete: [N]
  └─ Code to implement: [N] lines
```

### Weekly Progress Chart

```
Week 1:
  Mon: ████░░░░░░ 10 tests
  Tue: ████████░░ 8 tests
  Wed: ███████░░░ 20 tests
  Thu: ██████░░░░ 10 tests
  Fri: ███░░░░░░░ 5 tests

  Total: 55 tests, 48 hours, 528 lines code
  Coverage: 1.4% → 28%
```

---

## Implementation Checklist

### Before Starting (Day 1)

- [ ] Read all test strategy documents
- [ ] Set up test infrastructure (test helpers, mocks)
- [ ] Create test file templates
- [ ] Configure CI/CD pipeline for test runs
- [ ] Set up coverage reporting
- [ ] Schedule daily standup (15 min)
- [ ] Identify blockers

### Each Sprint

- [ ] Create GitHub issues for each test
- [ ] Write test code first (RED phase)
- [ ] Run tests and verify failure (RED ✓)
- [ ] Implement minimal code (GREEN phase)
- [ ] Run tests and verify pass (GREEN ✓)
- [ ] Refactor and improve code (REFACTOR phase)
- [ ] Run full test suite (no regression)
- [ ] Update progress dashboard
- [ ] Sprint review and retrospective

### Before Merge

- [ ] All P0 tests passing (55 tests)
- [ ] All P1 tests passing (74 tests)
- [ ] Coverage report > 50%
- [ ] CI/CD pipeline green
- [ ] Code review of test implementations
- [ ] Documentation updated
- [ ] Team sign-off

---

## Success Criteria

### P0 Complete (Week 1)
```
✅ 55 tests written
✅ 55 tests passing
✅ GraphQL Gateway: 28%+ coverage
✅ Security tests: 100% of critical paths
✅ All auth + permission checks enforced
✅ Connection pooling implemented
✅ Input validation complete
```

### P1 Complete (Week 2)
```
✅ 40 resolver tests written and passing
✅ N+1 query protection verified
✅ Error handling tested
✅ End-to-end flows working
✅ iOS tests written and passing
```

### Merge-Ready (Week 3)
```
✅ 129 tests written and passing
✅ 60%+ code coverage
✅ All security issues resolved
✅ All performance issues resolved
✅ CI/CD pipeline passing
✅ Code review approved
✅ Ready for production deployment
```

---

## Estimated Velocity

```
Day 1-2: 8 tests, 16 hours (ramping up)
Day 3-4: 12 tests, 16 hours
Day 5: 10 tests, 8 hours
Week 1 Total: 55 tests, 48 hours ✅

Week 2: 40 tests, 40 hours ✅
Week 3: 30 tests, 30 hours ✅

Grand Total: 129 tests, 118 hours
            (~3 weeks for 1 engineer)
            (~1.5 weeks for 2 engineers)
```

---

## Red Flags During Implementation

If you see these, ask for help:

1. **Test takes > 4 hours** - Something is wrong (test too big or infrastructure issue)
2. **Coverage decreases** - You're not testing new code properly
3. **Tests conflict** - Service interactions not isolated correctly
4. **Same bug in 3+ tests** - Fix implementation, not tests
5. **CI/CD pipeline fragile** - Tests depend on external state (database order, timing)

---

## Commands Cheat Sheet

```bash
# Run specific test suite
cargo test --test graphql_auth_middleware_test -- --test-threads=1

# Run single test
cargo test test_login_success -- --nocapture

# Run all tests with coverage
cargo tarpaulin --out Html

# Watch tests (install cargo-watch first)
cargo watch -x "test --test graphql_auth_middleware_test"

# Profile test execution time
cargo test --test graphql_auth_middleware_test -- --nocapture --test-threads=1 | grep test_

# Check test structure
cargo test --test graphql_auth_middleware_test -- --list
```

---

## Summary

This plan converts PR #59 from "untested code dump" to "production-ready with 60%+ coverage" in 2-3 weeks using TDD methodology.

**Key Success Factors:**
1. Write failing tests FIRST (RED phase)
2. Implement minimal code (GREEN phase)
3. Refactor with confidence (REFACTOR phase)
4. Track metrics daily
5. Do not skip phases

**Expected Outcome:**
- Security: 🟢 All critical paths tested
- Performance: 🟢 Connection pooling working
- Reliability: 🟢 Error handling verified
- Maintainability: 🟢 Code is well-documented via tests

**Ready to start? Begin with Phase 1, Sprint 1.1 on Monday.**

