# Social Service gRPC Implementation (Phase B)

## Architecture: Transactional Outbox Integration

This gRPC server implements the **Transactional Outbox pattern** for reliable event publishing in social-service.

### Core Design Principles

1. **Atomicity**: Business logic + outbox event in same PostgreSQL transaction
2. **Cache-Aside**: Update Redis AFTER successful PostgreSQL commit (best-effort)
3. **Idempotency**: `ON CONFLICT DO NOTHING` for like operations
4. **Event Publishing**: Use `transactional-outbox` library's `publish_event!` macro

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                      gRPC Request                           │
│                  (CreateLikeRequest)                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              PostgreSQL Transaction BEGIN                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. INSERT INTO likes (idempotent: ON CONFLICT DO NOTHING)  │
│                                                             │
│  2. INSERT INTO outbox_events (via publish_event!)          │
│     - aggregate_type: "like"                                │
│     - event_type: "social.like.created"                     │
│     - payload: { like_id, user_id, post_id, created_at }   │
│                                                             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              PostgreSQL Transaction COMMIT                   │
│          (Both like + event saved atomically)               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│         Redis Counter Update (Best-Effort)                  │
│  INCR social:post:{post_id}:likes                           │
│  (Warning logged if fails, but request succeeds)            │
└─────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│         Outbox Processor (Background Worker)                │
│  - Polls unpublished events every 5 seconds                 │
│  - Publishes to Kafka: nova.like.events                     │
│  - Marks event as published on success                      │
│  - Retries with exponential backoff on failure              │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Details

### File Structure

- **`server.rs`**: Main gRPC service implementation with transactional-outbox
  - Like operations: `CreateLike`, `DeleteLike`, `GetLikeCount`, `CheckUserLiked`, `BatchCheckUserLiked`, `GetPostLikes`
  - Share operations: `CreateShare`, `GetShareCount`, `CheckUserShared`
  - Comment operations: CRUD + listing/count
  - Batch operations: `BatchGetPostStats`

### AppState

Shared state across all gRPC handlers:

```rust
pub struct AppState {
    pub pg_pool: PgPool,                          // PostgreSQL connection pool
    pub counter_service: CounterService,          // Redis counter operations
    pub outbox_repo: Arc<SqlxOutboxRepository>,   // Outbox event repository
}
```

### Transaction Pattern (Example: CreateLike)

```rust
async fn create_like(&self, request: Request<CreateLikeRequest>) -> Result<Response<CreateLikeResponse>, Status> {
    let req = request.into_inner();
    let user_id = Uuid::parse_str(&req.user_id)?;
    let post_id = Uuid::parse_str(&req.post_id)?;

    // 1. Start PostgreSQL transaction
    let mut tx = self.state.pg_pool.begin().await?;

    // 2. Insert like (idempotent)
    let like_id = Uuid::new_v4();
    let result = sqlx::query!(
        "INSERT INTO likes (id, user_id, post_id, created_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (user_id, post_id) DO NOTHING
         RETURNING id",
        like_id, user_id, post_id
    )
    .fetch_optional(&mut *tx)
    .await?;

    let was_created = result.is_some();

    // 3. Publish event (only if new like created)
    if was_created {
        let event_payload = serde_json::json!({
            "like_id": like_id.to_string(),
            "user_id": user_id.to_string(),
            "post_id": post_id.to_string(),
            "created_at": chrono::Utc::now().to_rfc3339(),
        });

        publish_event!(
            &mut tx,
            &self.state.outbox_repo,
            "like",
            like_id,
            "social.like.created",
            event_payload
        )
        .await?;
    }

    // 4. Commit transaction (atomic)
    tx.commit().await?;

    // 5. Update Redis counter (best-effort, after commit)
    let new_count = if was_created {
        self.state.counter_service.clone()
            .increment_like_count(post_id)
            .await
            .unwrap_or_else(|e| {
                tracing::warn!(post_id=%post_id, error=%e, "Failed to increment Redis counter");
                0
            })
    } else {
        self.state.counter_service.clone().get_like_count(post_id).await.unwrap_or(0)
    };

    Ok(Response::new(CreateLikeResponse {
        success: true,
        like_id: like_id.to_string(),
        new_like_count: new_count,
    }))
}
```

## Event Schema

### social.like.created

```json
{
  "like_id": "uuid",
  "user_id": "uuid",
  "post_id": "uuid",
  "created_at": "2025-11-12T10:30:00Z"
}
```

Consumers: notification-service (for like notifications)

### social.like.deleted

```json
{
  "user_id": "uuid",
  "post_id": "uuid",
  "deleted_at": "2025-11-12T10:35:00Z"
}
```

Consumers: analytics-service (for unlike tracking)

### social.share.created

```json
{
  "share_id": "uuid",
  "user_id": "uuid",
  "post_id": "uuid",
  "share_type": "REPOST|STORY|DM|EXTERNAL",
  "target_user_id": "uuid|null",
  "created_at": "2025-11-12T10:40:00Z"
}
```

Consumers:
- notification-service (notify original author)
- feed-service (add to follower feeds if REPOST)

## Error Handling

### PostgreSQL Transaction Failures

- **Rollback**: If `INSERT INTO likes` or `INSERT INTO outbox_events` fails, transaction rolls back
- **Client Response**: `Status::internal("Failed to commit transaction: ...")`
- **Data Guarantee**: No like exists, no event published (all-or-nothing)

### Redis Counter Update Failures

- **Log Warning**: `tracing::warn!(post_id=%post_id, error=%e, "Failed to increment Redis counter")`
- **Client Response**: Still returns success (PostgreSQL data is source of truth)
- **Recovery**: Counter reconciliation job will sync Redis from PostgreSQL

### Event Publishing Failures (Outbox Processor)

- **Retry**: Exponential backoff (1s, 2s, 4s, 8s, 16s, max 300s)
- **Max Retries**: 5 attempts
- **Dead Letter**: After max retries, event requires manual intervention
- **Monitoring**: Alert on `event.retry_count > 3`

## Idempotency Guarantees

### CreateLike

- **Database**: `ON CONFLICT (user_id, post_id) DO NOTHING`
- **Behavior**: Returns success even if like already exists
- **Event**: Only published for **new** likes (checked via `RETURNING id`)

### DeleteLike

- **Database**: `DELETE ... RETURNING id`
- **Behavior**: Returns success even if like doesn't exist
- **Event**: Only published if like **actually deleted**

### CreateShare

- **Database**: No unique constraint (users can share multiple times)
- **Event**: Always published

## Cache Strategy: Cache-Aside Pattern

### Write Path

1. **Write to PostgreSQL** (inside transaction)
2. **Publish event to outbox** (inside transaction)
3. **Commit transaction**
4. **Update Redis cache** (after commit, best-effort)

**Why After Commit?**
- If transaction fails, cache remains consistent (no stale data)
- If Redis fails, PostgreSQL is source of truth (cache can be rebuilt)

### Read Path

1. **Try Redis first** (`GET social:post:{post_id}:likes`)
2. **On cache miss**, query PostgreSQL
3. **Optionally warm cache** for subsequent reads

## Testing

### Unit Tests (TODO)

```bash
cargo test -p social-service --lib
```

### Integration Tests (TODO)

Requires:
- PostgreSQL running (with `outbox_events` table)
- Redis running

```bash
# Set DATABASE_URL for sqlx offline mode
export DATABASE_URL=postgresql://localhost/social_test
cargo sqlx prepare --workspace

# Run integration tests
cargo test -p social-service --test integration_tests
```

### Manual Testing with grpcurl

```bash
# Create a like
grpcurl -plaintext -d '{
  "user_id": "123e4567-e89b-12d3-a456-426614174000",
  "post_id": "223e4567-e89b-12d3-a456-426614174000"
}' localhost:50051 nova.social_service.v1.SocialService/CreateLike

# Get like count
grpcurl -plaintext -d '{
  "post_id": "223e4567-e89b-12d3-a456-426614174000"
}' localhost:50051 nova.social_service.v1.SocialService/GetLikeCount

# Unlike
grpcurl -plaintext -d '{
  "user_id": "123e4567-e89b-12d3-a456-426614174000",
  "post_id": "223e4567-e89b-12d3-a456-426614174000"
}' localhost:50051 nova.social_service.v1.SocialService/DeleteLike
```

## Observability

### Structured Logging

All operations emit structured logs with correlation IDs:

```rust
tracing::info!(
    user_id=%user_id,
    post_id=%post_id,
    like_id=%like_id,
    "Like created successfully"
);

tracing::warn!(
    post_id=%post_id,
    error=%e,
    "Failed to increment Redis counter (data is in DB)"
);
```

### Metrics (TODO: Integrate with prometheus)

- `social_like_created_total{result="success|error"}`
- `social_like_deleted_total{result="success|error"}`
- `social_redis_cache_miss_total{operation="get_like_count"}`
- `social_outbox_event_published_total{event_type="social.like.created"}`

### Tracing

Distributed tracing headers are propagated via gRPC metadata (integrated with graphql-gateway).

## Deployment

### Environment Variables

```bash
# PostgreSQL
DATABASE_URL=postgresql://user:pass@localhost/social_db
DATABASE_MAX_CONNECTIONS=50
DATABASE_CONNECT_TIMEOUT=10

# Redis
REDIS_URL=redis://localhost:6379
REDIS_MAX_CONNECTIONS=20

# gRPC Server
GRPC_PORT=50051
GRPC_REFLECTION_ENABLED=true  # Development only

# Outbox Processor (separate deployment)
OUTBOX_POLL_INTERVAL_SECS=5
OUTBOX_BATCH_SIZE=100
OUTBOX_MAX_RETRIES=5
KAFKA_BROKERS=localhost:9092
```

### K8s Deployment

Two deployments:
1. **social-service**: gRPC server (horizontal scaling, stateless)
2. **social-outbox-processor**: Background worker (single instance, leader election for HA)

## Next Steps (Agent 6)

- [ ] Implement Comment operations with same transactional-outbox pattern
- [ ] Implement BatchGetCounts with Redis MGET optimization
- [ ] Implement BatchGetLikeStatus for feed rendering
- [ ] Add prometheus metrics
- [ ] Add integration tests
- [ ] Add load tests (benchmark transactional overhead)

## References

- [Transactional Outbox Pattern](https://microservices.io/patterns/data/transactional-outbox.html)
- [Transactional-Outbox Library](../libs/transactional-outbox/README.md)
- [Cache-Aside Pattern](https://docs.microsoft.com/en-us/azure/architecture/patterns/cache-aside)
