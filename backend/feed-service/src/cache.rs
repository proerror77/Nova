//! Redis-based caching layer for feed ranking results
//!
//! Implements multi-level caching strategy:
//! - L1: User feed cache (personalized rankings) - TTL: 5 minutes
//! - L2: Post metadata cache (post details) - TTL: 1 hour
//! - L3: User context cache (interests/preferences) - TTL: 30 minutes
//!
//! Cache keys follow the pattern:
//! - feed:{user_id}:{algorithm} → serialized GetFeedResponse
//! - post:{post_id} → serialized post metadata
//! - user_context:{user_id} → serialized user context/interests

use crate::error::{AppError, Result};
use redis::aio::ConnectionManager;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, warn};

/// Cache configuration
#[derive(Debug, Clone)]
pub struct CacheConfig {
    /// Feed cache TTL in seconds (5 minutes)
    pub feed_ttl: usize,
    /// Post metadata cache TTL in seconds (1 hour)
    pub post_ttl: usize,
    /// User context cache TTL in seconds (30 minutes)
    pub user_context_ttl: usize,
    /// Max feed cache size per user (number of posts)
    pub max_feed_size: usize,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            feed_ttl: 300,          // 5 minutes
            post_ttl: 3600,         // 1 hour
            user_context_ttl: 1800, // 30 minutes
            max_feed_size: 100,
        }
    }
}

/// Feed cache layer using Redis
#[derive(Clone)]
pub struct FeedCache {
    client: Arc<ConnectionManager>,
    config: CacheConfig,
}

impl FeedCache {
    /// Create a new feed cache instance
    pub async fn new(redis_url: &str, config: CacheConfig) -> Result<Self> {
        let client = redis::Client::open(redis_url)
            .map_err(|e| AppError::Internal(format!("Failed to create Redis client: {}", e)))?;

        let manager = ConnectionManager::new(client)
            .await
            .map_err(|e| AppError::Internal(format!("Failed to create Redis connection: {}", e)))?;

        Ok(Self {
            client: Arc::new(manager),
            config,
        })
    }

    /// Ping Redis to check connection health and keep connection alive
    ///
    /// This method should be called periodically from a background task
    /// to prevent "broken pipe" errors from stale connections.
    pub async fn ping(&self) -> Result<()> {
        redis::cmd("PING")
            .query_async::<_, String>(&mut self.client.as_ref().clone())
            .await
            .map_err(|e| {
                warn!("Redis PING failed: {}", e);
                AppError::Internal(format!("Redis health check failed: {}", e))
            })?;
        Ok(())
    }

    /// Get a clone of the connection manager for shared use
    ///
    /// Useful for passing to handlers that need direct Redis access
    pub fn connection_manager(&self) -> Arc<ConnectionManager> {
        Arc::clone(&self.client)
    }

    /// Get cached feed for user
    ///
    /// Returns serialized feed response if found in cache, None if miss/error
    pub async fn get_feed(&self, user_id: &str, algorithm: &str) -> Result<Option<CachedFeed>> {
        let key = format!("feed:{}:{}", user_id, algorithm);

        let value: Option<String> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut self.client.as_ref().clone())
            .await
            .map_err(|e| {
                warn!("Redis GET failed for {}: {}", key, e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        match value {
            Some(json) => {
                let cached = serde_json::from_str::<CachedFeed>(&json).map_err(|e| {
                    AppError::Internal(format!("Cache deserialization failed: {}", e))
                })?;
                debug!("Cache hit for feed:{}:{}", user_id, algorithm);
                Ok(Some(cached))
            }
            None => {
                debug!("Cache miss for feed:{}:{}", user_id, algorithm);
                Ok(None)
            }
        }
    }

    /// Cache feed ranking results
    ///
    /// Stores serialized feed with algorithm and timestamp
    pub async fn set_feed(&self, user_id: &str, algorithm: &str, feed: &CachedFeed) -> Result<()> {
        let key = format!("feed:{}:{}", user_id, algorithm);
        let json = serde_json::to_string(feed)
            .map_err(|e| AppError::Internal(format!("Cache serialization failed: {}", e)))?;

        redis::cmd("SETEX")
            .arg(&key)
            .arg(self.config.feed_ttl)
            .arg(&json)
            .query_async::<_, ()>(&mut self.client.as_ref().clone())
            .await
            .map_err(|e| {
                warn!("Redis SETEX failed for {}: {}", key, e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        debug!(
            "Cached feed for {}:{} with TTL={}s",
            user_id, algorithm, self.config.feed_ttl
        );
        Ok(())
    }

    /// Invalidate feed cache for a user
    ///
    /// Called when:
    /// - User follows/unfollows someone
    /// - Followed user posts new content
    /// - User's interests change
    ///
    /// Uses SCAN instead of KEYS to avoid blocking Redis
    pub async fn invalidate_feed(&self, user_id: &str) -> Result<()> {
        // Delete all algorithm variants for this user using SCAN (non-blocking)
        let pattern = format!("feed:{}:*", user_id);
        let mut cursor: u64 = 0;
        let mut total_deleted = 0;

        loop {
            // SCAN is non-blocking unlike KEYS
            let (next_cursor, keys): (u64, Vec<String>) = redis::cmd("SCAN")
                .arg(cursor)
                .arg("MATCH")
                .arg(&pattern)
                .arg("COUNT")
                .arg(100)
                .query_async(&mut self.client.as_ref().clone())
                .await
                .map_err(|e| {
                    warn!("Redis SCAN failed for {}: {}", pattern, e);
                    AppError::Internal(format!("Redis error: {}", e))
                })?;

            if !keys.is_empty() {
                redis::cmd("DEL")
                    .arg(&keys)
                    .query_async::<_, ()>(&mut self.client.as_ref().clone())
                    .await
                    .map_err(|e| {
                        warn!("Redis DEL failed: {}", e);
                        AppError::Internal(format!("Redis error: {}", e))
                    })?;
                total_deleted += keys.len();
            }

            cursor = next_cursor;
            if cursor == 0 {
                break;
            }
        }

        if total_deleted > 0 {
            debug!(
                "Invalidated {} feed caches for user {}",
                total_deleted, user_id
            );
        }

        Ok(())
    }

    /// Batch invalidate feed caches for multiple users
    ///
    /// Useful for fan-out invalidations (e.g., new post from creator)
    /// Uses SCAN instead of KEYS to avoid blocking Redis
    pub async fn batch_invalidate_feeds(&self, user_ids: &[&str]) -> Result<()> {
        let mut total_deleted = 0;

        for user_id in user_ids {
            let pattern = format!("feed:{}:*", user_id);
            let mut cursor: u64 = 0;

            loop {
                // SCAN is non-blocking unlike KEYS
                let (next_cursor, keys): (u64, Vec<String>) = redis::cmd("SCAN")
                    .arg(cursor)
                    .arg("MATCH")
                    .arg(&pattern)
                    .arg("COUNT")
                    .arg(100)
                    .query_async(&mut self.client.as_ref().clone())
                    .await
                    .map_err(|e| {
                        warn!("Redis SCAN failed for {}: {}", pattern, e);
                        AppError::Internal(format!("Redis error: {}", e))
                    })?;

                if !keys.is_empty() {
                    redis::cmd("DEL")
                        .arg(&keys)
                        .query_async::<_, ()>(&mut self.client.as_ref().clone())
                        .await
                        .map_err(|e| {
                            warn!("Redis DEL failed: {}", e);
                            AppError::Internal(format!("Redis error: {}", e))
                        })?;
                    total_deleted += keys.len();
                }

                cursor = next_cursor;
                if cursor == 0 {
                    break;
                }
            }
        }

        if total_deleted > 0 {
            debug!("Invalidated {} total feed caches", total_deleted);
        }

        Ok(())
    }

    /// Get cached post metadata
    pub async fn get_post(&self, post_id: &str) -> Result<Option<CachedPost>> {
        let key = format!("post:{}", post_id);

        let value: Option<String> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut self.client.as_ref().clone())
            .await
            .map_err(|e| {
                warn!("Redis GET failed for {}: {}", key, e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        match value {
            Some(json) => {
                let cached = serde_json::from_str::<CachedPost>(&json).map_err(|e| {
                    AppError::Internal(format!("Cache deserialization failed: {}", e))
                })?;
                Ok(Some(cached))
            }
            None => Ok(None),
        }
    }

    /// Cache post metadata
    pub async fn set_post(&self, post_id: &str, post: &CachedPost) -> Result<()> {
        let key = format!("post:{}", post_id);
        let json = serde_json::to_string(post)
            .map_err(|e| AppError::Internal(format!("Cache serialization failed: {}", e)))?;

        redis::cmd("SETEX")
            .arg(&key)
            .arg(self.config.post_ttl)
            .arg(&json)
            .query_async::<_, ()>(&mut self.client.as_ref().clone())
            .await
            .map_err(|e| {
                warn!("Redis SETEX failed for {}: {}", key, e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        Ok(())
    }

    /// Get cached user context (interests, preferences)
    pub async fn get_user_context(&self, user_id: &str) -> Result<Option<CachedUserContext>> {
        let key = format!("user_context:{}", user_id);

        let value: Option<String> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut self.client.as_ref().clone())
            .await
            .map_err(|e| {
                warn!("Redis GET failed for {}: {}", key, e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        match value {
            Some(json) => {
                let cached = serde_json::from_str::<CachedUserContext>(&json).map_err(|e| {
                    AppError::Internal(format!("Cache deserialization failed: {}", e))
                })?;
                Ok(Some(cached))
            }
            None => Ok(None),
        }
    }

    /// Cache user context
    pub async fn set_user_context(&self, user_id: &str, context: &CachedUserContext) -> Result<()> {
        let key = format!("user_context:{}", user_id);
        let json = serde_json::to_string(context)
            .map_err(|e| AppError::Internal(format!("Cache serialization failed: {}", e)))?;

        redis::cmd("SETEX")
            .arg(&key)
            .arg(self.config.user_context_ttl)
            .arg(&json)
            .query_async::<_, ()>(&mut self.client.as_ref().clone())
            .await
            .map_err(|e| {
                warn!("Redis SETEX failed for {}: {}", key, e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        Ok(())
    }

    /// Clear all feed caches (for testing/maintenance)
    pub async fn clear_all(&self) -> Result<()> {
        redis::cmd("FLUSHDB")
            .query_async::<_, ()>(&mut self.client.as_ref().clone())
            .await
            .map_err(|e| {
                warn!("Redis FLUSHDB failed: {}", e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        debug!("Cleared all feed caches");
        Ok(())
    }

    /// Get cache statistics
    pub async fn get_stats(&self) -> Result<CacheStats> {
        let info: String = redis::cmd("INFO")
            .arg("stats")
            .query_async(&mut self.client.as_ref().clone())
            .await
            .map_err(|e| {
                warn!("Redis INFO failed: {}", e);
                AppError::Internal(format!("Redis error: {}", e))
            })?;

        // Parse total_connections_received and total_commands_processed
        let mut stats = CacheStats::default();
        for line in info.lines() {
            if line.starts_with("total_connections_received:") {
                if let Ok(n) = line.split(':').nth(1).unwrap_or("0").parse() {
                    stats.total_connections = n;
                }
            } else if line.starts_with("total_commands_processed:") {
                if let Ok(n) = line.split(':').nth(1).unwrap_or("0").parse() {
                    stats.total_commands = n;
                }
            }
        }

        Ok(stats)
    }
}

/// Cached feed response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedFeed {
    pub posts: Vec<CachedFeedPost>,
    pub cursor: Option<String>,
    pub has_more: bool,
    pub total_count: u32,
    pub cached_at: i64,
}

/// Cached feed post with all required fields for FeedPost proto
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedFeedPost {
    pub id: String,
    pub user_id: String,
    pub content: String,
    pub created_at: i64,
    pub ranking_score: f64,
    pub like_count: u32,
    pub comment_count: u32,
    pub share_count: u32,
    pub bookmark_count: u32,
    #[serde(default)]
    pub media_urls: Vec<String>,
    #[serde(default)]
    pub media_type: String,
    #[serde(default)]
    pub thumbnail_urls: Vec<String>,
}

/// Cached post metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedPost {
    pub id: String,
    pub author_id: String,
    pub title: Option<String>,
    pub content_length: usize,
    pub created_at: i64,
    pub like_count: u32,
}

/// Cached user context for personalization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedUserContext {
    pub user_id: String,
    pub interests: Vec<String>,
    pub follower_count: u32,
    pub following_count: u32,
    pub engagement_score: f64,
    pub last_updated: i64,
}

/// Cache statistics
#[derive(Debug, Default)]
pub struct CacheStats {
    pub total_connections: u64,
    pub total_commands: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_cache_config_default() {
        let config = CacheConfig::default();
        assert_eq!(config.feed_ttl, 300);
        assert_eq!(config.post_ttl, 3600);
        assert_eq!(config.user_context_ttl, 1800);
    }

    #[test]
    fn test_cache_key_format() {
        let feed_key = format!("feed:{}:{}", "user-123", "ch");
        assert_eq!(feed_key, "feed:user-123:ch");

        let post_key = format!("post:{}", "post-456");
        assert_eq!(post_key, "post:post-456");

        let context_key = format!("user_context:{}", "user-789");
        assert_eq!(context_key, "user_context:user-789");
    }

    #[test]
    fn test_cached_feed_serialization() {
        let feed = CachedFeed {
            posts: vec![
                CachedFeedPost {
                    id: "post-1".to_string(),
                    user_id: "user-1".to_string(),
                    content: "Test content 1".to_string(),
                    created_at: 1234567890,
                    ranking_score: 0.95,
                    like_count: 10,
                    comment_count: 2,
                    share_count: 1,
                    bookmark_count: 0,
                    media_urls: vec![],
                    media_type: String::new(),
                    thumbnail_urls: vec![],
                },
                CachedFeedPost {
                    id: "post-2".to_string(),
                    user_id: "user-2".to_string(),
                    content: "Test content 2".to_string(),
                    created_at: 1234567891,
                    ranking_score: 0.87,
                    like_count: 20,
                    comment_count: 5,
                    share_count: 3,
                    bookmark_count: 1,
                    media_urls: vec![],
                    media_type: String::new(),
                    thumbnail_urls: vec![],
                },
            ],
            cursor: Some("cursor-123".to_string()),
            has_more: true,
            total_count: 100,
            cached_at: 1234567890,
        };

        let json = serde_json::to_string(&feed).unwrap();
        let deserialized: CachedFeed = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.posts.len(), 2);
        assert_eq!(deserialized.total_count, 100);
        assert_eq!(deserialized.posts[0].ranking_score, 0.95);
    }
}
