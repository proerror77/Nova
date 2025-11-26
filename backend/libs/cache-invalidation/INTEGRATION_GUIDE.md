# Integration Guide: Cache Invalidation

**🔴 INTEGRATION STATUS: ZERO SERVICES INTEGRATED** (as of 2025-11-11)
**Priority**: P1 (Codex GPT-5 Week 3-4 Recommendation)
**Risk**: Cache coherence issues across 12 microservices

Step-by-step guide to integrate cache invalidation into existing services.

---

## Current Status Audit (2025-11-11)

### Library Status
✅ **cache-invalidation library**: Complete (589 lines, production-ready)
✅ **Examples & Tests**: Integration examples provided
✅ **Documentation**: Comprehensive guides available

### Integration Status Across Services

| Service             | Publisher | Subscriber | Integration % | Notes                          |
|---------------------|-----------|------------|---------------|--------------------------------|
| user-service        | ❌         | ❌          | 0%            | High priority - owns User data |
| content-service     | ❌         | ❌          | 0%            | High priority - owns Post data |
| graphql-gateway     | N/A       | ❌          | 0%            | High priority - aggregates all |
| feed-service        | N/A       | ❌          | 0%            | Medium priority - reads only   |
| auth-service        | ❌         | N/A         | 0%            | Medium priority - session mgmt |
| notification-svc    | ❌         | ❌          | 0%            | Medium priority                |
| messaging-service   | ❌         | ❌          | 0%            | Medium priority                |
| events-service      | N/A       | ❌          | 0%            | Low priority - analytics       |
| search-service      | N/A       | ❌          | 0%            | Low priority - rebuild index   |
| media-service       | ❌         | N/A         | 0%            | Low priority                   |
| video-service       | ❌         | N/A         | 0%            | Low priority                   |
| streaming-service   | N/A       | N/A         | 0%            | N/A - no persistent cache      |

### Cache Coherence Risks Identified

**P0 - High Risk Scenarios**:
1. **User Profile Stale Cache**:
   - user-service updates profile → graphql-gateway cache stale
   - Impact: Users see old profile data in feed/posts
   - Current Mitigation: None (relies on TTL)

2. **Post Deletion Not Reflected**:
   - content-service soft-deletes post → feed-service still shows
   - Impact: Deleted posts appear in feeds
   - Current Mitigation: None (TTL: 5 min)

3. **Session Invalidation Delay**:
   - auth-service revokes JWT → user-service still caches valid
   - Impact: Revoked sessions remain active until TTL
   - Current Mitigation: None (TTL: 15 min)

**Current Workarounds**:
- All services use short TTLs (5-60 min) to mitigate stale data
- Inefficient: Causes unnecessary cache misses and DB load

---

## Architecture Overview

```text
┌──────────────────────────────────────────────────────────────┐
│                     Service Layer                            │
│  ┌────────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ user-service   │  │ content-     │  │ graphql-        │ │
│  │                │  │ service      │  │ gateway         │ │
│  │ [Publisher]    │  │ [Publisher]  │  │ [Subscriber]    │ │
│  └────────┬───────┘  └──────┬───────┘  └────────┬────────┘ │
│           │                 │                    │          │
└───────────┼─────────────────┼────────────────────┼──────────┘
            │                 │                    │
            v                 v                    v
    ┌───────────────────────────────────────────────────┐
    │          Redis Pub/Sub (cache:invalidate)        │
    │                 Broadcast Channel                 │
    └───────────────────────────────────────────────────┘
```

## Part 1: Publisher Integration (user-service)

### Step 1.1: Add Dependency

**File**: `backend/user-service/Cargo.toml`

```toml
[dependencies]
cache-invalidation = { path = "../libs/cache-invalidation" }
# ... existing dependencies
```

### Step 1.2: Initialize Publisher in Service

**File**: `backend/user-service/src/service.rs`

```rust
use cache_invalidation::InvalidationPublisher;
use sqlx::PgPool;
use std::sync::Arc;

pub struct UserService {
    db: Arc<PgPool>,
    cache_invalidator: Arc<InvalidationPublisher>,
}

impl UserService {
    pub async fn new(db: PgPool, redis_url: &str) -> anyhow::Result<Self> {
        // Initialize cache invalidation publisher
        let cache_invalidator = InvalidationPublisher::new(
            redis_url,
            "user-service".to_string()
        ).await?;

        tracing::info!("Cache invalidation publisher initialized");

        Ok(Self {
            db: Arc::new(db),
            cache_invalidator: Arc::new(cache_invalidator),
        })
    }

    /// Update user profile
    /// ✅ Invalidates cache AFTER successful database commit
    pub async fn update_user_profile(
        &self,
        user_id: &str,
        input: UpdateUserInput,
    ) -> anyhow::Result<User> {
        // 1. Update database within transaction
        let user = sqlx::query_as::<_, User>(
            "UPDATE users
             SET name = $1, bio = $2, avatar_url = $3, updated_at = NOW()
             WHERE id = $4
             RETURNING *"
        )
        .bind(&input.name)
        .bind(&input.bio)
        .bind(&input.avatar_url)
        .bind(user_id)
        .fetch_one(self.db.as_ref())
        .await?;

        // 2. Invalidate cache ONLY after successful commit
        if let Err(e) = self.cache_invalidator.invalidate_user(user_id).await {
            tracing::error!(
                error = ?e,
                user_id = %user_id,
                "Failed to invalidate user cache - cache will expire via TTL"
            );
            // Don't fail the request - cache will expire naturally
        } else {
            tracing::debug!(user_id = %user_id, "User cache invalidated");
        }

        Ok(user)
    }

    /// Delete user (with cascade invalidation)
    pub async fn delete_user(&self, user_id: &str) -> anyhow::Result<()> {
        // 1. Delete from database
        sqlx::query("DELETE FROM users WHERE id = $1")
            .bind(user_id)
            .execute(self.db.as_ref())
            .await?;

        // 2. Invalidate user cache
        let _ = self.cache_invalidator.invalidate_user(user_id).await;

        // 3. Invalidate related caches (cascade)
        let _ = self
            .cache_invalidator
            .invalidate_pattern(&format!("feed:{}:*", user_id))
            .await;

        let _ = self
            .cache_invalidator
            .invalidate_pattern(&format!("notification:{}:*", user_id))
            .await;

        tracing::info!(user_id = %user_id, "User deleted and caches invalidated");

        Ok(())
    }

    /// Batch update users (efficient batch invalidation)
    pub async fn batch_update_users(
        &self,
        updates: Vec<(String, UpdateUserInput)>,
    ) -> anyhow::Result<Vec<User>> {
        let mut users = Vec::new();

        // 1. Batch update database (use transaction)
        let mut tx = self.db.begin().await?;

        for (user_id, input) in &updates {
            let user = sqlx::query_as::<_, User>(
                "UPDATE users
                 SET name = $1, bio = $2, updated_at = NOW()
                 WHERE id = $3
                 RETURNING *"
            )
            .bind(&input.name)
            .bind(&input.bio)
            .bind(user_id)
            .fetch_one(&mut *tx)
            .await?;

            users.push(user);
        }

        tx.commit().await?;

        // 2. Batch invalidate caches (single publish, more efficient than loop)
        let cache_keys: Vec<String> = updates
            .iter()
            .map(|(user_id, _)| format!("user:{}", user_id))
            .collect();

        if let Err(e) = self.cache_invalidator.invalidate_batch(cache_keys).await {
            tracing::error!(error = ?e, "Batch cache invalidation failed");
        }

        Ok(users)
    }
}
```

### Step 1.3: Update Main to Initialize Publisher

**File**: `backend/user-service/src/main.rs`

```rust
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Load config
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://localhost:6379".to_string());

    let database_url = std::env::var("DATABASE_URL")?;

    // Create DB pool
    let db = PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await?;

    // Create service with cache invalidation
    let service = UserService::new(db, &redis_url).await?;

    tracing::info!("User service started with cache invalidation");

    // Start gRPC server...
    Ok(())
}
```

## Part 2: Subscriber Integration (graphql-gateway)

### Step 2.1: Add Dependency

**File**: `backend/graphql-gateway/Cargo.toml`

```toml
[dependencies]
cache-invalidation = { path = "../libs/cache-invalidation" }
# ... existing dependencies
```

### Step 2.2: Create Cache Manager with Invalidation

**File**: `backend/graphql-gateway/src/cache/manager.rs`

```rust
use cache_invalidation::{
    build_cache_key, InvalidationMessage, InvalidationSubscriber, InvalidationAction,
};
use dashmap::DashMap;
use redis::aio::ConnectionManager;
use std::sync::Arc;
use tokio::task::JoinHandle;
use tracing::{debug, error, info};

/// Unified cache manager handling both Redis and in-memory caches
pub struct CacheManager {
    redis: ConnectionManager,
    memory: Arc<DashMap<String, CachedEntry>>,
    invalidation_handle: Option<JoinHandle<()>>,
}

#[derive(Clone)]
pub struct CachedEntry {
    pub data: Vec<u8>,
    pub expires_at: chrono::DateTime<chrono::Utc>,
}

impl CacheManager {
    pub async fn new(redis_url: &str) -> anyhow::Result<Self> {
        // Initialize Redis connection
        let client = redis::Client::open(redis_url)?;
        let redis = ConnectionManager::new(client).await?;

        // Initialize in-memory cache
        let memory = Arc::new(DashMap::new());

        // Initialize invalidation subscriber
        let subscriber = InvalidationSubscriber::new(redis_url).await?;

        // Clone for callback
        let redis_clone = redis.clone();
        let memory_clone = Arc::clone(&memory);

        // Subscribe to cache invalidation events
        let handle = subscriber
            .subscribe(move |msg| {
                let redis = redis_clone.clone();
                let memory = Arc::clone(&memory_clone);

                async move {
                    Self::handle_invalidation(redis, memory, msg).await
                }
            })
            .await?;

        info!("Cache invalidation subscriber started");

        Ok(Self {
            redis,
            memory,
            invalidation_handle: Some(handle),
        })
    }

    /// Handle cache invalidation message
    async fn handle_invalidation(
        mut redis: ConnectionManager,
        memory: Arc<DashMap<String, CachedEntry>>,
        msg: InvalidationMessage,
    ) -> Result<(), cache_invalidation::InvalidationError> {
        debug!(
            message_id = %msg.message_id,
            entity_type = %msg.entity_type,
            action = ?msg.action,
            source = %msg.source_service,
            "Processing cache invalidation"
        );

        match msg.action {
            InvalidationAction::Delete | InvalidationAction::Update => {
                if let Some(entity_id) = &msg.entity_id {
                    let cache_key = build_cache_key(&msg.entity_type, entity_id);

                    // Delete from Redis
                    let _: () = redis::cmd("DEL")
                        .arg(&cache_key)
                        .query_async(&mut redis)
                        .await
                        .map_err(|e| {
                            error!(error = ?e, cache_key = %cache_key, "Redis delete failed");
                            e
                        })?;

                    // Delete from memory cache
                    memory.remove(&cache_key);

                    info!(
                        cache_key = %cache_key,
                        "Cache invalidated successfully"
                    );
                }
            }
            InvalidationAction::Pattern => {
                if let Some(pattern) = &msg.pattern {
                    // Use SCAN instead of KEYS to avoid blocking Redis
                    let mut cursor: u64 = 0;
                    let mut total_deleted = 0;

                    loop {
                        let (next_cursor, keys): (u64, Vec<String>) = redis::cmd("SCAN")
                            .arg(cursor)
                            .arg("MATCH")
                            .arg(pattern)
                            .arg("COUNT")
                            .arg(100)
                            .query_async(&mut redis)
                            .await
                            .map_err(|e| {
                                error!(error = ?e, pattern = %pattern, "Redis SCAN failed");
                                e
                            })?;

                        if !keys.is_empty() {
                            // Batch delete from Redis
                            let _: () = redis::cmd("DEL")
                                .arg(&keys)
                                .query_async(&mut redis)
                                .await
                                .map_err(|e| {
                                    error!(error = ?e, "Redis batch delete failed");
                                    e
                                })?;

                            // Delete from memory cache
                            for key in &keys {
                                memory.remove(key);
                            }
                            total_deleted += keys.len();
                        }

                        cursor = next_cursor;
                        if cursor == 0 {
                            break;
                        }
                    }

                    if total_deleted > 0 {
                        info!(
                            pattern = %pattern,
                            deleted_count = total_deleted,
                            "Pattern-based cache invalidation completed"
                        );
                    } else {
                        debug!(pattern = %pattern, "No matching keys found");
                    }
                }
            }
            InvalidationAction::Batch => {
                if let Some(entity_ids) = &msg.entity_ids {
                    // Batch delete from Redis
                    if !entity_ids.is_empty() {
                        let _: () = redis::cmd("DEL")
                            .arg(entity_ids)
                            .query_async(&mut redis)
                            .await
                            .map_err(|e| {
                                error!(error = ?e, "Batch delete failed");
                                e
                            })?;

                        // Batch delete from memory cache
                        for entity_id in entity_ids {
                            memory.remove(entity_id);
                        }

                        info!(
                            batch_size = entity_ids.len(),
                            "Batch cache invalidation completed"
                        );
                    }
                }
            }
        }

        Ok(())
    }

    /// Get from cache (checks memory first, then Redis)
    pub async fn get(&self, key: &str) -> anyhow::Result<Option<Vec<u8>>> {
        // Check memory cache first
        if let Some(entry) = self.memory.get(key) {
            if entry.expires_at > chrono::Utc::now() {
                debug!(cache_key = %key, "Memory cache hit");
                return Ok(Some(entry.data.clone()));
            } else {
                // Expired - remove from memory
                drop(entry);
                self.memory.remove(key);
            }
        }

        // Check Redis cache
        let data: Option<Vec<u8>> = redis::cmd("GET")
            .arg(key)
            .query_async(&mut self.redis.clone())
            .await?;

        if data.is_some() {
            debug!(cache_key = %key, "Redis cache hit");
        } else {
            debug!(cache_key = %key, "Cache miss");
        }

        Ok(data)
    }

    /// Set cache (both Redis and memory)
    pub async fn set(&self, key: &str, value: Vec<u8>, ttl_seconds: u64) -> anyhow::Result<()> {
        // Set in Redis with TTL
        redis::cmd("SETEX")
            .arg(key)
            .arg(ttl_seconds)
            .arg(&value)
            .query_async(&mut self.redis.clone())
            .await?;

        // Set in memory cache with expiration
        let expires_at = chrono::Utc::now() + chrono::Duration::seconds(ttl_seconds as i64);
        self.memory.insert(
            key.to_string(),
            CachedEntry {
                data: value,
                expires_at,
            },
        );

        debug!(cache_key = %key, ttl_seconds = ttl_seconds, "Cache set");

        Ok(())
    }
}

impl Drop for CacheManager {
    fn drop(&mut self) {
        if let Some(handle) = self.invalidation_handle.take() {
            handle.abort();
            info!("Cache invalidation subscriber stopped");
        }
    }
}
```

### Step 2.3: Update Main to Use Cache Manager

**File**: `backend/graphql-gateway/src/main.rs`

```rust
mod cache;

use cache::CacheManager;
use std::sync::Arc;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Load config
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://localhost:6379".to_string());

    // Create cache manager with automatic invalidation
    let cache_manager = Arc::new(CacheManager::new(&redis_url).await?);

    tracing::info!("GraphQL Gateway started with cache invalidation");

    // Use cache_manager in GraphQL context...
    // let schema = Schema::build(Query, Mutation, Subscription)
    //     .data(cache_manager)
    //     .finish();

    // Start HTTP server...
    Ok(())
}
```

### Step 2.4: Use Cache in GraphQL Resolvers

**File**: `backend/graphql-gateway/src/resolvers/user.rs`

```rust
use async_graphql::{Context, Object, Result};
use cache_invalidation::build_cache_key;

pub struct UserQuery;

#[Object]
impl UserQuery {
    /// Get user by ID (with caching)
    async fn user(&self, ctx: &Context<'_>, user_id: String) -> Result<Option<User>> {
        let cache_manager = ctx.data::<Arc<CacheManager>>()?;

        // Build cache key
        let cache_key = build_cache_key(&EntityType::User, &user_id);

        // Try cache first
        if let Some(cached_data) = cache_manager.get(&cache_key).await? {
            if let Ok(user) = serde_json::from_slice::<User>(&cached_data) {
                tracing::debug!(user_id = %user_id, "User loaded from cache");
                return Ok(Some(user));
            }
        }

        // Cache miss - fetch from database/service
        let user = fetch_user_from_service(&user_id).await?;

        if let Some(ref u) = user {
            // Cache the result (TTL: 1 hour)
            let data = serde_json::to_vec(u)?;
            cache_manager.set(&cache_key, data, 3600).await?;
            tracing::debug!(user_id = %user_id, "User cached");
        }

        Ok(user)
    }
}
```

## Part 3: Environment Configuration

### Add Redis URL to .env files

**File**: `backend/.env.example`

```bash
# Redis Configuration
REDIS_URL=redis://localhost:6379

# Or for Redis Cluster
# REDIS_URL=redis://localhost:6379,localhost:6380,localhost:6381

# For production with authentication
# REDIS_URL=redis://:password@redis.production.com:6379
```

## Part 4: Testing the Integration

### Test Script

Create `backend/scripts/test-cache-invalidation.sh`:

```bash
#!/bin/bash
set -e

echo "🧪 Testing Cache Invalidation Integration"
echo "=========================================="

# Start Redis
echo "1. Starting Redis..."
docker run -d --name redis-test -p 6379:6379 redis:7-alpine
sleep 2

# Start services (in background)
echo "2. Starting user-service..."
cd backend/user-service
cargo run --release &
USER_SERVICE_PID=$!
sleep 5

echo "3. Starting graphql-gateway..."
cd ../graphql-gateway
cargo run --release &
GATEWAY_PID=$!
sleep 5

# Test scenario
echo ""
echo "4. Testing cache invalidation..."

# Subscribe to Redis Pub/Sub to monitor
echo "   Monitoring Redis Pub/Sub..."
timeout 30 redis-cli SUBSCRIBE cache:invalidate &
MONITOR_PID=$!

sleep 2

# Trigger user update via gRPC
echo "   Updating user profile..."
grpcurl -plaintext \
    -d '{"user_id": "test_user_123", "name": "John Doe"}' \
    localhost:50051 \
    user.UserService/UpdateUser

sleep 2

# Check if invalidation was received
echo "   Checking cache invalidation..."
if redis-cli GET user:test_user_123; then
    echo "   ❌ FAIL: Cache still exists"
else
    echo "   ✅ PASS: Cache invalidated successfully"
fi

# Cleanup
echo ""
echo "5. Cleaning up..."
kill $USER_SERVICE_PID $GATEWAY_PID $MONITOR_PID 2>/dev/null || true
docker stop redis-test && docker rm redis-test

echo ""
echo "✅ Test completed!"
```

### Manual Testing

```bash
# Terminal 1: Start Redis
docker run --rm -p 6379:6379 redis:7-alpine

# Terminal 2: Monitor invalidations
redis-cli SUBSCRIBE cache:invalidate

# Terminal 3: Start user-service
cd backend/user-service
cargo run

# Terminal 4: Start graphql-gateway
cd backend/graphql-gateway
cargo run

# Terminal 5: Trigger updates
grpcurl -plaintext \
    -d '{"user_id": "123", "name": "Updated Name"}' \
    localhost:50051 \
    user.UserService/UpdateUser

# Check Terminal 2 - you should see invalidation message
```

## Part 5: Monitoring & Metrics

### Add Prometheus Metrics

```rust
use prometheus::{Counter, Histogram, Registry};

pub struct InvalidationMetrics {
    pub messages_published: Counter,
    pub messages_received: Counter,
    pub invalidation_latency: Histogram,
    pub errors: Counter,
}

impl InvalidationMetrics {
    pub fn new(registry: &Registry) -> Self {
        let messages_published = Counter::new(
            "cache_invalidation_published_total",
            "Total cache invalidation messages published"
        ).unwrap();

        let messages_received = Counter::new(
            "cache_invalidation_received_total",
            "Total cache invalidation messages received"
        ).unwrap();

        let invalidation_latency = Histogram::new(
            "cache_invalidation_latency_seconds",
            "Cache invalidation latency in seconds"
        ).unwrap();

        let errors = Counter::new(
            "cache_invalidation_errors_total",
            "Total cache invalidation errors"
        ).unwrap();

        registry.register(Box::new(messages_published.clone())).unwrap();
        registry.register(Box::new(messages_received.clone())).unwrap();
        registry.register(Box::new(invalidation_latency.clone())).unwrap();
        registry.register(Box::new(errors.clone())).unwrap();

        Self {
            messages_published,
            messages_received,
            invalidation_latency,
            errors,
        }
    }
}
```

## Part 6: Production Checklist

- [ ] Redis connection pooling configured
- [ ] Fallback TTLs set on all caches (1-24 hours)
- [ ] Error handling implemented (don't fail requests)
- [ ] Metrics exported to Prometheus
- [ ] Alerts configured:
  - [ ] Invalidation latency >10ms
  - [ ] Error rate >1%
  - [ ] Subscriber disconnections
- [ ] Integration tests passing
- [ ] Load testing completed (>10k msg/sec)
- [ ] Monitoring dashboards created
- [ ] Runbook documented

## Troubleshooting

### Issue: Subscriber not receiving messages

```bash
# Check Redis connectivity
redis-cli PING

# Check active channels
redis-cli PUBSUB CHANNELS

# Monitor in real-time
redis-cli SUBSCRIBE cache:invalidate
```

### Issue: High latency

```bash
# Check Redis latency
redis-cli --latency

# Check Redis stats
redis-cli INFO stats
```

### Issue: Memory leak

```rust
// Use weak references in callbacks
let cache_weak = Arc::downgrade(&memory_cache);

subscriber.subscribe(move |msg| async move {
    if let Some(cache) = cache_weak.upgrade() {
        // Process invalidation
    }
    Ok(())
}).await?;
```

---

**Next Steps:**
1. Integrate into user-service (Part 1)
2. Integrate into graphql-gateway (Part 2)
3. Add to content-service, social-service (same pattern)
4. Run integration tests
5. Deploy to staging
6. Monitor metrics
7. Deploy to production
