//! Feed caching module
//!
//! Provides unified feed caching with:
//! - Feed post list caching
//! - Snapshot for fallback
//! - Seen posts tracking

use crate::{ttl, CacheKey, CacheOperations, CacheResult, NovaCache};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tracing::debug;
use uuid::Uuid;

/// Cached feed entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedFeed {
    /// Post IDs in feed order
    pub post_ids: Vec<Uuid>,
    /// Timestamp when feed was generated
    pub generated_at: DateTime<Utc>,
    /// Algorithm used (e.g., "chronological", "ranked")
    #[serde(default)]
    pub algorithm: Option<String>,
    /// Schema version for cache invalidation on structure changes
    pub schema_version: u32,
}

impl CachedFeed {
    pub const CURRENT_SCHEMA_VERSION: u32 = 2;

    pub fn new(post_ids: Vec<Uuid>, algorithm: Option<String>) -> Self {
        Self {
            post_ids,
            generated_at: Utc::now(),
            algorithm,
            schema_version: Self::CURRENT_SCHEMA_VERSION,
        }
    }

    /// Check if cache is stale based on schema version
    pub fn is_stale(&self) -> bool {
        self.schema_version < Self::CURRENT_SCHEMA_VERSION
    }
}

/// Feed cache operations
pub struct FeedCache {
    cache: NovaCache,
}

impl FeedCache {
    pub fn new(cache: NovaCache) -> Self {
        Self { cache }
    }

    /// Get cached feed for a user
    pub async fn get_feed(&self, user_id: Uuid) -> CacheResult<Option<CachedFeed>> {
        let key = CacheKey::feed(user_id);
        match self.cache.get::<CachedFeed>(&key).await? {
            Some(feed) if !feed.is_stale() => Ok(Some(feed)),
            Some(_) => {
                // Stale schema version, delete and return miss
                let _ = self.cache.del(&key).await;
                Ok(None)
            }
            None => Ok(None),
        }
    }

    /// Cache feed for a user
    pub async fn set_feed(
        &self,
        user_id: Uuid,
        post_ids: Vec<Uuid>,
        algorithm: Option<String>,
    ) -> CacheResult<()> {
        let key = CacheKey::feed(user_id);
        let feed = CachedFeed::new(post_ids, algorithm);
        self.cache.set(&key, &feed, ttl::FEED).await
    }

    /// Invalidate feed cache for a user
    pub async fn invalidate_feed(&self, user_id: Uuid) -> CacheResult<()> {
        let key = CacheKey::feed(user_id);
        self.cache.del(&key).await
    }

    /// Batch invalidate feeds for multiple users
    pub async fn batch_invalidate_feeds(&self, user_ids: &[Uuid]) -> CacheResult<()> {
        if user_ids.is_empty() {
            return Ok(());
        }

        let keys: Vec<String> = user_ids.iter().map(|id| CacheKey::feed(*id)).collect();
        let key_refs: Vec<&str> = keys.iter().map(|s| s.as_str()).collect();
        self.cache.pipeline_del(&key_refs).await?;

        debug!(count = user_ids.len(), "Batch invalidated feeds");
        Ok(())
    }

    // ============= Snapshot (for fallback) =============

    /// Get feed snapshot (no TTL, for fallback when source is down)
    pub async fn get_snapshot(&self, user_id: Uuid) -> CacheResult<Option<CachedFeed>> {
        let key = CacheKey::feed_snapshot(user_id);
        self.cache.get(&key).await
    }

    /// Save feed snapshot (no TTL)
    pub async fn set_snapshot(&self, user_id: Uuid, post_ids: Vec<Uuid>) -> CacheResult<()> {
        let key = CacheKey::feed_snapshot(user_id);
        let feed = CachedFeed::new(post_ids, None);

        // Use a very long TTL instead of no TTL for safety
        const SNAPSHOT_TTL: u64 = 7 * 24 * 60 * 60; // 7 days
        self.cache.set(&key, &feed, SNAPSHOT_TTL).await
    }

    // ============= Seen Posts Tracking =============

    /// Mark posts as seen by user
    pub async fn mark_seen(&self, user_id: Uuid, post_ids: &[Uuid]) -> CacheResult<()> {
        if post_ids.is_empty() {
            return Ok(());
        }

        let key = CacheKey::feed_seen(user_id);
        let post_strings: Vec<String> = post_ids.iter().map(|id| id.to_string()).collect();

        let mut conn = self.cache.redis.lock().await;

        // Add to set
        redis::cmd("SADD")
            .arg(&key)
            .arg(&post_strings)
            .query_async::<_, ()>(&mut *conn)
            .await
            .map_err(crate::CacheError::Redis)?;

        // Set TTL (7 days)
        redis::cmd("EXPIRE")
            .arg(&key)
            .arg(7 * 24 * 60 * 60)
            .query_async::<_, ()>(&mut *conn)
            .await
            .map_err(crate::CacheError::Redis)?;

        Ok(())
    }

    /// Filter out already seen posts
    pub async fn filter_unseen(&self, user_id: Uuid, post_ids: &[Uuid]) -> CacheResult<Vec<Uuid>> {
        if post_ids.is_empty() {
            return Ok(Vec::new());
        }

        let key = CacheKey::feed_seen(user_id);
        let post_strings: Vec<String> = post_ids.iter().map(|id| id.to_string()).collect();

        let mut conn = self.cache.redis.lock().await;

        let seen_flags: Vec<bool> = redis::cmd("SMISMEMBER")
            .arg(&key)
            .arg(&post_strings)
            .query_async(&mut *conn)
            .await
            .map_err(crate::CacheError::Redis)?;

        let unseen: Vec<Uuid> = post_ids
            .iter()
            .zip(seen_flags.iter())
            .filter_map(|(id, &seen)| if !seen { Some(*id) } else { None })
            .collect();

        Ok(unseen)
    }

    /// Clear seen posts for a user
    pub async fn clear_seen(&self, user_id: Uuid) -> CacheResult<()> {
        let key = CacheKey::feed_seen(user_id);
        self.cache.del(&key).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cached_feed_schema_version() {
        let feed = CachedFeed::new(vec![Uuid::new_v4()], None);
        assert!(!feed.is_stale());

        let old_feed = CachedFeed {
            post_ids: vec![],
            generated_at: Utc::now(),
            algorithm: None,
            schema_version: 1,
        };
        assert!(old_feed.is_stale());
    }
}
