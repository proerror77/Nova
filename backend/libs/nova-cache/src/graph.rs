//! Graph relationship caching (following, followers, is_following, etc.)
//!
//! This module provides caching for social graph operations which are
//! some of the most frequently called APIs in the system.

use crate::{
    ttl, CacheError, CacheKey, CacheOperations, CacheResult, NovaCache, CACHE_MISS_SENTINEL,
};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, warn};
use uuid::Uuid;

/// Cached following/followers list
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedRelationshipList {
    /// List of user IDs
    pub user_ids: Vec<Uuid>,
    /// Total count (may be greater than user_ids.len() for paginated results)
    pub total_count: i32,
    /// Whether there are more results
    pub has_more: bool,
    /// Cache timestamp
    pub cached_at: chrono::DateTime<chrono::Utc>,
}

/// Graph cache operations
pub struct GraphCache {
    cache: NovaCache,
}

impl GraphCache {
    pub fn new(cache: NovaCache) -> Self {
        Self { cache }
    }

    // ============= Following List =============

    /// Get cached following list for a user
    pub async fn get_following(
        &self,
        user_id: Uuid,
    ) -> CacheResult<Option<CachedRelationshipList>> {
        let key = CacheKey::following(user_id);
        self.cache.get(&key).await
    }

    /// Cache following list for a user
    pub async fn set_following(
        &self,
        user_id: Uuid,
        user_ids: Vec<Uuid>,
        total_count: i32,
        has_more: bool,
    ) -> CacheResult<()> {
        let key = CacheKey::following(user_id);
        let cached = CachedRelationshipList {
            user_ids,
            total_count,
            has_more,
            cached_at: chrono::Utc::now(),
        };
        self.cache.set(&key, &cached, ttl::FOLLOWING).await
    }

    /// Invalidate following list cache
    pub async fn invalidate_following(&self, user_id: Uuid) -> CacheResult<()> {
        let key = CacheKey::following(user_id);
        self.cache.del(&key).await
    }

    // ============= Followers List =============

    /// Get cached followers list for a user
    pub async fn get_followers(
        &self,
        user_id: Uuid,
    ) -> CacheResult<Option<CachedRelationshipList>> {
        let key = CacheKey::followers(user_id);
        self.cache.get(&key).await
    }

    /// Cache followers list for a user
    pub async fn set_followers(
        &self,
        user_id: Uuid,
        user_ids: Vec<Uuid>,
        total_count: i32,
        has_more: bool,
    ) -> CacheResult<()> {
        let key = CacheKey::followers(user_id);
        let cached = CachedRelationshipList {
            user_ids,
            total_count,
            has_more,
            cached_at: chrono::Utc::now(),
        };
        self.cache.set(&key, &cached, ttl::FOLLOWERS).await
    }

    /// Invalidate followers list cache
    pub async fn invalidate_followers(&self, user_id: Uuid) -> CacheResult<()> {
        let key = CacheKey::followers(user_id);
        self.cache.del(&key).await
    }

    // ============= Is Following Check =============

    /// Get cached is_following status
    /// Returns: Some(true/false) if cached, None if not cached
    pub async fn get_is_following(
        &self,
        follower_id: Uuid,
        followee_id: Uuid,
    ) -> CacheResult<Option<bool>> {
        let key = CacheKey::is_following(follower_id, followee_id);

        // Check for raw value to handle negative cache
        match self.cache.get_raw(&key).await? {
            Some(value) => {
                if value == CACHE_MISS_SENTINEL {
                    // Negative cache - we know they don't follow
                    Ok(Some(false))
                } else if value == "1" || value == "true" {
                    Ok(Some(true))
                } else if value == "0" || value == "false" {
                    Ok(Some(false))
                } else {
                    // Invalid data, treat as miss
                    warn!(key = %key, value = %value, "Invalid is_following cache value");
                    Ok(None)
                }
            }
            None => Ok(None),
        }
    }

    /// Cache is_following status
    pub async fn set_is_following(
        &self,
        follower_id: Uuid,
        followee_id: Uuid,
        is_following: bool,
    ) -> CacheResult<()> {
        let key = CacheKey::is_following(follower_id, followee_id);

        // Use simple "1" or "0" for boolean to save space
        let value = if is_following { "1" } else { "0" };

        let mut conn = self.cache.redis.lock().await;
        conn.set_ex::<_, _, ()>(&key, value, ttl::IS_FOLLOWING)
            .await
            .map_err(CacheError::Redis)?;

        debug!(
            follower = %follower_id,
            followee = %followee_id,
            is_following = is_following,
            "Cached is_following"
        );
        Ok(())
    }

    /// Invalidate is_following cache (both directions)
    pub async fn invalidate_is_following(
        &self,
        follower_id: Uuid,
        followee_id: Uuid,
    ) -> CacheResult<()> {
        let key = CacheKey::is_following(follower_id, followee_id);
        self.cache.del(&key).await
    }

    // ============= Batch Operations =============

    /// Batch check is_following for multiple followees
    /// Returns map of followee_id -> Option<bool> (None if not cached)
    pub async fn batch_get_is_following(
        &self,
        follower_id: Uuid,
        followee_ids: &[Uuid],
    ) -> CacheResult<HashMap<Uuid, Option<bool>>> {
        if followee_ids.is_empty() {
            return Ok(HashMap::new());
        }

        let mut conn = self.cache.redis.lock().await;
        let mut results = HashMap::with_capacity(followee_ids.len());

        // Build keys
        let keys: Vec<String> = followee_ids
            .iter()
            .map(|fid| CacheKey::is_following(follower_id, *fid))
            .collect();

        // Use MGET for batch read
        let values: Vec<Option<String>> = redis::cmd("MGET")
            .arg(&keys)
            .query_async(&mut *conn)
            .await
            .map_err(CacheError::Redis)?;

        for (followee_id, value) in followee_ids.iter().zip(values.into_iter()) {
            let result = match value {
                Some(v) if v == CACHE_MISS_SENTINEL => Some(false),
                Some(v) if v == "1" || v == "true" => Some(true),
                Some(v) if v == "0" || v == "false" => Some(false),
                _ => None,
            };
            results.insert(*followee_id, result);
        }

        Ok(results)
    }

    /// Batch set is_following for multiple followees
    pub async fn batch_set_is_following(
        &self,
        follower_id: Uuid,
        statuses: &[(Uuid, bool)],
    ) -> CacheResult<()> {
        if statuses.is_empty() {
            return Ok(());
        }

        let mut conn = self.cache.redis.lock().await;
        let mut pipe = redis::Pipeline::new();

        for (followee_id, is_following) in statuses {
            let key = CacheKey::is_following(follower_id, *followee_id);
            let value = if *is_following { "1" } else { "0" };
            pipe.set_ex(&key, value, ttl::IS_FOLLOWING);
        }

        pipe.query_async::<_, ()>(&mut *conn)
            .await
            .map_err(CacheError::Redis)?;

        debug!(
            follower = %follower_id,
            count = statuses.len(),
            "Batch cached is_following"
        );
        Ok(())
    }

    // ============= Relationship Change Invalidation =============

    /// Invalidate all caches affected by a new follow
    pub async fn on_follow_created(&self, follower_id: Uuid, followee_id: Uuid) -> CacheResult<()> {
        // Invalidate follower's following list
        self.invalidate_following(follower_id).await?;

        // Invalidate followee's followers list
        self.invalidate_followers(followee_id).await?;

        // Invalidate the is_following check
        self.invalidate_is_following(follower_id, followee_id)
            .await?;

        // Also invalidate follower's feed cache (they should see followee's posts now)
        let feed_key = CacheKey::feed(follower_id);
        let _ = self.cache.del(&feed_key).await;

        debug!(
            follower = %follower_id,
            followee = %followee_id,
            "Invalidated caches for new follow"
        );
        Ok(())
    }

    /// Invalidate all caches affected by an unfollow
    pub async fn on_follow_deleted(&self, follower_id: Uuid, followee_id: Uuid) -> CacheResult<()> {
        // Same invalidations as follow created
        self.on_follow_created(follower_id, followee_id).await
    }

    // ============= Mute/Block Caching =============

    /// Get cached is_muted status
    pub async fn get_is_muted(&self, muter_id: Uuid, mutee_id: Uuid) -> CacheResult<Option<bool>> {
        let key = CacheKey::is_muted(muter_id, mutee_id);
        match self.cache.get_raw(&key).await? {
            Some(v) if v == "1" => Ok(Some(true)),
            Some(v) if v == "0" || v == CACHE_MISS_SENTINEL => Ok(Some(false)),
            _ => Ok(None),
        }
    }

    /// Cache is_muted status
    pub async fn set_is_muted(
        &self,
        muter_id: Uuid,
        mutee_id: Uuid,
        is_muted: bool,
    ) -> CacheResult<()> {
        let key = CacheKey::is_muted(muter_id, mutee_id);
        let value = if is_muted { "1" } else { "0" };
        let mut conn = self.cache.redis.lock().await;
        conn.set_ex::<_, _, ()>(&key, value, ttl::IS_FOLLOWING)
            .await
            .map_err(CacheError::Redis)?;
        Ok(())
    }

    /// Get cached is_blocked status
    pub async fn get_is_blocked(
        &self,
        blocker_id: Uuid,
        blocked_id: Uuid,
    ) -> CacheResult<Option<bool>> {
        let key = CacheKey::is_blocked(blocker_id, blocked_id);
        match self.cache.get_raw(&key).await? {
            Some(v) if v == "1" => Ok(Some(true)),
            Some(v) if v == "0" || v == CACHE_MISS_SENTINEL => Ok(Some(false)),
            _ => Ok(None),
        }
    }

    /// Cache is_blocked status
    pub async fn set_is_blocked(
        &self,
        blocker_id: Uuid,
        blocked_id: Uuid,
        is_blocked: bool,
    ) -> CacheResult<()> {
        let key = CacheKey::is_blocked(blocker_id, blocked_id);
        let value = if is_blocked { "1" } else { "0" };
        let mut conn = self.cache.redis.lock().await;
        conn.set_ex::<_, _, ()>(&key, value, ttl::IS_FOLLOWING)
            .await
            .map_err(CacheError::Redis)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cached_relationship_list_serialization() {
        let list = CachedRelationshipList {
            user_ids: vec![Uuid::new_v4(), Uuid::new_v4()],
            total_count: 100,
            has_more: true,
            cached_at: chrono::Utc::now(),
        };

        let json = serde_json::to_string(&list).unwrap();
        let deserialized: CachedRelationshipList = serde_json::from_str(&json).unwrap();

        assert_eq!(list.user_ids.len(), deserialized.user_ids.len());
        assert_eq!(list.total_count, deserialized.total_count);
        assert_eq!(list.has_more, deserialized.has_more);
    }
}
