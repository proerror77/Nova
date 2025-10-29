use redis::{aio::ConnectionManager, AsyncCommands};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::metrics::feed::{FEED_CACHE_EVENTS, FEED_CACHE_WRITE_TOTAL};

/// Feed cache manager using Redis
#[derive(Clone)]
pub struct FeedCache {
    redis: ConnectionManager,
    default_ttl: Duration,
}

/// Cached feed entry结构
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedFeed {
    pub post_ids: Vec<Uuid>,
}

impl FeedCache {
    pub fn new(redis: ConnectionManager, default_ttl_secs: u64) -> Self {
        Self {
            redis,
            default_ttl: Duration::from_secs(default_ttl_secs),
        }
    }

    fn feed_key(user_id: Uuid) -> String {
        format!("feed:v1:{}", user_id)
    }

    fn seen_key(user_id: Uuid) -> String {
        format!("feed:seen:{}", user_id)
    }

    pub async fn read_feed_cache(&self, user_id: Uuid) -> Result<Option<CachedFeed>> {
        let key = Self::feed_key(user_id);
        let mut conn = self.redis.clone();

        match conn.get::<_, Option<String>>(&key).await {
            Ok(Some(data)) => {
                debug!("Feed cache HIT for user {}", user_id);
                serde_json::from_str::<CachedFeed>(&data)
                    .map(Some)
                    .map_err(|e| {
                        error!("Failed to deserialize cached feed: {}", e);
                        FEED_CACHE_EVENTS
                            .with_label_values(&["error"])
                            .inc();
                        AppError::Internal(format!("Cache deserialization error: {}", e))
                    })
            }
            Ok(None) => {
                debug!("Feed cache MISS for user {}", user_id);
                Ok(None)
            }
            Err(e) => {
                warn!("Redis read error for feed cache: {}", e);
                FEED_CACHE_EVENTS
                    .with_label_values(&["error"])
                    .inc();
                Err(AppError::CacheError(e.to_string()))
            }
        }
    }

    pub async fn write_feed_cache(
        &self,
        user_id: Uuid,
        post_ids: Vec<Uuid>,
        ttl_secs: Option<u64>,
    ) -> Result<()> {
        let key = Self::feed_key(user_id);
        let ttl = ttl_secs
            .map(Duration::from_secs)
            .unwrap_or(self.default_ttl);

        let total_posts = post_ids.len();
        let cached_feed = CachedFeed { post_ids };

        let data = serde_json::to_string(&cached_feed).map_err(|e| {
            error!("Failed to serialize feed for cache: {}", e);
            AppError::Internal(format!("Cache serialization error: {}", e))
        })?;

        let jitter = (rand::random::<u32>() % 10) as f64 / 100.0;
        let jitter_secs = (ttl.as_secs_f64() * jitter).round() as u64;
        let final_ttl = ttl + Duration::from_secs(jitter_secs);

        let mut conn = self.redis.clone();
        conn.set_ex::<_, _, ()>(&key, data, final_ttl.as_secs())
            .await
            .map_err(|e| {
                warn!("Failed to write feed cache: {}", e);
                FEED_CACHE_WRITE_TOTAL
                    .with_label_values(&["error"])
                    .inc();
                AppError::CacheError(e.to_string())
            })?;

        debug!(
            "Feed cache WRITE for user {} ({} posts) with TTL {:?}",
            user_id, total_posts, final_ttl
        );

        FEED_CACHE_WRITE_TOTAL
            .with_label_values(&["success"])
            .inc();

        Ok(())
    }

    pub async fn invalidate_feed(&self, user_id: Uuid) -> Result<()> {
        let key = Self::feed_key(user_id);
        let mut conn = self.redis.clone();
        conn.del::<_, ()>(&key)
            .await
            .map_err(|e| AppError::CacheError(e.to_string()))?;

        debug!("Feed cache INVALIDATE for user {}", user_id);

        Ok(())
    }

    pub async fn mark_posts_seen(&self, user_id: Uuid, post_ids: &[Uuid]) -> Result<()> {
        let key = Self::seen_key(user_id);
        let post_id_strings: Vec<String> = post_ids.iter().map(|id| id.to_string()).collect();

        if post_id_strings.is_empty() {
            return Ok(());
        }

        let mut conn = self.redis.clone();
        conn.sadd::<_, _, ()>(&key, post_id_strings)
            .await
            .map_err(|e| AppError::CacheError(e.to_string()))?;

        conn.expire::<_, ()>(&key, 7 * 24 * 60 * 60)
            .await
            .map_err(|e| AppError::CacheError(e.to_string()))?;

        debug!(
            "Marked posts as seen for user {} ({} posts)",
            user_id,
            post_ids.len()
        );

        Ok(())
    }

    pub async fn filter_unseen_posts(
        &self,
        user_id: Uuid,
        post_ids: &[Uuid],
    ) -> Result<Vec<Uuid>> {
        let key = Self::seen_key(user_id);

        if post_ids.is_empty() {
            return Ok(Vec::new());
        }

        let post_id_strings: Vec<String> = post_ids.iter().map(|id| id.to_string()).collect();
        let mut conn = self.redis.clone();
        let seen_flags: Vec<bool> = conn
            .smismember::<_, _, Vec<bool>>(&key, &post_id_strings)
            .await
            .map_err(|e| AppError::CacheError(e.to_string()))?;

        let mut unseen = Vec::with_capacity(post_ids.len());
        for (idx, seen) in seen_flags.into_iter().enumerate() {
            if !seen {
                unseen.push(post_ids[idx]);
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

    pub async fn clear_seen_posts(&self, user_id: Uuid) -> Result<()> {
        let key = Self::seen_key(user_id);

        let mut conn = self.redis.clone();
        conn.del::<_, ()>(&key)
            .await
            .map_err(|e| AppError::CacheError(e.to_string()))?;

        debug!("Cleared seen posts tracking for user {}", user_id);
        Ok(())
    }

    pub async fn invalidate_by_event(
        &self,
        event_type: &str,
        user_id: Uuid,
        target_id: Option<Uuid>,
    ) -> Result<()> {
        match event_type {
            "like" | "new_post" => {
                debug!(
                    "Event '{}': invalidating feeds for followers of user {}",
                    event_type, user_id
                );
                self.invalidate_feed(user_id).await?;
            }
            "new_follow" | "unfollow" => {
                debug!(
                    "Event '{}': invalidating feeds for {} and {:?}",
                    event_type,
                    user_id, target_id
                );
                self.invalidate_feed(user_id).await?;
                if let Some(target) = target_id {
                    self.invalidate_feed(target).await?;
                }
            }
            "delete_post" => {
                debug!(
                    "Event 'delete_post': invalidating feed for post author {}",
                    user_id
                );
                self.invalidate_feed(user_id).await?;
            }
            _ => warn!("Unknown event type for cache invalidation: {}", event_type),
        }

        Ok(())
    }

    pub async fn batch_invalidate(&self, user_ids: Vec<Uuid>) -> Result<()> {
        if user_ids.is_empty() {
            return Ok(());
        }

        debug!("Batch invalidating feeds for {} users", user_ids.len());

        for user_id in user_ids {
            let key = Self::feed_key(user_id);
            let mut conn = self.redis.clone();
            redis::cmd("DEL")
                .arg(&key)
                .query_async::<_, ()>(&mut conn)
                .await
                .map_err(|e| AppError::CacheError(e.to_string()))?;
        }

        debug!("Batch invalidation complete");
        Ok(())
    }

    pub async fn warm_cache(&self, user_id: Uuid, post_ids: Vec<Uuid>) -> Result<()> {
        if post_ids.is_empty() {
            debug!("Skipping cache warm for user {} (no posts)", user_id);
            return Ok(());
        }

        self.write_feed_cache(user_id, post_ids.clone(), Some(120))
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
        let key = FeedCache::feed_key(user_id);
        assert_eq!(key, format!("feed:v1:{}", user_id));
    }

    #[test]
    fn test_seen_key_format() {
        let user_id = Uuid::new_v4();
        let key = FeedCache::seen_key(user_id);
        assert_eq!(key, format!("feed:seen:{}", user_id));
    }
}
