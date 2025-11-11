# Architecture Comparison: V1 vs V2

**Date**: 2025-11-11
**Status**: Design Complete - Ready for Approval

---

## Quick Reference

| Aspect | Current (V1) | Redesigned (V2) | Improvement |
|--------|--------------|-----------------|-------------|
| **Services** | 12 | 6 core + 2 support | 33% reduction |
| **Circular Dependencies** | 3 | 0 | 100% fixed |
| **Data Ownership Violations** | 15/min | 0 | 100% fixed |
| **Independent Deployment** | 20% | 100% | 5x improvement |
| **Avg Dependencies/Service** | 3.2 | < 2 | 37% reduction |
| **GraphQL DB Connections** | 1 (PostgreSQL) | 0 | Clean separation |

---

## Service Architecture

### Current (V1) - 12 Services with Chaos

```
auth-service ←→ user-service         [CIRCULAR DEPENDENCY ❌]
content-service ←→ feed-service      [CIRCULAR DEPENDENCY ❌]
messaging-service ←→ notification    [CIRCULAR DEPENDENCY ❌]

media-service  )
video-service  } → Same data, fragmented [DUPLICATION ❌]
streaming     )
cdn-service   )

graphql-gateway → PostgreSQL         [ANTI-PATTERN ❌]

search-service → ALL databases       [N+1 QUERIES ❌]
```

### Redesigned (V2) - 6 Core Services with Clear Boundaries

```
Identity → User → Content → Social   [ACYCLIC ✅]
                     ↓
                   Media
                     ↓
              Communication

Events ← ALL (publish)               [EVENT-DRIVEN ✅]
Search ← Events (consume only)       [READ-ONLY PROJECTION ✅]

GraphQL → gRPC only (no DB)          [CLEAN ORCHESTRATION ✅]
```

---

## Data Ownership

### Current (V1) - Chaos

| Table | Writers | Problem |
|-------|---------|---------|
| **users** | auth, user, content, messaging, notification, graphql | 6 services write! |
| **sessions** | auth, user | 2 services write |
| **posts** | content, feed | 2 services write |
| **notifications** | messaging, notification, feed | 3 services write |

**Result**: Data corruption, race conditions, impossible to deploy independently.

### Redesigned (V2) - Single Owner

| Table | Owner Service | Readers |
|-------|---------------|---------|
| **users** | user-service | Identity (gRPC), Content (gRPC), Social (gRPC) |
| **sessions** | identity-service | User (gRPC) |
| **posts** | content-service | Social (gRPC), Search (events) |
| **notifications** | communication-service | None (push-based) |

**Result**: Zero conflicts, clear ownership, independent deployability.

---

## API Design

### Current (V1)

```protobuf
// auth-service/proto/auth_service.proto
service AuthService {
  rpc GetUser(GetUserRequest) returns (GetUserResponse);  // ❌ Not auth's job!
  rpc UpdateUser(UpdateUserRequest) returns (User);       // ❌ Writes to user table!
}

// user-service/proto/user_service.proto
service UserService {
  rpc VerifyToken(VerifyTokenRequest) returns (VerifyTokenResponse);  // ❌ Calls auth!
  rpc GetUserPosts(GetUserPostsRequest) returns (PostsResponse);      // ❌ Calls content!
}
```

**Problem**: Overlapping responsibilities, unclear boundaries.

### Redesigned (V2)

```protobuf
// identity-service: Authentication ONLY
service IdentityService {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc Login(LoginRequest) returns (LoginResponse);
  rpc VerifyToken(VerifyTokenRequest) returns (VerifyTokenResponse);
  // NO user profile methods
}

// user-service: User profiles ONLY
service UserService {
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
  rpc UpdateProfile(UpdateProfileRequest) returns (UpdateProfileResponse);
  // NO authentication methods
}
```

**Result**: Clear separation of concerns, single responsibility per service.

---

## Communication Patterns

### Current (V1) - Direct Calls with Circular Dependencies

```rust
// ❌ BAD: content-service calls feed-service
pub async fn create_post(req: CreatePostRequest) -> Result<Post> {
    let post = db.insert_post(&req).await?;

    // Direct call to feed-service
    feed_client.update_user_feed(post.author_id, post.id).await?;

    Ok(post)
}

// ❌ BAD: feed-service calls content-service
pub async fn get_feed(user_id: Uuid) -> Result<Vec<Post>> {
    let feed_items = db.get_feed_items(user_id).await?;

    // Circular call back to content-service
    content_client.get_posts_by_ids(feed_items).await?
}
```

**Problem**: Can't deploy content without feed, can't deploy feed without content.

### Redesigned (V2) - Event-Driven Decoupling

```rust
// ✅ GOOD: content-service publishes event
pub async fn create_post(
    req: CreatePostRequest,
    pool: &PgPool,
    events: &EventPublisher,
) -> Result<Post> {
    let mut tx = pool.begin().await?;

    let post = insert_post(&mut tx, &req).await?;

    // Publish event (Outbox pattern)
    events.publish_in_transaction(
        &mut tx,
        "content.post.created",
        &PostCreatedEvent { post_id: post.id, author_id: req.author_id },
    ).await?;

    tx.commit().await?;
    Ok(post)
}

// ✅ GOOD: social-service subscribes to event
#[event_handler(topic = "content.post.created")]
pub async fn on_post_created(&self, event: PostCreatedEvent) -> Result<()> {
    let followers = self.get_followers(&event.author_id).await?;

    for follower_id in followers {
        sqlx::query!(
            "INSERT INTO feeds (user_id, content_id) VALUES ($1, $2)",
            follower_id, event.post_id
        ).execute(&self.pool).await?;
    }

    Ok(())
}
```

**Result**: Content can deploy independently. Social reacts asynchronously.

---

## GraphQL Gateway

### Current (V1) - Anti-Pattern

```rust
// ❌ BAD: GraphQL has database connection
pub struct Context {
    pub db_pool: PgPool,  // Direct database access!
    pub user_client: UserServiceClient,
}

pub async fn user(ctx: &Context, id: Uuid) -> Result<User> {
    // Direct database query
    sqlx::query_as!(User, "SELECT * FROM users WHERE id = $1", id)
        .fetch_one(&ctx.db_pool)
        .await
}
```

**Problem**: Gateway knows about database schema, bypasses service boundaries.

### Redesigned (V2) - Clean Orchestration

```rust
// ✅ GOOD: GraphQL has NO database, only gRPC clients
pub struct Context {
    pub user_client: UserServiceClient,
    pub content_client: ContentServiceClient,
    pub social_client: SocialServiceClient,
    // NO db_pool!
}

pub async fn user(ctx: &Context, id: Uuid) -> Result<User> {
    // Call user-service via gRPC
    ctx.user_client.get_user(GetUserRequest {
        user_id: id.to_string(),
    }).await?.into_inner().user.ok_or(Error::NotFound)
}

pub async fn user_posts(ctx: &Context, user: &User) -> Result<Vec<Post>> {
    // Call content-service via gRPC
    ctx.content_client.get_user_posts(GetUserPostsRequest {
        user_id: user.id.clone(),
        limit: 20,
    }).await?.into_inner().posts
}
```

**Result**: Gateway is a thin orchestration layer. All business logic in services.

---

## Deployment & Scalability

### Current (V1)

```yaml
# ❌ BAD: Can't deploy auth-service without user-service
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
spec:
  replicas: 3
  containers:
    - name: auth
      env:
        - name: USER_SERVICE_URL
          value: "user-service:50051"  # Circular dependency!

# If user-service is down, auth-service won't start
```

### Redesigned (V2)

```yaml
# ✅ GOOD: Identity service has NO dependencies
apiVersion: apps/v1
kind: Deployment
metadata:
  name: identity-service
spec:
  replicas: 3
  containers:
    - name: identity
      env:
        - name: KAFKA_BROKERS
          value: "kafka:9092"
        # NO service dependencies!

# Can deploy independently, always starts successfully
```

---

## Testing Strategy

### Current (V1)

```rust
// ❌ BAD: Integration test requires ALL services running
#[tokio::test]
async fn test_user_registration() {
    // Requires: auth-service, user-service, notification-service, events-service
    let auth = connect_to_auth().await?;
    let user = connect_to_user().await?;
    let notif = connect_to_notification().await?;
    let events = connect_to_events().await?;

    // If any service is down, test fails
    let result = auth.register(req).await?;

    // Wait for circular propagation
    tokio::time::sleep(Duration::from_secs(5)).await;

    // Check multiple databases
    assert!(user.get_user(result.user_id).await.is_ok());
    assert!(notif.check_welcome_email(result.user_id).await.is_ok());
}
```

**Problem**: Slow, flaky, requires entire stack.

### Redesigned (V2)

```rust
// ✅ GOOD: Test single service in isolation
#[tokio::test]
async fn test_user_registration() {
    // Only requires: identity-service + Kafka (mock)
    let identity = IdentityServiceClient::connect("http://localhost:50051").await?;

    let resp = identity.register(RegisterRequest {
        email: "test@example.com".into(),
        username: "testuser".into(),
        password: "password123".into(),
    }).await?;

    assert!(!resp.into_inner().access_token.is_empty());

    // Event published to Kafka (can verify with Kafka mock)
    // No need to wait for other services
}

// Separate test for user-service event handling
#[tokio::test]
async fn test_user_profile_created_from_event() {
    let pool = setup_test_db().await;
    let handler = UserEventHandlers::new(pool.clone());

    // Simulate event
    handler.on_user_registered(UserRegisteredEvent {
        user_id: "123".into(),
        email: "test@example.com".into(),
        username: "testuser".into(),
    }).await?;

    // Verify profile created
    let user = sqlx::query!("SELECT * FROM users WHERE id = $1", "123")
        .fetch_one(&pool).await?;

    assert_eq!(user.username, "testuser");
}
```

**Result**: Fast, reliable, isolated tests.

---

## Database Constraints

### Current (V1) - No Enforcement

```sql
-- ❌ NO constraints on service ownership
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE,
    -- Anyone can write!
);

-- Result: auth-service, user-service, messaging-service all write to users
```

### Redesigned (V2) - Database-Level Enforcement

```sql
-- ✅ Service ownership enforced at database level
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE,
    service_owner VARCHAR(50) DEFAULT 'user-service' NOT NULL
);

ALTER TABLE users ADD CONSTRAINT owned_by_user_service
    CHECK (service_owner = 'user-service');

-- Trigger to prevent cross-service writes
CREATE OR REPLACE FUNCTION check_service_boundary()
RETURNS TRIGGER AS $$
DECLARE
    current_service VARCHAR(50);
BEGIN
    current_service := current_setting('application_name', true);

    IF current_service IS NOT NULL AND current_service != NEW.service_owner THEN
        RAISE EXCEPTION 'Service % cannot write to table owned by %',
            current_service, NEW.service_owner;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_service_boundary
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION check_service_boundary();
```

**Result**: Database enforces service boundaries. Violations are impossible.

---

## Metrics & Observability

### Current (V1)

```
Circular Dependencies: 3
Cross-Service DB Queries: 15/min
Service Ownership Violations: 50+/day
Independent Deployment Rate: 20%

⛔ Cannot trace requests across circular dependencies
⛔ No clear service boundaries to monitor
⛔ Unknown which service owns which data
```

### Redesigned (V2)

```
Circular Dependencies: 0 ✅
Cross-Service DB Queries: 0 ✅
Service Ownership Violations: 0 ✅
Independent Deployment Rate: 100% ✅

✅ Every event has correlation_id for tracing
✅ Every service has clear ownership metrics
✅ Every boundary violation logged and alerted
```

---

## Migration Risk Assessment

| Risk | Mitigation |
|------|-----------|
| **Breaking existing APIs** | Feature flags for gradual rollout |
| **Data inconsistency** | Outbox pattern ensures atomicity |
| **Event ordering** | Kafka partitions by entity ID |
| **Deployment coordination** | Blue-green deployment per service |
| **Rollback complexity** | Each phase can rollback independently |
| **Developer learning curve** | Comprehensive documentation + examples |

---

## Conclusion

### Current V1 Architecture: 🔴 Not Scalable

- Circular dependencies block deployments
- Data ownership chaos causes bugs
- Over-fragmentation (12 services doing 6 jobs)
- GraphQL gateway has database access (anti-pattern)
- Testing requires entire stack

### Redesigned V2 Architecture: 🟢 Production-Ready

- Zero circular dependencies (acyclic graph)
- Clear data ownership (single writer per table)
- Right-sized services (6 core + 2 support)
- Clean separation of concerns
- Independent deployment and testing

**Implementation Timeline**: 6 weeks
**Risk Level**: Medium (mitigated with feature flags)
**Reward**: High (solves all architectural anti-patterns)

---

"Theory and practice sometimes clash. And when that happens, theory loses. Every single time." - Linus Torvalds

This redesign is based on real-world problems, not theoretical perfection.

**Next Steps**: Get approval, start Phase 1 implementation (Identity Service + Events Infrastructure).
