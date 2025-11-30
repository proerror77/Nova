//! Cached graph repository wrapper
//!
//! Wraps any GraphRepositoryTrait implementation with Redis caching.

use super::GraphRepositoryTrait;
use anyhow::Result;
use nova_cache::graph::GraphCache;
use nova_cache::NovaCache;
use std::collections::HashMap;
use std::sync::Arc;
use tracing::{debug, warn};
use uuid::Uuid;

/// Repository wrapper that adds caching to any GraphRepositoryTrait implementation
pub struct CachedGraphRepository {
    /// Inner repository (PostgreSQL, Neo4j, or DualWrite)
    inner: Arc<dyn GraphRepositoryTrait + Send + Sync>,
    /// Graph cache
    cache: GraphCache,
    /// Whether caching is enabled
    enabled: bool,
}

impl CachedGraphRepository {
    pub fn new(
        inner: Arc<dyn GraphRepositoryTrait + Send + Sync>,
        nova_cache: NovaCache,
        enabled: bool,
    ) -> Self {
        Self {
            inner,
            cache: GraphCache::new(nova_cache),
            enabled,
        }
    }

    /// Get cache hit/miss stats for monitoring
    #[allow(dead_code)] // Reserved for cache metrics endpoint
    pub fn is_cache_enabled(&self) -> bool {
        self.enabled
    }
}

#[async_trait::async_trait]
impl GraphRepositoryTrait for CachedGraphRepository {
    async fn create_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        // Execute the write
        self.inner.create_follow(follower_id, followee_id).await?;

        // Invalidate caches
        if self.enabled {
            if let Err(e) = self.cache.on_follow_created(follower_id, followee_id).await {
                warn!(
                    error = %e,
                    follower = %follower_id,
                    followee = %followee_id,
                    "Failed to invalidate cache after follow creation"
                );
            }
        }

        Ok(())
    }

    async fn delete_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        // Execute the delete
        self.inner.delete_follow(follower_id, followee_id).await?;

        // Invalidate caches
        if self.enabled {
            if let Err(e) = self.cache.on_follow_deleted(follower_id, followee_id).await {
                warn!(
                    error = %e,
                    follower = %follower_id,
                    followee = %followee_id,
                    "Failed to invalidate cache after follow deletion"
                );
            }
        }

        Ok(())
    }

    async fn create_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        self.inner.create_mute(muter_id, mutee_id).await?;

        // Invalidate mute cache
        if self.enabled {
            let _ = self.cache.set_is_muted(muter_id, mutee_id, true).await;
        }

        Ok(())
    }

    async fn delete_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        self.inner.delete_mute(muter_id, mutee_id).await?;

        // Invalidate mute cache
        if self.enabled {
            let _ = self.cache.set_is_muted(muter_id, mutee_id, false).await;
        }

        Ok(())
    }

    async fn create_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        self.inner.create_block(blocker_id, blocked_id).await?;

        // Invalidate block cache
        if self.enabled {
            let _ = self
                .cache
                .set_is_blocked(blocker_id, blocked_id, true)
                .await;
        }

        Ok(())
    }

    async fn delete_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        self.inner.delete_block(blocker_id, blocked_id).await?;

        // Invalidate block cache
        if self.enabled {
            let _ = self
                .cache
                .set_is_blocked(blocker_id, blocked_id, false)
                .await;
        }

        Ok(())
    }

    async fn get_followers(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        // Only cache the first page (offset 0) to keep cache simple
        if self.enabled && offset == 0 {
            // Try cache first
            match self.cache.get_followers(user_id).await {
                Ok(Some(cached)) => {
                    debug!(user = %user_id, "Cache HIT for followers");
                    // Apply limit to cached results
                    let limited: Vec<Uuid> =
                        cached.user_ids.into_iter().take(limit as usize).collect();
                    let has_more = (limit as i32) < cached.total_count;
                    return Ok((limited, cached.total_count, has_more));
                }
                Ok(None) => {
                    debug!(user = %user_id, "Cache MISS for followers");
                }
                Err(e) => {
                    warn!(user = %user_id, error = %e, "Cache error for followers");
                }
            }
        }

        // Fetch from database
        let (followers, total_count, has_more) =
            self.inner.get_followers(user_id, limit, offset).await?;

        // Cache the result (only first page)
        if self.enabled && offset == 0 {
            if let Err(e) = self
                .cache
                .set_followers(user_id, followers.clone(), total_count, has_more)
                .await
            {
                warn!(user = %user_id, error = %e, "Failed to cache followers");
            }
        }

        Ok((followers, total_count, has_more))
    }

    async fn get_following(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        // Only cache the first page (offset 0)
        if self.enabled && offset == 0 {
            // Try cache first
            match self.cache.get_following(user_id).await {
                Ok(Some(cached)) => {
                    debug!(user = %user_id, "Cache HIT for following");
                    let limited: Vec<Uuid> =
                        cached.user_ids.into_iter().take(limit as usize).collect();
                    let has_more = (limit as i32) < cached.total_count;
                    return Ok((limited, cached.total_count, has_more));
                }
                Ok(None) => {
                    debug!(user = %user_id, "Cache MISS for following");
                }
                Err(e) => {
                    warn!(user = %user_id, error = %e, "Cache error for following");
                }
            }
        }

        // Fetch from database
        let (following, total_count, has_more) =
            self.inner.get_following(user_id, limit, offset).await?;

        // Cache the result (only first page)
        if self.enabled && offset == 0 {
            if let Err(e) = self
                .cache
                .set_following(user_id, following.clone(), total_count, has_more)
                .await
            {
                warn!(user = %user_id, error = %e, "Failed to cache following");
            }
        }

        Ok((following, total_count, has_more))
    }

    async fn is_following(&self, follower_id: Uuid, followee_id: Uuid) -> Result<bool> {
        if self.enabled {
            // Try cache first
            match self.cache.get_is_following(follower_id, followee_id).await {
                Ok(Some(is_following)) => {
                    debug!(
                        follower = %follower_id,
                        followee = %followee_id,
                        "Cache HIT for is_following"
                    );
                    return Ok(is_following);
                }
                Ok(None) => {
                    debug!(
                        follower = %follower_id,
                        followee = %followee_id,
                        "Cache MISS for is_following"
                    );
                }
                Err(e) => {
                    warn!(
                        follower = %follower_id,
                        followee = %followee_id,
                        error = %e,
                        "Cache error for is_following"
                    );
                }
            }
        }

        // Fetch from database
        let is_following = self.inner.is_following(follower_id, followee_id).await?;

        // Cache the result
        if self.enabled {
            if let Err(e) = self
                .cache
                .set_is_following(follower_id, followee_id, is_following)
                .await
            {
                warn!(
                    follower = %follower_id,
                    followee = %followee_id,
                    error = %e,
                    "Failed to cache is_following"
                );
            }
        }

        Ok(is_following)
    }

    async fn is_muted(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<bool> {
        if self.enabled {
            if let Ok(Some(is_muted)) = self.cache.get_is_muted(muter_id, mutee_id).await {
                return Ok(is_muted);
            }
        }

        let is_muted = self.inner.is_muted(muter_id, mutee_id).await?;

        if self.enabled {
            let _ = self.cache.set_is_muted(muter_id, mutee_id, is_muted).await;
        }

        Ok(is_muted)
    }

    async fn is_blocked(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<bool> {
        if self.enabled {
            if let Ok(Some(is_blocked)) = self.cache.get_is_blocked(blocker_id, blocked_id).await {
                return Ok(is_blocked);
            }
        }

        let is_blocked = self.inner.is_blocked(blocker_id, blocked_id).await?;

        if self.enabled {
            let _ = self
                .cache
                .set_is_blocked(blocker_id, blocked_id, is_blocked)
                .await;
        }

        Ok(is_blocked)
    }

    async fn batch_check_following(
        &self,
        follower_id: Uuid,
        followee_ids: Vec<Uuid>,
    ) -> Result<HashMap<String, bool>> {
        if followee_ids.is_empty() {
            return Ok(HashMap::new());
        }

        let mut results = HashMap::with_capacity(followee_ids.len());
        let mut uncached_ids = Vec::new();

        if self.enabled {
            // Check cache for each followee
            match self
                .cache
                .batch_get_is_following(follower_id, &followee_ids)
                .await
            {
                Ok(cached_results) => {
                    for (followee_id, cached) in cached_results {
                        match cached {
                            Some(is_following) => {
                                results.insert(followee_id.to_string(), is_following);
                            }
                            None => {
                                uncached_ids.push(followee_id);
                            }
                        }
                    }
                }
                Err(e) => {
                    warn!(error = %e, "Batch cache lookup failed, falling back to DB");
                    uncached_ids = followee_ids.clone();
                }
            }
        } else {
            uncached_ids = followee_ids.clone();
        }

        // Fetch uncached from database
        if !uncached_ids.is_empty() {
            let db_results = self
                .inner
                .batch_check_following(follower_id, uncached_ids.clone())
                .await?;

            // Cache the results
            if self.enabled {
                let cache_items: Vec<(Uuid, bool)> = uncached_ids
                    .iter()
                    .filter_map(|id| {
                        db_results
                            .get(&id.to_string())
                            .map(|&is_following| (*id, is_following))
                    })
                    .collect();

                if let Err(e) = self
                    .cache
                    .batch_set_is_following(follower_id, &cache_items)
                    .await
                {
                    warn!(error = %e, "Failed to batch cache is_following results");
                }
            }

            results.extend(db_results);
        }

        Ok(results)
    }

    async fn get_blocked_users(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        // For blocked users, we don't cache the list to keep it simple
        // Block relationship changes are already cached individually via is_blocked
        self.inner.get_blocked_users(user_id, limit, offset).await
    }

    async fn health_check(&self) -> Result<()> {
        self.inner.health_check().await
    }
}
