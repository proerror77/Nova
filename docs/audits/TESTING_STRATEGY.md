# Nova Social Backend - Testing Strategy & Execution Plan

**Version**: 1.0
**Last Updated**: 2025-11-22
**Status**: IN PROGRESS - P0/P1 items being addressed

## Executive Summary

Current test coverage is **MEDIUM-HIGH RISK** due to:
- **Critical gaps**: Chat authorization, social-service integration, feed performance
- **Architecture issue**: Tests validating code existence rather than behavior
- **Coverage metric**: ~1657 tests / ~26k LOC but <30% coverage on security paths

**Recommendation**: Implement P0 blockers immediately before production release.

---

## Part 1: Critical Gaps & Mitigations

### BLOCKER 1: Chat Authorization Tests Missing

**Risk**: Users could potentially access/send messages in conversations they don't own

**Current Code**:
```rust
// backend/graphql-gateway/src/rest_api/chat.rs:50
pub async fn send_chat_message(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    payload: web::Json<SendMessageBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };
    // ⚠️ ISSUE: Only checks authentication, not authorization
    // ⚠️ MISSING TEST: Does not verify user owns conversation
}
```

**Test Template - Add to `backend/graphql-gateway/tests/chat_authorization_tests.rs`**:

```rust
//! Chat Authorization Tests
//!
//! OWASP A01:2021 - Broken Access Control
//! Tests that users can only access/modify their own conversations

use actix_web::{test, web, App, HttpResponse};
use graphql_gateway::clients::{MockChatClient, ServiceClients};
use uuid::Uuid;

async fn mock_send_handler() -> HttpResponse {
    HttpResponse::Ok().finish()
}

#[tokio::test]
async fn test_send_message_requires_conversation_membership() {
    // User A tries to send message to conversation between User B and User C
    let user_a_id = Uuid::new_v4();
    let user_b_id = Uuid::new_v4();
    let user_c_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    let mut chat_client = MockChatClient::new();
    chat_client.expect_send_message()
        .with(
            eq(SendMessageRequest {
                conversation_id: conversation_id.to_string(),
                sender_id: user_a_id.to_string(),
                content: "message".to_string(),
                ..Default::default()
            }),
        )
        .times(1)
        .returning(|_| {
            Err(Status::permission_denied(
                "User is not a member of this conversation"
            ))
        });

    // Setup test app
    let clients = web::Data::new(ServiceClients::with_mock_chat(chat_client));
    let app = test::init_service(
        App::new()
            .app_data(clients)
            .route("/api/v2/chat/messages", web::post().to(mock_send_handler)),
    )
    .await;

    // Test: User A sends to B-C conversation
    let req = test::TestRequest::post()
        .uri("/api/v2/chat/messages")
        .insert_header(("Authorization", format!("Bearer {}", generate_jwt(user_a_id))))
        .set_json(&SendMessageRequest {
            conversation_id: conversation_id.to_string(),
            sender_id: user_a_id.to_string(),
            content: "unauthorized message".to_string(),
            ..Default::default()
        })
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 403, "Should deny unauthorized conversation access");
}

#[tokio::test]
async fn test_list_conversations_filters_by_user() {
    let user_a_id = Uuid::new_v4();
    let user_b_id = Uuid::new_v4();
    let conv_a1 = Uuid::new_v4(); // A's conversation
    let conv_a2 = Uuid::new_v4(); // A's conversation
    let conv_b1 = Uuid::new_v4(); // B's conversation

    let mut chat_client = MockChatClient::new();
    chat_client.expect_list_conversations()
        .withf(move |req| req.user_id == user_a_id.to_string())
        .times(1)
        .returning(move |_| {
            Ok(ListConversationsResponse {
                conversations: vec![
                    Conversation { id: conv_a1.to_string(), ..Default::default() },
                    Conversation { id: conv_a2.to_string(), ..Default::default() },
                ],
                ..Default::default()
            })
        });

    let clients = web::Data::new(ServiceClients::with_mock_chat(chat_client));
    let app = test::init_service(
        App::new()
            .app_data(clients)
            .route("/api/v2/chat/conversations", web::get().to(mock_get_conversations)),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/api/v2/chat/conversations")
        .insert_header(("Authorization", format!("Bearer {}", generate_jwt(user_a_id))))
        .to_request();

    let resp = test::call_service(&app, req).await;
    let body: ListConversationsResponse = test::read_body_json(resp).await;

    assert_eq!(body.conversations.len(), 2);
    assert!(body.conversations.iter().all(|c| {
        c.id == conv_a1.to_string() || c.id == conv_a2.to_string()
    }), "User should only see their own conversations");
}

#[tokio::test]
async fn test_get_messages_validates_conversation_access() {
    let user_id = Uuid::new_v4();
    let other_user_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    let mut chat_client = MockChatClient::new();
    chat_client.expect_get_messages()
        .with(
            eq(GetMessagesRequest {
                conversation_id: conversation_id.to_string(),
                requester_id: user_id.to_string(),
                ..Default::default()
            }),
        )
        .times(1)
        .returning(|_| {
            Err(Status::permission_denied(
                "You do not have access to this conversation"
            ))
        });

    // ... similar test setup

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 403);
}

fn generate_jwt(user_id: Uuid) -> String {
    // Use crypto_core JWT generation
    crypto_core::jwt::generate_access_token(
        user_id,
        "test@example.com",
        "testuser"
    ).expect("JWT generation failed")
}
```

---

### BLOCKER 2: Social-Service Integration Tests Missing

**Current State**:
```
backend/social-service/tests/
└── follow_boundary.rs (68 LOC - only code existence checks)
```

**Missing**: Zero integration tests for follow operations

**Impact**: Follow/unfollow may fail in production without detection

**Solution**: Create `backend/social-service/tests/integration/`

**Test Template - Follow Operations**:

```rust
// File: backend/social-service/tests/integration/follow_operations_test.rs

//! Follow Operation Integration Tests
//!
//! Tests the complete follow/unfollow flow:
//! 1. social-service validates follow request
//! 2. graph-service creates edge
//! 3. cache-invalidation triggers
//! 4. Feed visibility updates

use social_service::handlers::follow::{CreateFollowRequest, DeleteFollowRequest};
use social_service::services::follow_service::FollowService;
use uuid::Uuid;

#[tokio::test]
async fn test_follow_creates_graph_edge() {
    let follower_id = Uuid::new_v4();
    let followee_id = Uuid::new_v4();

    let mut db = MockDatabase::new();
    let mut graph_client = MockGraphClient::new();

    // Setup expectations
    db.expect_insert_follow()
        .with(follower_id, followee_id)
        .times(1)
        .returning(Ok(()));

    graph_client.expect_create_edge()
        .with(follower_id, followee_id)
        .times(1)
        .returning(Ok(()));

    let service = FollowService::new(db, graph_client, MockCache::new());

    let req = CreateFollowRequest {
        follower_id: follower_id.to_string(),
        followee_id: followee_id.to_string(),
    };

    let result = service.create_follow(req).await;
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_follow_prevents_self_follow() {
    let user_id = Uuid::new_v4();
    let service = FollowService::new(
        MockDatabase::new(),
        MockGraphClient::new(),
        MockCache::new()
    );

    let req = CreateFollowRequest {
        follower_id: user_id.to_string(),
        followee_id: user_id.to_string(), // Same user!
    };

    let result = service.create_follow(req).await;
    assert!(result.is_err());
    assert_eq!(
        result.unwrap_err().to_string(),
        "Cannot follow yourself"
    );
}

#[tokio::test]
async fn test_follow_prevents_duplicate_follows() {
    let follower_id = Uuid::new_v4();
    let followee_id = Uuid::new_v4();

    let mut db = MockDatabase::new();
    db.expect_insert_follow()
        .with(follower_id, followee_id)
        .returning(Err(DatabaseError::UniqueConstraintViolation));

    let service = FollowService::new(
        db,
        MockGraphClient::new(),
        MockCache::new()
    );

    let req = CreateFollowRequest {
        follower_id: follower_id.to_string(),
        followee_id: followee_id.to_string(),
    };

    let result = service.create_follow(req).await;
    assert!(result.is_err());
}

#[tokio::test]
async fn test_unfollow_removes_graph_edge() {
    let follower_id = Uuid::new_v4();
    let followee_id = Uuid::new_v4();

    let mut db = MockDatabase::new();
    let mut graph_client = MockGraphClient::new();

    db.expect_delete_follow()
        .with(follower_id, followee_id)
        .times(1)
        .returning(Ok(()));

    graph_client.expect_delete_edge()
        .with(follower_id, followee_id)
        .times(1)
        .returning(Ok(()));

    let service = FollowService::new(db, graph_client, MockCache::new());

    let req = DeleteFollowRequest {
        follower_id: follower_id.to_string(),
        followee_id: followee_id.to_string(),
    };

    let result = service.delete_follow(req).await;
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_unfollow_with_blocking() {
    // If User A blocks User B, follow relationship is removed
    let user_a = Uuid::new_v4();
    let user_b = Uuid::new_v4();

    let mut service = create_test_service().await;

    // A follows B
    service.create_follow(user_a, user_b).await.unwrap();

    // A blocks B
    service.block_user(user_a, user_b).await.unwrap();

    // Verify follow is removed
    let is_following = service.is_following(user_a, user_b).await.unwrap();
    assert!(!is_following, "Follow should be removed when blocking");
}
```

---

### BLOCKER 3: Feed Service Tests Using `include_str!()` - Convert to Functional

**Problem**: Current tests check if code exists, not if it works

```rust
// ❌ CURRENT APPROACH - PROBLEMATIC
#[actix_web::test]
async fn test_feed_pagination_logic() {
    let source = include_str!("../src/handlers/feed.rs");
    assert!(source.contains("remaining")); // Only checks code existence
}
```

**Solution**: Replace with actual integration tests using mocks

**Test Template - Functional Feed Tests**:

```rust
// File: backend/feed-service/tests/integration/feed_pagination_test.rs

//! Feed Pagination Integration Tests
//!
//! Tests actual feed handler behavior with mocked gRPC services

use feed_service::handlers::feed::GetFeedRequest;
use feed_service::models::FeedPost;
use uuid::Uuid;

#[tokio::test]
async fn test_feed_respects_limit_parameter() {
    let user_id = Uuid::new_v4();
    let followed_users = vec![Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4()];

    // Setup mocks to return 50 posts total
    let mut content_client = MockContentClient::new();
    content_client.expect_get_posts_by_author()
        .returning(|author_id| {
            let posts = (0..50).map(|i| FeedPost {
                id: Uuid::new_v4(),
                user_id: author_id,
                content: format!("Post {}", i),
                created_at: chrono::Utc::now(),
                ranking_score: 0.5,
                like_count: 0,
                comment_count: 0,
                share_count: 0,
            }).collect();
            Ok(posts)
        });

    let handler = FeedHandler::new(
        Arc::new(content_client),
        Arc::new(MockGraphClient::new()),
    );

    // Test 1: Request 20 posts with no cursor
    let req = GetFeedRequest {
        user_id: user_id.to_string(),
        limit: 20,
        cursor: None,
    };

    let resp = handler.get_feed(req).await.unwrap();
    assert_eq!(resp.posts.len(), 20, "Should respect limit=20");
    assert!(resp.has_more, "Should indicate more posts available");
    assert!(!resp.next_cursor.is_empty(), "Should provide next cursor");

    // Test 2: Request 100 posts (should cap at 100)
    let req = GetFeedRequest {
        user_id: user_id.to_string(),
        limit: 1000, // Exceeds max
        cursor: None,
    };

    let resp = handler.get_feed(req).await.unwrap();
    assert!(resp.posts.len() <= 100, "Should cap at max limit of 100");
}

#[tokio::test]
async fn test_feed_pagination_with_cursor() {
    let user_id = Uuid::new_v4();

    // Setup mocks
    let mut content_client = MockContentClient::new();
    let all_posts = create_test_posts(200);
    content_client.expect_get_posts_by_author()
        .returning({
            let posts = all_posts.clone();
            move |_author_id| Ok(posts.clone())
        });

    let handler = FeedHandler::new(
        Arc::new(content_client),
        Arc::new(MockGraphClient::new()),
    );

    // Page 1
    let req1 = GetFeedRequest {
        user_id: user_id.to_string(),
        limit: 50,
        cursor: None,
    };
    let resp1 = handler.get_feed(req1).await.unwrap();
    assert_eq!(resp1.posts.len(), 50);
    let cursor = resp1.next_cursor.clone();

    // Page 2
    let req2 = GetFeedRequest {
        user_id: user_id.to_string(),
        limit: 50,
        cursor: Some(cursor),
    };
    let resp2 = handler.get_feed(req2).await.unwrap();
    assert_eq!(resp2.posts.len(), 50);

    // Verify no overlap
    let ids1: Vec<_> = resp1.posts.iter().map(|p| &p.id).collect();
    let ids2: Vec<_> = resp2.posts.iter().map(|p| &p.id).collect();
    assert!(!ids1.iter().any(|id| ids2.contains(id)), "Pages should not overlap");
}

#[tokio::test]
async fn test_feed_handles_partial_failure_gracefully() {
    let user_id = Uuid::new_v4();
    let followed_users = vec![
        Uuid::new_v4(),
        Uuid::new_v4(),
        Uuid::new_v4(),
    ];

    let mut content_client = MockContentClient::new();
    let mut call_count = 0;

    content_client.expect_get_posts_by_author()
        .withf({
            let users = followed_users.clone();
            move |author_id| users.contains(author_id)
        })
        .returning(|author_id| {
            call_count += 1;
            if call_count == 2 {
                // User 2 fails (simulating service unavailable)
                Err(tonic::Status::unavailable("Service temporarily unavailable"))
            } else {
                // Users 1 and 3 succeed
                Ok(create_test_posts(10))
            }
        });

    let handler = FeedHandler::new(
        Arc::new(content_client),
        Arc::new(MockGraphClient::new()),
    );

    let req = GetFeedRequest {
        user_id: user_id.to_string(),
        limit: 50,
        cursor: None,
    };

    let resp = handler.get_feed(req).await.unwrap();

    // Should still return posts from users 1 and 3
    assert!(resp.posts.len() > 0, "Should aggregate posts despite one user failure");
    assert!(!resp.posts.is_empty(), "Should have graceful degradation");
}

#[tokio::test]
async fn test_feed_with_large_followed_list() {
    let user_id = Uuid::new_v4();
    let followed_users: Vec<_> = (0..1000).map(|_| Uuid::new_v4()).collect();

    let mut content_client = MockContentClient::new();
    content_client.expect_get_posts_by_author()
        .returning(|_author_id| Ok(create_test_posts(5))); // 5 posts per user

    let handler = FeedHandler::new(
        Arc::new(content_client),
        Arc::new(MockGraphClient::new()),
    );

    let start = Instant::now();
    let req = GetFeedRequest {
        user_id: user_id.to_string(),
        limit: 20,
        cursor: None,
    };

    let resp = handler.get_feed(req).await.unwrap();
    let duration = start.elapsed();

    assert!(resp.posts.len() <= 20);
    assert!(
        duration < Duration::from_secs(5),
        "Feed aggregation should complete in <5s, took {:?}",
        duration
    );
}
```

---

## Part 2: Implementation Roadmap

### Phase 1: P0 Blockers (This Week)
**Effort**: 5-7 days | **Risk**: Blocks production

1. **Chat Authorization Tests** (1-2 days)
   - File: `backend/graphql-gateway/tests/chat_authorization_tests.rs`
   - Tests: 5-7 test cases
   - Estimated LOC: 200-300

2. **Social-Service Integration Tests** (2-3 days)
   - File: `backend/social-service/tests/integration/follow_operations_test.rs`
   - Tests: 6-8 test cases
   - Estimated LOC: 300-400

3. **Feed Tests Conversion** (1-2 days)
   - Replace: `backend/feed-service/tests/feed_integration_test.rs`
   - Tests: Replace 6 string-literal tests with 8-10 functional tests
   - Estimated LOC: 400-500

### Phase 2: P1 High Priority (Next Sprint)
**Effort**: 8-10 days | **Risk**: Performance/reliability degradation

4. **N+1 Query Performance Tests** (1-2 days)
5. **Cross-Service Authorization Tests** (1-2 days)
6. **Error Path Coverage** (2-3 days)

### Phase 3: P2 Medium Priority (Following Sprint)
**Effort**: 7-10 days | **Risk**: Technical debt buildup

7. **Performance Regression Suite** (2-3 days)
8. **Chaos Engineering Tests** (2-3 days)
9. **E2E API Contract Tests** (2-3 days)

---

## Part 3: Testing Best Practices

### Mock Pattern for gRPC Services

```rust
// backend/feed-service/tests/common/mocks.rs

pub struct MockContentClient {
    expectations: Vec<(String, Box<dyn Fn() -> Result<Vec<FeedPost>> + Send>)>,
}

impl MockContentClient {
    pub fn new() -> Self {
        Self { expectations: Vec::new() }
    }

    pub fn expect_get_posts_by_author(
        &mut self,
        author_id: Uuid,
        response: Result<Vec<FeedPost>>,
    ) -> &mut Self {
        self.expectations.push((
            author_id.to_string(),
            Box::new(move || response.clone()),
        ));
        self
    }

    pub async fn get_posts_by_author(
        &self,
        author_id: Uuid,
    ) -> Result<Vec<FeedPost>> {
        // Return corresponding mock response
    }
}
```

### Authorization Test Pattern

```rust
#[tokio::test]
async fn test_authorization_pattern_name() {
    // 1. Setup: Create test users and resources
    let owner_id = Uuid::new_v4();
    let other_user_id = Uuid::new_v4();
    let resource_id = Uuid::new_v4();

    // 2. Execute: Attempt unauthorized action
    let result = handler.operation(other_user_id, resource_id).await;

    // 3. Assert: Verify proper error
    assert!(result.is_err());
    assert_eq!(
        result.unwrap_err().code(),
        tonic::Code::PermissionDenied
    );
}
```

### Performance Test Pattern

```rust
#[tokio::test]
async fn test_performance_scenario() {
    // 1. Setup: Create test data at scale
    let large_dataset = create_large_dataset(10_000);

    // 2. Baseline: Record baseline metrics
    let start = Instant::now();
    let _result = operation(&large_dataset).await;
    let duration = start.elapsed();

    // 3. Assert: Verify within SLA
    assert!(
        duration < Duration::from_secs(5),
        "Operation exceeded SLA: {:?}",
        duration
    );

    // 4. Log: Record for regression tracking
    println!("Operation duration: {:?} (target: <5s)", duration);
}
```

---

## Part 4: Continuous Improvement

### Monthly Review Checklist
- [ ] Test execution time trending
- [ ] Flaky test detection and fix
- [ ] Coverage metric tracking
- [ ] New security vulnerabilities in test scope
- [ ] Performance SLA compliance

### Test Maintenance
- Keep mocks synchronized with proto definitions
- Update boundary tests after schema changes
- Refactor tests with >50 lines
- Document complex test scenarios

---

## Appendix: Test Files Status

| File | Status | P Level | Action |
|------|--------|---------|--------|
| `chat_authorization_tests.rs` | 🔴 MISSING | P0 | Create |
| `social-service/tests/integration/` | 🔴 MISSING | P0 | Create |
| `feed_integration_test.rs` | 🟡 BROKEN | P0 | Replace |
| `follow_boundary.rs` | 🟡 INSUFFICIENT | P0 | Expand |
| `grpc-jwt-propagation/tests/` | 🟢 GOOD | - | Maintain |
| `user-service/tests/` | 🟢 GOOD | - | Maintain |
| Performance tests | 🟡 TEMPLATE | P1 | Activate |

---

**Document Version**: 1.0
**Created**: 2025-11-22
**Next Review**: 2025-12-06
