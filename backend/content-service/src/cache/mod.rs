/// Content caching layer
///
/// This module provides:
/// - Redis-based caching for posts, comments, stories
/// - Cache invalidation strategies
/// - Cache warming utilities
pub mod feed_cache;

use crate::error::{AppError, Result};
use crate::models::{Comment, Post};
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
    /// Create a new cache wrapper from a Redis client
    pub async fn new(client: redis::Client, ttl_seconds: Option<u64>) -> Result<Self> {
        let manager = ConnectionManager::new(client)
            .await
            .map_err(|e| AppError::CacheError(format!("Failed to connect to Redis: {e}")))?;

        Ok(Self {
            conn: Arc::new(Mutex::new(manager)),
            ttl_seconds: ttl_seconds.unwrap_or(DEFAULT_TTL_SECONDS),
        })
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

    /// Cache a comment entity
    pub async fn cache_comment(&self, comment: &Comment) -> Result<()> {
        self.set_json(&Self::comment_key(comment.id), comment, None)
            .await
    }

    /// Fetch cached comment
    pub async fn get_comment(&self, comment_id: Uuid) -> Result<Option<Comment>> {
        self.get_json(&Self::comment_key(comment_id)).await
    }

    /// Remove a comment from cache
    pub async fn invalidate_comment(&self, comment_id: Uuid) -> Result<()> {
        self.delete(&Self::comment_key(comment_id)).await
    }

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

    /// Helper to build comment cache key
    fn comment_key(id: Uuid) -> String {
        format!("content:comment:{id}")
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

    #[test]
    fn test_comment_key_format() {
        let id = Uuid::nil();
        assert_eq!(
            ContentCache::comment_key(id),
            "content:comment:00000000-0000-0000-0000-000000000000"
        );
    }
}
