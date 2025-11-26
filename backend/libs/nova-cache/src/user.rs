//! User caching module
//!
//! Provides caching for user profiles.

use crate::{ttl, CacheKey, CacheOperations, CacheResult, NovaCache, CACHE_MISS_SENTINEL};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Cached user profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedUser {
    pub id: Uuid,
    pub username: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub bio: Option<String>,
    pub follower_count: i32,
    pub following_count: i32,
    pub post_count: i32,
    pub is_verified: bool,
    pub cached_at: DateTime<Utc>,
}

/// User cache operations
pub struct UserCache {
    cache: NovaCache,
}

impl UserCache {
    pub fn new(cache: NovaCache) -> Self {
        Self { cache }
    }

    /// Get cached user by ID
    pub async fn get_user(&self, user_id: Uuid) -> CacheResult<Option<CachedUser>> {
        let key = CacheKey::user(user_id);

        // Check raw value for negative cache
        match self.cache.get_raw(&key).await? {
            Some(v) if v == CACHE_MISS_SENTINEL => Ok(None),
            Some(v) => {
                match serde_json::from_str::<CachedUser>(&v) {
                    Ok(user) => Ok(Some(user)),
                    Err(_) => {
                        // Corrupted data, delete and return miss
                        let _ = self.cache.del(&key).await;
                        Ok(None)
                    }
                }
            }
            None => Ok(None),
        }
    }

    /// Cache user profile
    pub async fn set_user(&self, user: &CachedUser) -> CacheResult<()> {
        let key = CacheKey::user(user.id);
        self.cache.set(&key, user, ttl::USER).await
    }

    /// Set negative cache for non-existent user
    pub async fn set_user_not_found(&self, user_id: Uuid) -> CacheResult<()> {
        let key = CacheKey::user(user_id);
        self.cache.set_negative(&key).await
    }

    /// Invalidate user cache
    pub async fn invalidate_user(&self, user_id: Uuid) -> CacheResult<()> {
        let key = CacheKey::user(user_id);
        self.cache.del(&key).await
    }

    /// Get user by username
    pub async fn get_user_by_username(&self, username: &str) -> CacheResult<Option<Uuid>> {
        let key = CacheKey::user_by_username(username);
        self.cache.get(&key).await
    }

    /// Cache username -> user_id mapping
    pub async fn set_user_by_username(&self, username: &str, user_id: Uuid) -> CacheResult<()> {
        let key = CacheKey::user_by_username(username);
        self.cache.set(&key, &user_id, ttl::USER).await
    }

    /// Batch get users
    pub async fn batch_get_users(&self, user_ids: &[Uuid]) -> CacheResult<Vec<Option<CachedUser>>> {
        if user_ids.is_empty() {
            return Ok(Vec::new());
        }

        let mut conn = self.cache.redis.lock().await;
        let keys: Vec<String> = user_ids.iter().map(|id| CacheKey::user(*id)).collect();

        let values: Vec<Option<String>> = redis::cmd("MGET")
            .arg(&keys)
            .query_async(&mut *conn)
            .await
            .map_err(crate::CacheError::Redis)?;

        let results: Vec<Option<CachedUser>> = values
            .into_iter()
            .map(|v| {
                v.and_then(|s| {
                    if s == CACHE_MISS_SENTINEL {
                        None
                    } else {
                        serde_json::from_str(&s).ok()
                    }
                })
            })
            .collect();

        Ok(results)
    }
}
