use redis::AsyncCommands;
use redis_utils::SharedConnectionManager;
use std::convert::TryFrom;
use std::time::Duration;
use tracing::{debug, error, warn};

use crate::error::{AppError, Result};
#[cfg(test)]
use crate::utils::redis_timeout::run_with_timeout;

/// Event deduplicator using Redis
///
/// Ensures that each event is processed exactly once by tracking event IDs
/// in Redis with a TTL. This prevents duplicate processing in case of:
/// - Kafka message redelivery
/// - Consumer restarts
/// - Network retries
///
/// # Implementation
/// - Uses Redis SET with NX (not exists) flag for atomic check-and-set
/// - TTL of 1 hour to prevent unbounded growth
/// - Key format: `events:dedup:{event_id}`
#[derive(Clone)]
pub struct EventDeduplicator {
    redis: SharedConnectionManager,
    ttl_seconds: u64,
}

impl EventDeduplicator {
    /// Create a new event deduplicator
    ///
    /// # Arguments
    /// * `redis` - Shared Redis connection manager
    /// * `ttl_seconds` - TTL for dedup keys (default: 3600 = 1 hour)
    pub fn new(redis: SharedConnectionManager, ttl_seconds: u64) -> Self {
        Self { redis, ttl_seconds }
    }

    /// Check if an event has already been processed
    ///
    /// # Arguments
    /// * `event_id` - Unique event identifier (should be globally unique)
    ///
    /// # Returns
    /// * `Result<bool>` - true if event is a duplicate, false if new
    ///
    /// # Note
    /// This method is idempotent and can be called multiple times.
    pub async fn is_duplicate(&self, event_id: &str) -> Result<bool> {
        let key = format!("events:dedup:{}", event_id);

        let mut conn = self.redis.lock().await.clone();

        // Check if key exists
        let exists: bool = conn.exists(&key).await.map_err(|e| {
            error!("Failed to check dedup key {}: {}", key, e);
            AppError::Redis(e)
        })?;

        if exists {
            debug!("Event {} is a duplicate", event_id);
        } else {
            debug!("Event {} is new", event_id);
        }

        Ok(exists)
    }

    /// Mark an event as processed
    ///
    /// # Arguments
    /// * `event_id` - Event identifier to mark as processed
    ///
    /// # Returns
    /// * `Result<bool>` - true if this is the first time marking (success),
    ///   false if already marked (race condition)
    ///
    /// # Note
    /// Uses SET NX (set if not exists) for atomic operation.
    /// If false is returned, it means another consumer already processed this event.
    pub async fn mark_processed(&self, event_id: &str) -> Result<bool> {
        let key = format!("events:dedup:{}", event_id);

        let mut conn = self.redis.lock().await.clone();

        // SET key value NX EX ttl
        // Returns true if key was set, false if already exists
        let ttl = usize::try_from(self.ttl_seconds).map_err(|_| {
            error!(
                "Configured dedup TTL {} exceeds platform limits",
                self.ttl_seconds
            );
            AppError::Validation("Deduplication TTL exceeds usize::MAX".to_string())
        })?;

        let was_set: bool = conn
            .set_options(
                &key,
                "1",
                redis::SetOptions::default()
                    .conditional_set(redis::ExistenceCheck::NX) // Only set if not exists
                    .with_expiration(redis::SetExpiry::EX(ttl)),
            )
            .await
            .map_err(|e| {
                error!("Failed to set dedup key {}: {}", key, e);
                AppError::Redis(e)
            })?;

        if was_set {
            debug!(
                "Marked event {} as processed (TTL: {}s)",
                event_id, self.ttl_seconds
            );
        } else {
            warn!(
                "Event {} was already marked as processed (race condition)",
                event_id
            );
        }

        Ok(was_set)
    }

    /// Check and mark an event in one atomic operation
    ///
    /// # Arguments
    /// * `event_id` - Event identifier
    ///
    /// # Returns
    /// * `Result<bool>` - true if event is new and was marked, false if duplicate
    ///
    /// # Note
    /// This is the recommended method for most use cases as it combines
    /// check and mark in one operation.
    pub async fn check_and_mark(&self, event_id: &str) -> Result<bool> {
        // mark_processed already uses SET NX which is atomic
        self.mark_processed(event_id).await
    }

    /// Remove an event from dedup cache (for testing/manual cleanup)
    ///
    /// # Warning
    /// This will allow the event to be processed again. Use with caution.
    pub async fn remove(&self, event_id: &str) -> Result<()> {
        let key = format!("events:dedup:{}", event_id);

        let mut conn = self.redis.lock().await.clone();

        let deleted: u32 = conn.del(&key).await.map_err(|e| {
            error!("Failed to delete dedup key {}: {}", key, e);
            AppError::Redis(e)
        })?;

        if deleted > 0 {
            warn!("Removed dedup key for event {}", event_id);
        } else {
            debug!("Dedup key for event {} did not exist", event_id);
        }

        Ok(())
    }

    /// Get TTL for an event (for monitoring)
    ///
    /// # Returns
    /// * `Result<Option<Duration>>` - Remaining TTL, or None if key doesn't exist
    pub async fn get_ttl(&self, event_id: &str) -> Result<Option<Duration>> {
        let key = format!("events:dedup:{}", event_id);

        let mut conn = self.redis.lock().await.clone();

        let ttl_seconds: i64 = conn.ttl(&key).await.map_err(|e| {
            error!("Failed to get TTL for {}: {}", key, e);
            AppError::Redis(e)
        })?;

        match ttl_seconds {
            -2 => Ok(None),                                // Key doesn't exist
            -1 => Ok(Some(Duration::from_secs(u64::MAX))), // Key exists but has no TTL (shouldn't happen)
            n if n > 0 => Ok(Some(Duration::from_secs(n as u64))),
            _ => Ok(None),
        }
    }

    /// Clear all dedup keys (for testing)
    ///
    /// # Warning
    /// This will remove ALL event dedup keys. Only use in testing.
    #[cfg(test)]
    pub async fn clear_all(&self) -> Result<()> {
        let mut conn = self.redis.lock().await.clone();

        // Scan for all dedup keys
        let keys: Vec<String> = run_with_timeout(
            redis::cmd("KEYS")
                .arg("events:dedup:*")
                .query_async(&mut conn),
        )
        .await
        .map_err(|e| {
            error!("Failed to scan dedup keys: {}", e);
            AppError::Redis(e)
        })?;

        if !keys.is_empty() {
            let deleted: usize = run_with_timeout(conn.del::<_, usize>(&keys))
                .await
                .map_err(|e| {
                    error!("Failed to delete dedup keys: {}", e);
                    AppError::Redis(e)
                })?;

            warn!("Cleared {} dedup keys", deleted);
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use redis_utils::RedisPool;

    async fn create_test_dedup_with_ttl(ttl: u64) -> EventDeduplicator {
        let redis_url =
            std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".to_string());

        let pool = RedisPool::connect(&redis_url, None)
            .await
            .expect("Failed to create Redis pool");

        EventDeduplicator::new(pool.manager(), ttl)
    }

    async fn create_test_dedup() -> EventDeduplicator {
        create_test_dedup_with_ttl(3600).await
    }

    #[tokio::test]
    #[ignore] // Requires Redis
    async fn test_dedup_lifecycle() {
        let dedup = create_test_dedup().await;
        dedup.clear_all().await.unwrap();

        let event_id = "test_event_123";

        // First check - should be new
        assert!(!dedup.is_duplicate(event_id).await.unwrap());

        // Mark as processed
        assert!(dedup.mark_processed(event_id).await.unwrap());

        // Second check - should be duplicate
        assert!(dedup.is_duplicate(event_id).await.unwrap());

        // Try to mark again - should fail
        assert!(!dedup.mark_processed(event_id).await.unwrap());

        // Remove and check again
        dedup.remove(event_id).await.unwrap();
        assert!(!dedup.is_duplicate(event_id).await.unwrap());

        // Cleanup
        dedup.clear_all().await.unwrap();
    }

    #[tokio::test]
    #[ignore] // Requires Redis
    async fn test_check_and_mark_atomic() {
        let dedup = create_test_dedup().await;
        dedup.clear_all().await.unwrap();

        let event_id = "test_atomic_456";

        // First call - should succeed
        assert!(dedup.check_and_mark(event_id).await.unwrap());

        // Second call - should fail (duplicate)
        assert!(!dedup.check_and_mark(event_id).await.unwrap());

        // Cleanup
        dedup.clear_all().await.unwrap();
    }

    #[tokio::test]
    #[ignore] // Requires Redis
    async fn test_ttl() {
        let dedup = create_test_dedup_with_ttl(10).await;
        dedup.clear_all().await.unwrap();

        let event_id = "test_ttl_789";

        // Mark with TTL
        dedup.mark_processed(event_id).await.unwrap();

        // Check TTL
        let ttl = dedup.get_ttl(event_id).await.unwrap();
        assert!(ttl.is_some());
        assert!(ttl.unwrap().as_secs() <= 10);

        // Non-existent key should return None
        let ttl = dedup.get_ttl("nonexistent").await.unwrap();
        assert!(ttl.is_none());

        // Cleanup
        dedup.clear_all().await.unwrap();
    }

    #[tokio::test]
    #[ignore] // Requires Redis
    async fn test_concurrent_mark() {
        let dedup = create_test_dedup().await;
        dedup.clear_all().await.unwrap();

        let event_id = "test_concurrent_999";

        // Simulate concurrent consumers
        let dedup1 = dedup.clone();
        let dedup2 = dedup.clone();
        let event_id1 = event_id.to_string();
        let event_id2 = event_id.to_string();

        let handle1 = tokio::spawn(async move { dedup1.check_and_mark(&event_id1).await.unwrap() });

        let handle2 = tokio::spawn(async move { dedup2.check_and_mark(&event_id2).await.unwrap() });

        let result1 = handle1.await.unwrap();
        let result2 = handle2.await.unwrap();

        // Exactly one should succeed
        assert_ne!(result1, result2);
        assert!(result1 || result2);

        // Cleanup
        dedup.clear_all().await.unwrap();
    }
}
