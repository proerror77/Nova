/// Content caching layer
///
/// This module provides:
/// - Redis-based caching for posts, comments, stories
/// - Cache invalidation strategies
/// - Cache warming utilities
pub mod feed_cache;

use crate::error::{AppError, Result};
use crate::models::Post;
// Note: Comment caching moved to social-service
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use serde::de::DeserializeOwned;
use serde::Serialize;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

pub use feed_cache::{CachedFeed, FeedCache};

/// Default cache TTL (seconds)
const DEFAULT_TTL_SECONDS: u64 = 300;

/// Redis-backed content cache helper
#[derive(Clone)]
pub struct ContentCache {
    conn: Arc<Mutex<ConnectionManager>>,
    ttl_seconds: u64,
}

impl ContentCache {
    /// Create a new cache wrapper from a Redis client (legacy constructor used in tests)
    pub async fn new(client: redis::Client, ttl_seconds: Option<u64>) -> Result<Self> {
        let manager = ConnectionManager::new(client)
            .await
            .map_err(|e| AppError::CacheError(format!("Failed to connect to Redis: {e}")))?;
        Ok(Self::with_manager(
            Arc::new(Mutex::new(manager)),
            ttl_seconds,
        ))
    }

    /// Create a new cache wrapper from an existing connection manager
    pub fn with_manager(manager: Arc<Mutex<ConnectionManager>>, ttl_seconds: Option<u64>) -> Self {
        Self {
            conn: manager,
            ttl_seconds: ttl_seconds.unwrap_or(DEFAULT_TTL_SECONDS),
        }
    }

    /// Cache a post entity
    pub async fn cache_post(&self, post: &Post) -> Result<()> {
        self.set_json(&Self::post_key(post.id), post, None).await
    }

    /// Fetch a cached post if available
    pub async fn get_post(&self, post_id: Uuid) -> Result<Option<Post>> {
        self.get_json(&Self::post_key(post_id)).await
    }

    /// Remove post from cache
    pub async fn invalidate_post(&self, post_id: Uuid) -> Result<()> {
        self.delete(&Self::post_key(post_id)).await
    }

    /// Batch get posts by IDs (avoids N+1 queries)
    /// Returns a map of post_id -> Post for cache hits
    pub async fn batch_get_posts(
        &self,
        post_ids: &[Uuid],
    ) -> Result<std::collections::HashMap<Uuid, Post>> {
        if post_ids.is_empty() {
            return Ok(std::collections::HashMap::new());
        }

        let keys: Vec<String> = post_ids.iter().map(|id| Self::post_key(*id)).collect();
        let mut conn = self.conn.lock().await;

        // Use MGET for batch retrieval
        let values: Vec<Option<String>> = redis::cmd("MGET")
            .arg(&keys)
            .query_async(&mut *conn)
            .await
            .map_err(|e| AppError::CacheError(format!("Failed to batch read from cache: {e}")))?;

        let mut result = std::collections::HashMap::with_capacity(post_ids.len());
        for (idx, value) in values.into_iter().enumerate() {
            if let Some(raw) = value {
                if let Ok(post) = serde_json::from_str::<Post>(&raw) {
                    result.insert(post_ids[idx], post);
                }
            }
        }

        tracing::debug!(
            "Batch cache lookup: {} hits out of {} requested",
            result.len(),
            post_ids.len()
        );

        Ok(result)
    }

    /// Batch cache multiple posts using pipeline
    pub async fn batch_cache_posts(&self, posts: &[Post]) -> Result<()> {
        if posts.is_empty() {
            return Ok(());
        }

        let mut conn = self.conn.lock().await;
        let mut pipeline = redis::pipe();

        for post in posts {
            let key = Self::post_key(post.id);
            let payload = serde_json::to_string(post)
                .map_err(|e| AppError::CacheError(format!("Failed to serialize post: {e}")))?;
            pipeline.set_ex(&key, payload, self.ttl_seconds);
        }

        pipeline
            .query_async::<_, ()>(&mut *conn)
            .await
            .map_err(|e| AppError::CacheError(format!("Failed to batch write to cache: {e}")))?;

        tracing::debug!("Batch cached {} posts", posts.len());
        Ok(())
    }

    /// Batch invalidate multiple posts
    pub async fn batch_invalidate_posts(&self, post_ids: &[Uuid]) -> Result<()> {
        if post_ids.is_empty() {
            return Ok(());
        }

        let keys: Vec<String> = post_ids.iter().map(|id| Self::post_key(*id)).collect();
        let mut conn = self.conn.lock().await;

        redis::cmd("DEL")
            .arg(&keys)
            .query_async::<_, ()>(&mut *conn)
            .await
            .map_err(|e| AppError::CacheError(format!("Failed to batch delete from cache: {e}")))?;

        tracing::debug!("Batch invalidated {} posts", post_ids.len());
        Ok(())
    }

    // Note: cache_comment, get_comment, invalidate_comment moved to social-service

    /// Cache an arbitrary JSON payload under a namespaced key
    pub async fn set_json<T: Serialize>(
        &self,
        key: &str,
        value: &T,
        ttl: Option<u64>,
    ) -> Result<()> {
        let payload = serde_json::to_string(value)
            .map_err(|e| AppError::CacheError(format!("Failed to serialize cache value: {e}")))?;

        let mut conn = self.conn.lock().await;
        let ttl = ttl.unwrap_or(self.ttl_seconds);

        conn.set_ex(key, payload, ttl)
            .await
            .map_err(|e| AppError::CacheError(format!("Failed to write to cache: {e}")))
    }

    /// Retrieve and deserialize JSON payload
    pub async fn get_json<T: DeserializeOwned>(&self, key: &str) -> Result<Option<T>> {
        let mut conn = self.conn.lock().await;
        let value: Option<String> = conn
            .get(key)
            .await
            .map_err(|e| AppError::CacheError(format!("Failed to read from cache: {e}")))?;

        match value {
            Some(raw) => {
                let parsed = serde_json::from_str(&raw).map_err(|e| {
                    AppError::CacheError(format!("Failed to deserialize cache value: {e}"))
                })?;
                Ok(Some(parsed))
            }
            None => Ok(None),
        }
    }

    /// Delete a cache entry by key
    pub async fn delete(&self, key: &str) -> Result<()> {
        let mut conn = self.conn.lock().await;
        conn.del(key)
            .await
            .map(|_: usize| ())
            .map_err(|e| AppError::CacheError(format!("Failed to delete cache key: {e}")))
    }

    /// Helper to build post cache key
    fn post_key(id: Uuid) -> String {
        format!("content:post:{id}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_post_key_format() {
        let id = Uuid::nil();
        assert_eq!(
            ContentCache::post_key(id),
            "content:post:00000000-0000-0000-0000-000000000000"
        );
    }

    // Note: test_comment_key_format removed - comment caching moved to social-service
}
