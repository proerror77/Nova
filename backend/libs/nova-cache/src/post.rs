//! Post caching module
//!
//! Provides caching for post metadata and user interactions.

use crate::{ttl, CacheKey, CacheOperations, CacheResult, NovaCache};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Cached post metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedPost {
    pub id: Uuid,
    pub user_id: Uuid,
    pub content: Option<String>,
    pub media_urls: Vec<String>,
    pub like_count: i32,
    pub comment_count: i32,
    pub share_count: i32,
    pub created_at: DateTime<Utc>,
    pub cached_at: DateTime<Utc>,
}

/// Post cache operations
pub struct PostCache {
    cache: NovaCache,
}

impl PostCache {
    pub fn new(cache: NovaCache) -> Self {
        Self { cache }
    }

    /// Get cached post
    pub async fn get_post(&self, post_id: Uuid) -> CacheResult<Option<CachedPost>> {
        let key = CacheKey::post(post_id);
        self.cache.get(&key).await
    }

    /// Cache post metadata
    pub async fn set_post(&self, post: &CachedPost) -> CacheResult<()> {
        let key = CacheKey::post(post.id);
        self.cache.set(&key, post, ttl::POST).await
    }

    /// Invalidate post cache
    pub async fn invalidate_post(&self, post_id: Uuid) -> CacheResult<()> {
        let key = CacheKey::post(post_id);
        self.cache.del(&key).await
    }

    /// Batch get posts
    pub async fn batch_get_posts(&self, post_ids: &[Uuid]) -> CacheResult<Vec<Option<CachedPost>>> {
        if post_ids.is_empty() {
            return Ok(Vec::new());
        }

        let mut conn = self.cache.redis.lock().await;
        let keys: Vec<String> = post_ids.iter().map(|id| CacheKey::post(*id)).collect();

        let values: Vec<Option<String>> = redis::cmd("MGET")
            .arg(&keys)
            .query_async(&mut *conn)
            .await
            .map_err(crate::CacheError::Redis)?;

        let results: Vec<Option<CachedPost>> = values
            .into_iter()
            .map(|v| v.and_then(|s| serde_json::from_str(&s).ok()))
            .collect();

        Ok(results)
    }

    /// Batch cache posts
    pub async fn batch_set_posts(&self, posts: &[CachedPost]) -> CacheResult<()> {
        if posts.is_empty() {
            return Ok(());
        }

        let items: Vec<(String, &CachedPost, u64)> = posts
            .iter()
            .map(|p| (CacheKey::post(p.id), p, ttl::POST))
            .collect();

        let refs: Vec<(&str, &CachedPost, u64)> =
            items.iter().map(|(k, p, t)| (k.as_str(), *p, *t)).collect();

        self.cache.pipeline_set(&refs).await
    }

    // ============= Like Cache =============

    /// Check if user liked a post (cached)
    pub async fn get_user_liked(&self, user_id: Uuid, post_id: Uuid) -> CacheResult<Option<bool>> {
        let key = CacheKey::user_liked_post(user_id, post_id);
        match self.cache.get_raw(&key).await? {
            Some(v) if v == "1" => Ok(Some(true)),
            Some(v) if v == "0" => Ok(Some(false)),
            _ => Ok(None),
        }
    }

    /// Cache user liked status
    pub async fn set_user_liked(
        &self,
        user_id: Uuid,
        post_id: Uuid,
        liked: bool,
    ) -> CacheResult<()> {
        let key = CacheKey::user_liked_post(user_id, post_id);
        let value = if liked { "1" } else { "0" };

        let mut conn = self.cache.redis.lock().await;
        redis::cmd("SETEX")
            .arg(&key)
            .arg(ttl::FEED) // 5 minutes
            .arg(value)
            .query_async::<_, ()>(&mut *conn)
            .await
            .map_err(crate::CacheError::Redis)?;

        Ok(())
    }

    /// Invalidate user liked cache
    pub async fn invalidate_user_liked(&self, user_id: Uuid, post_id: Uuid) -> CacheResult<()> {
        let key = CacheKey::user_liked_post(user_id, post_id);
        self.cache.del(&key).await
    }

    // ============= User Posts List =============

    /// Get cached list of user's posts
    pub async fn get_user_posts(&self, user_id: Uuid) -> CacheResult<Option<Vec<Uuid>>> {
        let key = CacheKey::user_posts(user_id);
        self.cache.get(&key).await
    }

    /// Cache user's post list
    pub async fn set_user_posts(&self, user_id: Uuid, post_ids: Vec<Uuid>) -> CacheResult<()> {
        let key = CacheKey::user_posts(user_id);
        self.cache.set(&key, &post_ids, ttl::FEED).await
    }

    /// Invalidate user's post list
    pub async fn invalidate_user_posts(&self, user_id: Uuid) -> CacheResult<()> {
        let key = CacheKey::user_posts(user_id);
        self.cache.del(&key).await
    }
}
