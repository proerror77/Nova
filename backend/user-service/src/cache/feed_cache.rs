use redis::{aio::ConnectionManager, AsyncCommands};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::error::{AppError, Result};

/// Feed cache manager using Redis
#[derive(Clone)]
pub struct FeedCache {
    redis: ConnectionManager,
    default_ttl: Duration,
}

/// Cached feed entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedFeed {
    pub post_ids: Vec<Uuid>,
    pub total_count: usize,
    pub cached_at: i64, // Unix timestamp
}

impl FeedCache {
    /// Create a new FeedCache instance
    ///
    /// # Arguments
    /// * `redis` - Redis connection manager
    /// * `default_ttl_secs` - Default cache TTL in seconds (default: 120s)
    pub fn new(redis: ConnectionManager, default_ttl_secs: u64) -> Self {
        Self {
            redis,
            default_ttl: Duration::from_secs(default_ttl_secs),
        }
    }

    /// Generate cache key for user feed
    ///
    /// Format: `feed:v1:{user_id}:{offset}:{limit}`
    fn feed_key(user_id: Uuid, offset: u32, limit: u32) -> String {
        format!("feed:v1:{}:{}:{}", user_id, offset, limit)
    }

    /// Generate "seen posts" key for deduplication
    ///
    /// Format: `feed:seen:{user_id}`
    fn seen_key(user_id: Uuid) -> String {
        format!("feed:seen:{}", user_id)
    }

    /// Read cached feed for user
    ///
    /// # Returns
    /// * `Ok(Some(CachedFeed))` - Cache hit
    /// * `Ok(None)` - Cache miss
    /// * `Err(AppError)` - Redis error
    pub async fn read_feed_cache(
        &mut self,
        user_id: Uuid,
        offset: u32,
        limit: u32,
    ) -> Result<Option<CachedFeed>> {
        let key = Self::feed_key(user_id, offset, limit);

        match self.redis.get::<_, Option<String>>(&key).await {
            Ok(Some(data)) => {
                debug!("Feed cache HIT for user {} ({}:{})", user_id, offset, limit);
                serde_json::from_str::<CachedFeed>(&data)
                    .map(Some)
                    .map_err(|e| {
                        error!("Failed to deserialize cached feed: {}", e);
                        AppError::Internal(format!("Cache deserialization error: {}", e))
                    })
            }
            Ok(None) => {
                debug!(
                    "Feed cache MISS for user {} ({}:{})",
                    user_id, offset, limit
                );
                Ok(None)
            }
            Err(e) => {
                warn!("Redis read error for feed cache: {}", e);
                Err(AppError::Redis(e))
            }
        }
    }

    /// Write feed to cache
    ///
    /// # Arguments
    /// * `user_id` - User ID
    /// * `offset` - Offset for pagination
    /// * `limit` - Limit for pagination
    /// * `post_ids` - List of post IDs to cache
    /// * `ttl_secs` - Optional custom TTL (uses default if None)
    pub async fn write_feed_cache(
        &mut self,
        user_id: Uuid,
        offset: u32,
        limit: u32,
        post_ids: Vec<Uuid>,
        ttl_secs: Option<u64>,
    ) -> Result<()> {
        let key = Self::feed_key(user_id, offset, limit);
        let ttl = ttl_secs
            .map(Duration::from_secs)
            .unwrap_or(self.default_ttl);

        let cached_feed = CachedFeed {
            post_ids: post_ids.clone(),
            total_count: post_ids.len(),
            cached_at: chrono::Utc::now().timestamp(),
        };

        let data = serde_json::to_string(&cached_feed).map_err(|e| {
            error!("Failed to serialize feed for cache: {}", e);
            AppError::Internal(format!("Cache serialization error: {}", e))
        })?;

        // Add random jitter to TTL to prevent cache stampede
        let jitter_secs = (rand::random::<u64>() % 30) as i64; // 0-30 seconds jitter
        let final_ttl = Duration::from_secs((ttl.as_secs() as i64 + jitter_secs) as u64);

        self.redis
            .set_ex::<_, _, ()>(&key, data, final_ttl.as_secs())
            .await
            .map_err(|e| {
                warn!("Failed to write feed cache: {}", e);
                AppError::Redis(e)
            })?;

        debug!(
            "Feed cache WRITE for user {} ({}:{}) with TTL {:?}",
            user_id, offset, limit, final_ttl
        );

        Ok(())
    }

    /// Invalidate feed cache for a user
    ///
    /// Deletes all cached feed entries for the user (all offsets/limits)
    pub async fn invalidate_feed(&mut self, user_id: Uuid) -> Result<()> {
        // Pattern: feed:v1:{user_id}:*
        let pattern = format!("feed:v1:{}:*", user_id);

        // Use SCAN to find all matching keys (safer than KEYS in production)
        let mut conn = self.redis.clone();
        let keys: Vec<String> = redis::cmd("SCAN")
            .cursor_arg(0)
            .arg("MATCH")
            .arg(&pattern)
            .arg("COUNT")
            .arg(100)
            .query_async::<_, (i64, Vec<String>)>(&mut conn)
            .await
            .map(|(_, keys)| keys)
            .unwrap_or_default();

        if !keys.is_empty() {
            self.redis
                .del::<_, ()>(keys.clone())
                .await
                .map_err(AppError::Redis)?;

            debug!(
                "Feed cache INVALIDATE for user {} ({} keys deleted)",
                user_id,
                keys.len()
            );
        }

        Ok(())
    }

    /// Mark posts as seen by user (for deduplication)
    ///
    /// Stores in a Redis Set with 7-day expiry
    pub async fn mark_posts_seen(&mut self, user_id: Uuid, post_ids: &[Uuid]) -> Result<()> {
        let key = Self::seen_key(user_id);
        let post_id_strings: Vec<String> = post_ids.iter().map(|id| id.to_string()).collect();

        if post_id_strings.is_empty() {
            return Ok(());
        }

        self.redis
            .sadd::<_, _, ()>(&key, post_id_strings)
            .await
            .map_err(AppError::Redis)?;

        // Set expiry to 7 days
        self.redis
            .expire::<_, ()>(&key, 7 * 24 * 60 * 60)
            .await
            .map_err(AppError::Redis)?;

        debug!(
            "Marked {} posts as seen for user {}",
            post_ids.len(),
            user_id
        );
        Ok(())
    }

    /// Check if posts have been seen by user
    ///
    /// # Returns
    /// * `Vec<Uuid>` - List of unseen post IDs (filters out seen posts)
    pub async fn filter_unseen_posts(
        &mut self,
        user_id: Uuid,
        post_ids: &[Uuid],
    ) -> Result<Vec<Uuid>> {
        let key = Self::seen_key(user_id);

        if post_ids.is_empty() {
            return Ok(Vec::new());
        }

        let post_id_strings: Vec<String> = post_ids.iter().map(|id| id.to_string()).collect();

        // Check which posts are in the seen set
        let mut unseen = Vec::new();
        for (i, post_id_str) in post_id_strings.iter().enumerate() {
            let is_member = self
                .redis
                .sismember::<_, _, bool>(&key, post_id_str)
                .await
                .unwrap_or(false);

            if !is_member {
                unseen.push(post_ids[i]);
            }
        }

        debug!(
            "Filtered {} unseen posts from {} total for user {}",
            unseen.len(),
            post_ids.len(),
            user_id
        );

        Ok(unseen)
    }

    /// Clear seen posts tracking for user (reset)
    pub async fn clear_seen_posts(&mut self, user_id: Uuid) -> Result<()> {
        let key = Self::seen_key(user_id);

        self.redis
            .del::<_, ()>(&key)
            .await
            .map_err(AppError::Redis)?;

        debug!("Cleared seen posts tracking for user {}", user_id);
        Ok(())
    }

    /// Invalidate cache by event type
    ///
    /// # Event Types
    /// - "like": invalidate feeds of post author's followers
    /// - "new_post": invalidate feeds of post author's followers
    /// - "new_follow": invalidate caches for both follower and followee
    /// - "delete_post": invalidate feeds of all users who saw it
    pub async fn invalidate_by_event(
        &mut self,
        event_type: &str,
        user_id: Uuid,
        target_id: Option<Uuid>,
    ) -> Result<()> {
        match event_type {
            "like" | "new_post" => {
                // Invalidate feeds of all followers of the user who created content
                // In production: query followers from DB and batch invalidate
                debug!(
                    "Event '{}': invalidating feeds for followers of user {}",
                    event_type, user_id
                );

                // For now, just invalidate the user's own feed
                self.invalidate_feed(user_id).await?;
            }
            "new_follow" => {
                // Invalidate both users' feeds
                debug!(
                    "Event 'new_follow': invalidating feeds for {} and {:?}",
                    user_id, target_id
                );
                self.invalidate_feed(user_id).await?;

                if let Some(target) = target_id {
                    self.invalidate_feed(target).await?;
                }
            }
            "delete_post" => {
                // Invalidate all feeds (in production: only those who saw it)
                debug!(
                    "Event 'delete_post': invalidating feed for post author {}",
                    user_id
                );
                self.invalidate_feed(user_id).await?;
            }
            _ => {
                warn!("Unknown event type for cache invalidation: {}", event_type);
            }
        }

        Ok(())
    }

    /// Batch invalidate feeds for multiple users
    ///
    /// Iterates with SCAN and deletes matched keys in chunks to avoid blocking.
    pub async fn batch_invalidate(&mut self, user_ids: Vec<Uuid>) -> Result<()> {
        if user_ids.is_empty() {
            return Ok(());
        }

        debug!("Batch invalidating feeds for {} users", user_ids.len());

        // Iterate per user to control memory and latency
        for user_id in &user_ids {
            let pattern = format!("feed:v1:{}:*", user_id);
            let mut cursor: u64 = 0;

            loop {
                // SCAN cursor MATCH pattern COUNT 1000
                let (next_cursor, keys): (u64, Vec<String>) = redis::cmd("SCAN")
                    .arg(cursor)
                    .arg("MATCH")
                    .arg(&pattern)
                    .arg("COUNT")
                    .arg(1000)
                    .query_async(&mut self.redis)
                    .await
                    .map_err(AppError::Redis)?;

                if !keys.is_empty() {
                    let mut pipe = redis::pipe();
                    for k in keys {
                        pipe.del(k);
                    }
                    let _: () = pipe
                        .query_async(&mut self.redis)
                        .await
                        .map_err(AppError::Redis)?;
                }

                if next_cursor == 0 {
                    break;
                }
                cursor = next_cursor;
            }
        }

        debug!("Batch invalidation complete for {} users", user_ids.len());
        Ok(())
    }

    /// Warm cache for a specific user
    ///
    /// Pre-compute and store feed in cache (used by cache warming job)
    pub async fn warm_cache(&mut self, user_id: Uuid, post_ids: Vec<Uuid>) -> Result<()> {
        if post_ids.is_empty() {
            debug!("Skipping cache warm for user {} (no posts)", user_id);
            return Ok(());
        }

        // Write to cache with standard TTL
        self.write_feed_cache(user_id, 0, 20, post_ids.clone(), Some(120))
            .await?;

        debug!(
            "Cache warmed for user {} with {} posts",
            user_id,
            post_ids.len()
        );
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feed_key_format() {
        let user_id = Uuid::new_v4();
        let key = FeedCache::feed_key(user_id, 0, 20);
        assert_eq!(key, format!("feed:v1:{}:0:20", user_id));
    }

    #[test]
    fn test_seen_key_format() {
        let user_id = Uuid::new_v4();
        let key = FeedCache::seen_key(user_id);
        assert_eq!(key, format!("feed:seen:{}", user_id));
    }
}
