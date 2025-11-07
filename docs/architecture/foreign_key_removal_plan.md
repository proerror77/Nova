# Foreign Key Removal Execution Plan

> **Created**: 2025-11-07
> **Status**: 📋 Planning Phase
> **Priority**: P0 - Critical Architecture Debt
> **Impact**: All services (messaging, content, streaming, stories, experiments)

## Executive Summary

Remove 112 cross-service foreign key constraints to eliminate distributed monolith anti-pattern. Transition to application-layer validation using gRPC calls with eventual consistency.

**Timeline**: 4-6 weeks (phased rollout)

---

## Phase 0: Prerequisites ✅

### 0.1 Inventory Foreign Keys
- ✅ **Status**: Completed
- ✅ **Artifact**: `docs/architecture/foreign_key_inventory.md`
- ✅ **Finding**: 112 constraints across 30+ migration files

### 0.2 Clarify Service Boundaries
- ✅ **Status**: Completed
- ✅ **Artifact**: `docs/architecture/service_boundary_analysis.md`
- ✅ **Decision**: auth-service = single writer for users table

### 0.3 Implement gRPC Resilience
- ✅ **Status**: Completed
- ✅ **Artifact**: `backend/user-service/src/grpc/resilience.rs`
- ✅ **Features**: Circuit Breaker + Retry with exponential backoff

### 0.4 Verify auth-service has CheckUserExists RPC
- ✅ **Status**: Already exists
- ✅ **Location**: `backend/proto/services/auth_service.proto:79-85`
```protobuf
rpc CheckUserExists(CheckUserExistsRequest) returns (CheckUserExistsResponse);
```

---

## Phase 1: Add Application-Layer Validation (2 weeks)

### Goals
1. Implement gRPC-based user validation in all services
2. Run validation **in parallel** with FK constraints (safety net)
3. Monitor validation success rate (should be 100%)

### 1.1 Implement AuthServiceClient in All Services

**Services to update**:
- messaging-service
- content-service
- streaming-service
- stories-service
- experiments-service

**Implementation**:
```rust
// Example: messaging-service/src/grpc/auth_client.rs
pub struct AuthServiceClient {
    client_pool: Arc<GrpcClientPool<TonicAuthClient<Channel>>>,
    circuit_breaker: Arc<CircuitBreaker>,
    retry_policy: RetryPolicy,
}

impl AuthServiceClient {
    /// Validate user exists before INSERT
    pub async fn user_exists(&self, user_id: &str) -> Result<bool, AppError> {
        let request = CheckUserExistsRequest {
            user_id: user_id.to_string(),
        };

        let result = execute_with_retry(
            &self.circuit_breaker,
            &self.retry_policy,
            "auth-service",
            || async {
                let mut client = self.client_pool.acquire().await;
                let mut tonic_request = tonic::Request::new(request.clone());
                tonic_request.set_timeout(Duration::from_secs(2)); // Fast validation
                client.check_user_exists(tonic_request).await
            },
        ).await?;

        Ok(result.exists)
    }
}
```

### 1.2 Add Validation Before INSERT Operations

**Example: messaging-service conversations**:

```rust
// Before (with FK constraint):
pub async fn create_conversation(
    pool: &PgPool,
    created_by: Uuid,
    conversation_type: &str,
) -> Result<Conversation> {
    sqlx::query_as!(
        Conversation,
        "INSERT INTO conversations (created_by, conversation_type) VALUES ($1, $2) RETURNING *",
        created_by,  // ✅ FK constraint validates this
        conversation_type
    )
    .fetch_one(pool)
    .await?
}

// After (with application-layer validation):
pub async fn create_conversation(
    pool: &PgPool,
    auth_client: &AuthServiceClient,
    created_by: Uuid,
    conversation_type: &str,
) -> Result<Conversation> {
    // ✅ Validate user exists via gRPC
    if !auth_client.user_exists(&created_by.to_string()).await? {
        return Err(AppError::Validation(format!(
            "User {} does not exist",
            created_by
        )));
    }

    // ✅ FK constraint still active (safety net during migration)
    sqlx::query_as!(
        Conversation,
        "INSERT INTO conversations (created_by, conversation_type) VALUES ($1, $2) RETURNING *",
        created_by,
        conversation_type
    )
    .fetch_one(pool)
    .await?
}
```

### 1.3 Add Feature Flag for Validation

```rust
// config.rs
pub struct AppConfig {
    pub enforce_user_validation: bool,  // Default: true in phase 1
}

// validation.rs
pub async fn validate_user_or_fail(
    auth_client: &AuthServiceClient,
    user_id: &Uuid,
    config: &AppConfig,
) -> Result<(), AppError> {
    if !config.enforce_user_validation {
        return Ok(()); // Skip validation if flag disabled
    }

    if !auth_client.user_exists(&user_id.to_string()).await? {
        return Err(AppError::Validation(format!("User {} not found", user_id)));
    }

    Ok(())
}
```

### 1.4 Monitor Validation Success Rate

**Metrics to track**:
```rust
// Prometheus metrics
user_validation_total{service="messaging", result="success"}
user_validation_total{service="messaging", result="failure"}
user_validation_total{service="messaging", result="error"}
```

**Expected outcome**: 100% success rate (validation passes for all valid FKs)

---

## Phase 2: Remove Foreign Key Constraints (1 week)

### Goals
1. Drop all FK constraints to `users(id)`
2. Keep application-layer validation active
3. Monitor for any broken invariants

### 2.1 Generate Migration Files

**Structure**:
```
backend/migrations/
├── 100_drop_fk_messaging_service.sql
├── 101_drop_fk_content_service.sql
├── 102_drop_fk_streaming_service.sql
├── 103_drop_fk_stories_service.sql
└── 104_drop_fk_experiments_service.sql
```

**Example: 100_drop_fk_messaging_service.sql**:
```sql
-- Migration: Drop foreign keys for messaging-service
-- Phase 2: FK Removal (application-layer validation already active)

-- conversations.created_by
ALTER TABLE conversations
DROP CONSTRAINT IF EXISTS conversations_created_by_fkey;

-- conversation_participants.user_id
ALTER TABLE conversation_participants
DROP CONSTRAINT IF EXISTS conversation_participants_user_id_fkey;

-- messages.sender_id
ALTER TABLE messages
DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;

-- Add comments for future reference
COMMENT ON COLUMN conversations.created_by IS
'User UUID (validated via auth-service gRPC, no FK constraint)';

COMMENT ON COLUMN conversation_participants.user_id IS
'User UUID (validated via auth-service gRPC, no FK constraint)';

COMMENT ON COLUMN messages.sender_id IS
'User UUID (validated via auth-service gRPC, no FK constraint)';
```

### 2.2 Rollout Strategy

**Step 1**: Test in staging
```bash
# Run migrations in staging
psql $STAGING_DB < backend/migrations/100_drop_fk_messaging_service.sql

# Verify application-layer validation still works
curl -X POST https://staging.nova.com/api/conversations \
  -H "Content-Type: application/json" \
  -d '{"created_by": "invalid-uuid"}'  # Should fail validation
```

**Step 2**: Blue-Green deployment in production
```bash
# Deploy new code (with validation) to green environment
kubectl apply -f k8s/messaging-service-green.yaml

# Run migrations on production database
psql $PROD_DB < backend/migrations/100_drop_fk_messaging_service.sql

# Switch traffic to green
kubectl apply -f k8s/ingress-green.yaml

# Monitor for errors (expected: zero errors)
```

### 2.3 Rollback Plan

If validation failures occur:

```sql
-- Rollback: Re-add FK constraints (data should still be consistent)
ALTER TABLE conversations
ADD CONSTRAINT conversations_created_by_fkey
FOREIGN KEY (created_by) REFERENCES users(id);

ALTER TABLE conversation_participants
ADD CONSTRAINT conversation_participants_user_id_fkey
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE messages
ADD CONSTRAINT messages_sender_id_fkey
FOREIGN KEY (sender_id) REFERENCES users(id);
```

---

## Phase 3: Implement Eventual Consistency (2 weeks)

### Goals
1. Handle user deletion across services
2. No cascading deletes (eventual consistency via Kafka)
3. Each service cleans up its own data

### 3.1 Add Kafka Event Producer (auth-service)

```rust
// auth-service/src/services/user_service.rs
pub async fn delete_user(
    pool: &PgPool,
    kafka_producer: &FutureProducer,
    user_id: Uuid,
) -> Result<(), AppError> {
    // Soft delete user in database
    sqlx::query!(
        "UPDATE users SET deleted_at = NOW() WHERE id = $1",
        user_id
    )
    .execute(pool)
    .await?;

    // Publish user_deleted event to Kafka
    let event = UserDeletedEvent {
        user_id: user_id.to_string(),
        deleted_at: chrono::Utc::now().timestamp_millis(),
    };

    kafka_producer
        .send_json("user-events", &event)
        .await?;

    Ok(())
}
```

### 3.2 Add Kafka Event Consumers (All Services)

**Example: messaging-service**:
```rust
// messaging-service/src/kafka/user_events_consumer.rs
pub struct UserEventsConsumer {
    consumer: StreamConsumer,
    pool: PgPool,
}

impl UserEventsConsumer {
    pub async fn run(&self) {
        loop {
            match self.consumer.recv().await {
                Ok(msg) => {
                    let event: UserDeletedEvent = serde_json::from_slice(msg.payload())?;
                    self.handle_user_deleted(event).await?;
                }
                Err(e) => error!("Kafka error: {}", e),
            }
        }
    }

    async fn handle_user_deleted(&self, event: UserDeletedEvent) -> Result<()> {
        let user_id = Uuid::parse_str(&event.user_id)?;

        // Clean up user's data (equivalent to ON DELETE CASCADE)
        sqlx::query!(
            "DELETE FROM conversation_participants WHERE user_id = $1",
            user_id
        )
        .execute(&self.pool)
        .await?;

        sqlx::query!(
            "DELETE FROM messages WHERE sender_id = $1",
            user_id
        )
        .execute(&self.pool)
        .await?;

        sqlx::query!(
            "DELETE FROM conversations WHERE created_by = $1",
            user_id
        )
        .execute(&self.pool)
        .await?;

        info!("Cleaned up data for deleted user: {}", user_id);
        Ok(())
    }
}
```

### 3.3 Idempotency via Deduplication

```rust
// Prevent duplicate processing of user_deleted events
async fn handle_user_deleted(&self, event: UserDeletedEvent) -> Result<()> {
    let event_id = format!("user_deleted:{}", event.user_id);

    // Check if already processed
    if self.deduplicator.is_processed(&event_id).await? {
        debug!("Event {} already processed, skipping", event_id);
        return Ok(());
    }

    // Process event
    self.cleanup_user_data(event.user_id).await?;

    // Mark as processed
    self.deduplicator.mark_processed(&event_id).await?;

    Ok(())
}
```

---

## Phase 4: Cleanup and Monitoring (1 week)

### 4.1 Remove Feature Flags

After 2 weeks of stable operation:
```rust
// Remove enforcement flag (always validate)
- pub enforce_user_validation: bool,
+ // Validation always active, no flag needed
```

### 4.2 Add Monitoring Dashboards

**Grafana Dashboard**: "FK Removal Health"

**Panels**:
1. User validation success rate (should be >99.9%)
2. User validation latency p50/p95/p99
3. Kafka consumer lag (user_deleted events)
4. Orphaned records detection (background job)

### 4.3 Background Job: Orphaned Record Cleanup

```rust
// Cron job: Run daily to detect orphaned records
pub async fn detect_orphaned_records(
    pool: &PgPool,
    auth_client: &AuthServiceClient,
) -> Result<Vec<Uuid>> {
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar!(
        "SELECT DISTINCT user_id FROM conversation_participants"
    )
    .fetch_all(pool)
    .await?;

    let mut orphaned = Vec::new();
    for user_id in all_user_ids {
        if !auth_client.user_exists(&user_id.to_string()).await? {
            orphaned.push(user_id);
        }
    }

    if !orphaned.is_empty() {
        warn!("Found {} orphaned records: {:?}", orphaned.len(), orphaned);
    }

    Ok(orphaned)
}
```

---

## Rollback Strategy

### If Phase 1 Fails (Validation Issues)
- Disable feature flag: `enforce_user_validation = false`
- Continue relying on FK constraints
- Investigate validation failures

### If Phase 2 Fails (FK Removal Breaks System)
- Re-apply FK constraints (see 2.3)
- Code continues to work (validation still active)
- Data should still be consistent

### If Phase 3 Fails (Kafka Issues)
- Kafka is optional (cleanup enhancement)
- Services still work with orphaned records
- Run background cleanup job manually

---

## Success Criteria

- ✅ All 112 FK constraints removed
- ✅ Zero validation failures in production
- ✅ 100% Kafka event delivery for user deletions
- ✅ No orphaned records detected by background job
- ✅ All services deploy independently without database coupling
- ✅ P95 validation latency < 50ms

---

## Next Steps

1. **Week 1-2**: Implement AuthServiceClient in all services
2. **Week 2-3**: Add application-layer validation to INSERT operations
3. **Week 3-4**: Monitor validation success rate (1 week buffer)
4. **Week 4**: Generate and apply FK removal migrations
5. **Week 5-6**: Implement Kafka event consumers
6. **Week 7**: Final monitoring and cleanup

---

## Appendix: Service-Specific Validation Points

### messaging-service
- `conversations.created_by` - Validate before INSERT
- `conversation_participants.user_id` - Validate before INSERT
- `messages.sender_id` - Validate before INSERT

### content-service
- `posts.user_id` - Validate before INSERT
- `stories.user_id` - Validate before INSERT
- `story_views.viewer_id` - Validate before INSERT
- `story_close_friends.owner_id/friend_id` - Validate before INSERT
- `post_shares.user_id` - Validate before INSERT
- `bookmarks.user_id` - Validate before INSERT

### streaming-service
- `streams.broadcaster_id` - Validate before INSERT
- `viewer_sessions.viewer_id` - Validate before INSERT

### experiments-service
- `experiments.created_by` - Validate before INSERT
- `experiment_assignments.user_id` - Validate before INSERT
- `experiment_events.user_id` - Validate before INSERT
