//! Redis-based viewer counting
//!
//! Critical design: Viewer counts MUST use Redis, not PostgreSQL
//! Reason: 100K viewers joining = 100K writes
//!   - PostgreSQL: ~10K writes/sec (saturated)
//!   - Redis: ~100K ops/sec (comfortable)

use anyhow::{Context, Result};
use redis::{aio::ConnectionManager, AsyncCommands};
use uuid::Uuid;

/// Viewer counter using Redis
#[derive(Clone)]
pub struct ViewerCounter {
    redis: ConnectionManager,
}

impl ViewerCounter {
    pub fn new(redis: ConnectionManager) -> Self {
        Self { redis }
    }

    // =========================================================================
    // Active Streams Set
    // =========================================================================

    /// Add stream to active set
    pub async fn add_active_stream(&mut self, stream_id: Uuid) -> Result<()> {
        let key = "streams:active";
        self.redis
            .sadd::<_, _, ()>(key, stream_id.to_string())
            .await
            .context("Failed to add stream to active set")?;
        Ok(())
    }

    /// Remove stream from active set
    pub async fn remove_active_stream(&mut self, stream_id: Uuid) -> Result<()> {
        let key = "streams:active";
        self.redis
            .srem::<_, _, ()>(key, stream_id.to_string())
            .await
            .context("Failed to remove stream from active set")?;
        Ok(())
    }

    /// Get count of active streams
    pub async fn count_active_streams(&mut self) -> Result<i32> {
        let key = "streams:active";
        let count: i32 = self
            .redis
            .scard(key)
            .await
            .context("Failed to count active streams")?;
        Ok(count)
    }

    // =========================================================================
    // Viewer Counting (Critical Path)
    // =========================================================================

    /// Increment viewer count (when viewer joins)
    pub async fn increment_viewers(&mut self, stream_id: Uuid) -> Result<i32> {
        let key = format!("stream:{}:viewers", stream_id);
        let new_count: i32 = self
            .redis
            .incr(&key, 1)
            .await
            .context("Failed to increment viewer count")?;

        // Update peak if necessary
        self.update_peak_if_higher(stream_id, new_count).await?;

        Ok(new_count)
    }

    /// Decrement viewer count (when viewer leaves)
    pub async fn decrement_viewers(&mut self, stream_id: Uuid) -> Result<i32> {
        let key = format!("stream:{}:viewers", stream_id);
        let new_count: i32 = self
            .redis
            .decr(&key, 1)
            .await
            .context("Failed to decrement viewer count")?;

        // Ensure count never goes negative (idempotency)
        if new_count < 0 {
            self.redis.set(&key, 0).await?;
            return Ok(0);
        }

        Ok(new_count)
    }

    /// Get current viewer count
    pub async fn get_viewer_count(&mut self, stream_id: Uuid) -> Result<i32> {
        let key = format!("stream:{}:viewers", stream_id);
        let count: Option<i32> = self.redis.get(&key).await?;
        Ok(count.unwrap_or(0))
    }

    /// Reset viewer count (when stream ends)
    pub async fn reset_viewers(&mut self, stream_id: Uuid) -> Result<()> {
        let key = format!("stream:{}:viewers", stream_id);
        self.redis.del::<_, ()>(&key).await?;
        Ok(())
    }

    // =========================================================================
    // Peak Viewer Tracking
    // =========================================================================

    /// Update peak viewer count if current is higher
    async fn update_peak_if_higher(&mut self, stream_id: Uuid, current: i32) -> Result<()> {
        let peak_key = format!("stream:{}:peak", stream_id);
        let peak: Option<i32> = self.redis.get(&peak_key).await?;

        if peak.unwrap_or(0) < current {
            // Set new peak with 24-hour TTL
            self.redis.set_ex(&peak_key, current, 86400).await?;
        }

        Ok(())
    }

    /// Get peak viewer count
    pub async fn get_peak_viewers(&mut self, stream_id: Uuid) -> Result<i32> {
        let key = format!("stream:{}:peak", stream_id);
        let peak: Option<i32> = self.redis.get(&key).await?;
        Ok(peak.unwrap_or(0))
    }

    /// Reset peak viewer count
    pub async fn reset_peak(&mut self, stream_id: Uuid) -> Result<()> {
        let key = format!("stream:{}:peak", stream_id);
        self.redis.del::<_, ()>(&key).await?;
        Ok(())
    }

    // =========================================================================
    // Stream Heartbeat (Health Check)
    // =========================================================================

    /// Update stream heartbeat (called every 10 seconds by monitor)
    pub async fn update_heartbeat(&mut self, stream_id: Uuid) -> Result<()> {
        let key = format!("stream:{}:heartbeat", stream_id);
        let timestamp = chrono::Utc::now().timestamp();
        self.redis.set_ex(&key, timestamp, 30).await?; // 30s TTL
        Ok(())
    }

    /// Check if stream is healthy (heartbeat within last 30 seconds)
    pub async fn is_stream_healthy(&mut self, stream_id: Uuid) -> Result<bool> {
        let key = format!("stream:{}:heartbeat", stream_id);
        let exists: bool = self.redis.exists(&key).await?;
        Ok(exists)
    }

    // =========================================================================
    // Batch Operations (Performance Optimization)
    // =========================================================================

    /// Get viewer counts for multiple streams (single Redis call)
    pub async fn get_viewer_counts_batch(&mut self, stream_ids: &[Uuid]) -> Result<Vec<i32>> {
        if stream_ids.is_empty() {
            return Ok(vec![]);
        }

        let keys: Vec<String> = stream_ids
            .iter()
            .map(|id| format!("stream:{}:viewers", id))
            .collect();

        let counts: Vec<Option<i32>> = self.redis.get(&keys).await?;
        Ok(counts.into_iter().map(|c| c.unwrap_or(0)).collect())
    }

    // =========================================================================
    // Cleanup
    // =========================================================================

    /// Cleanup all Redis keys for a stream (called when stream ends)
    pub async fn cleanup_stream(&mut self, stream_id: Uuid) -> Result<()> {
        let keys = vec![
            format!("stream:{}:viewers", stream_id),
            format!("stream:{}:peak", stream_id),
            format!("stream:{}:heartbeat", stream_id),
        ];

        self.redis.del::<_, ()>(keys).await?;
        self.remove_active_stream(stream_id).await?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests require Redis connection
    // Run with: cargo test --test '*' -- --ignored

    #[ignore]
    #[tokio::test]
    async fn test_increment_decrement_viewers() {
        // TODO: Setup test Redis
        // let redis = ConnectionManager::new(...).await.unwrap();
        // let mut counter = ViewerCounter::new(redis);
        // let stream_id = Uuid::new_v4();
        //
        // let count1 = counter.increment_viewers(stream_id).await.unwrap();
        // assert_eq!(count1, 1);
        //
        // let count2 = counter.increment_viewers(stream_id).await.unwrap();
        // assert_eq!(count2, 2);
        //
        // let count3 = counter.decrement_viewers(stream_id).await.unwrap();
        // assert_eq!(count3, 1);
    }

    #[ignore]
    #[tokio::test]
    async fn test_peak_tracking() {
        // TODO: Test that peak is updated when current exceeds previous peak
    }

    #[ignore]
    #[tokio::test]
    async fn test_viewer_count_never_negative() {
        // TODO: Test that decrementing below 0 resets to 0 (idempotency)
    }
}
