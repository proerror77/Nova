//! Caching layer for GraphQL gateway
//!
//! **Multi-tier caching architecture**:
//! - L1 (query_cache): In-memory process-local cache (nanosecond latency)
//! - L2 (redis_cache): Distributed Redis cache (millisecond latency)
//!
//! **P0-7**: Distributed Redis caching to reduce N+1 queries
//! **Quick Win #5**: In-memory query response caching

pub mod query_cache;
pub mod redis_cache;

use anyhow::{Context as _, Result};
use redis::aio::ConnectionManager;
use redis::{AsyncCommands, Client};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, error, warn};

/// Redis cache configuration
#[derive(Debug, Clone)]
pub struct CacheConfig {
    /// Redis connection URL
    pub redis_url: String,
    /// Default TTL for cached items (seconds)
    pub default_ttl: u64,
    /// User profile cache TTL
    pub user_ttl: u64,
    /// Post cache TTL
    pub post_ttl: u64,
    /// Media cache TTL
    pub media_ttl: u64,
}

impl CacheConfig {
    /// Create config from environment variables
    pub fn from_env() -> Self {
        Self {
            redis_url: std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://localhost:6379".to_string()),
            default_ttl: 300, // 5 minutes
            user_ttl: 600,    // 10 minutes
            post_ttl: 300,    // 5 minutes
            media_ttl: 3600,  // 1 hour
        }
    }
}

/// Redis cache client
pub struct CacheClient {
    connection: ConnectionManager,
    config: CacheConfig,
}

impl CacheClient {
    /// Create a new cache client
    pub async fn new(config: CacheConfig) -> Result<Self> {
        let client =
            Client::open(config.redis_url.clone()).context("Failed to create Redis client")?;

        let connection = ConnectionManager::new(client)
            .await
            .context("Failed to create Redis connection manager")?;

        debug!("Redis cache initialized: {}", config.redis_url);

        Ok(Self { connection, config })
    }

    /// Get a value from cache
    pub async fn get<T: for<'de> Deserialize<'de>>(&self, key: &str) -> Result<Option<T>> {
        match self.connection.clone().get::<_, Option<String>>(key).await {
            Ok(Some(value)) => {
                debug!("Cache hit: {}", key);
                let parsed =
                    serde_json::from_str(&value).context("Failed to deserialize cached value")?;
                Ok(Some(parsed))
            }
            Ok(None) => {
                debug!("Cache miss: {}", key);
                Ok(None)
            }
            Err(e) => {
                warn!("Cache get error for key {}: {}", key, e);
                Ok(None)
            }
        }
    }

    /// Set a value in cache with default TTL
    pub async fn set<T: Serialize>(&self, key: &str, value: &T) -> Result<()> {
        self.set_with_ttl(key, value, self.config.default_ttl).await
    }

    /// Set a value in cache with custom TTL
    pub async fn set_with_ttl<T: Serialize>(&self, key: &str, value: &T, ttl: u64) -> Result<()> {
        let serialized =
            serde_json::to_string(value).context("Failed to serialize value for cache")?;

        match redis::cmd("SETEX")
            .arg(key)
            .arg(ttl)
            .arg(&serialized)
            .query_async::<_, ()>(&mut self.connection.clone())
            .await
        {
            Ok(_) => {
                debug!("Cache set: {} (TTL: {}s)", key, ttl);
                Ok(())
            }
            Err(e) => {
                warn!("Cache set error for key {}: {}", key, e);
                // Non-fatal: cache failure shouldn't block requests
                Ok(())
            }
        }
    }

    /// Delete a key from cache
    pub async fn delete(&self, key: &str) -> Result<()> {
        match self.connection.clone().del::<_, ()>(key).await {
            Ok(_) => {
                debug!("Cache invalidated: {}", key);
                Ok(())
            }
            Err(e) => {
                warn!("Cache delete error for key {}: {}", key, e);
                Ok(())
            }
        }
    }

    /// Delete multiple keys from cache
    pub async fn delete_many(&self, keys: &[&str]) -> Result<()> {
        if keys.is_empty() {
            return Ok(());
        }

        match self.connection.clone().del::<_, ()>(keys).await {
            Ok(_) => {
                debug!("Cache invalidated multiple keys: {} items", keys.len());
                Ok(())
            }
            Err(e) => {
                warn!("Cache delete_many error: {}", e);
                Ok(())
            }
        }
    }

    /// Clear all cache (be careful with this!)
    pub async fn flush_all(&self) -> Result<()> {
        match redis::cmd("FLUSHDB")
            .query_async::<_, ()>(&mut self.connection.clone())
            .await
        {
            Ok(_) => {
                warn!("Cache flushed: all keys deleted");
                Ok(())
            }
            Err(e) => {
                error!("Cache flush error: {}", e);
                Err(e.into())
            }
        }
    }

    /// Get cache statistics
    pub async fn get_stats(&self) -> Result<CacheStats> {
        match redis::cmd("INFO")
            .arg("stats")
            .query_async::<_, String>(&mut self.connection.clone())
            .await
        {
            Ok(info) => {
                // Parse Redis INFO response
                let stats = CacheStats::from_redis_info(&info);
                Ok(stats)
            }
            Err(e) => {
                warn!("Failed to get cache stats: {}", e);
                Ok(CacheStats::default())
            }
        }
    }

    /// Check if cache is healthy
    pub async fn health_check(&self) -> Result<bool> {
        match redis::cmd("PING")
            .query_async::<_, String>(&mut self.connection.clone())
            .await
        {
            Ok(response) => {
                let healthy = response.eq_ignore_ascii_case("PONG");
                if !healthy {
                    warn!(
                        "Cache health check failed: unexpected response: {}",
                        response
                    );
                }
                Ok(healthy)
            }
            Err(e) => {
                error!("Cache health check failed: {}", e);
                Ok(false)
            }
        }
    }
}

/// Cache statistics
#[derive(Debug, Clone, Default)]
pub struct CacheStats {
    pub total_connections: u64,
    pub commands_processed: u64,
    pub keyspace_hits: u64,
    pub keyspace_misses: u64,
}

impl CacheStats {
    /// Parse Redis INFO response
    fn from_redis_info(info: &str) -> Self {
        let mut stats = CacheStats::default();

        for line in info.lines() {
            if let Some(value) = line.strip_prefix("total_connections_received:") {
                stats.total_connections = value.trim().parse().unwrap_or(0);
            } else if let Some(value) = line.strip_prefix("total_commands_processed:") {
                stats.commands_processed = value.trim().parse().unwrap_or(0);
            } else if let Some(value) = line.strip_prefix("keyspace_hits:") {
                stats.keyspace_hits = value.trim().parse().unwrap_or(0);
            } else if let Some(value) = line.strip_prefix("keyspace_misses:") {
                stats.keyspace_misses = value.trim().parse().unwrap_or(0);
            }
        }

        stats
    }

    /// Calculate cache hit rate
    pub fn hit_rate(&self) -> f64 {
        let total = self.keyspace_hits + self.keyspace_misses;
        if total == 0 {
            0.0
        } else {
            (self.keyspace_hits as f64 / total as f64) * 100.0
        }
    }
}

// ============================================================================
// CACHE KEY BUILDER - Standardized key naming convention
// ============================================================================

/// Build standardized cache keys
pub struct CacheKeyBuilder;

impl CacheKeyBuilder {
    /// User profile cache key
    pub fn user_profile(user_id: &str) -> String {
        format!("user:profile:{}", user_id)
    }

    /// User settings cache key
    pub fn user_settings(user_id: &str) -> String {
        format!("user:settings:{}", user_id)
    }

    /// User posts list cache key
    pub fn user_posts(user_id: &str) -> String {
        format!("user:posts:{}", user_id)
    }

    /// Post details cache key
    pub fn post_details(post_id: &str) -> String {
        format!("post:details:{}", post_id)
    }

    /// Post comments cache key
    pub fn post_comments(post_id: &str) -> String {
        format!("post:comments:{}", post_id)
    }

    /// Media cache key
    pub fn media(media_id: &str) -> String {
        format!("media:{}", media_id)
    }

    /// Feed cache key
    pub fn feed(user_id: &str, page: usize) -> String {
        format!("feed:{}:page:{}", user_id, page)
    }

    /// Search results cache key
    pub fn search_results(query: &str, page: usize) -> String {
        let hash = format!("{:x}", md5::compute(query.as_bytes()));
        format!("search:{}:page:{}", hash, page)
    }

    /// Related posts cache key
    pub fn related_posts(post_id: &str) -> String {
        format!("post:related:{}", post_id)
    }
}

// ============================================================================
// CACHE INVALIDATION PATTERNS
// ============================================================================

/// Handle cache invalidation on mutations
pub struct CacheInvalidator {
    cache: Arc<CacheClient>,
}

impl CacheInvalidator {
    pub fn new(cache: Arc<CacheClient>) -> Self {
        Self { cache }
    }

    /// Invalidate caches when a user is updated
    pub async fn on_user_update(&self, user_id: &str) -> Result<()> {
        let keys = vec![
            CacheKeyBuilder::user_profile(user_id),
            CacheKeyBuilder::user_settings(user_id),
            CacheKeyBuilder::user_posts(user_id),
        ];

        for key in keys {
            self.cache.delete(&key).await?;
        }

        Ok(())
    }

    /// Invalidate caches when a post is created/updated/deleted
    pub async fn on_post_mutation(&self, post_id: &str, owner_id: &str) -> Result<()> {
        let keys = vec![
            CacheKeyBuilder::post_details(post_id),
            CacheKeyBuilder::post_comments(post_id),
            CacheKeyBuilder::related_posts(post_id),
            CacheKeyBuilder::user_posts(owner_id),
            // Invalidate all feed pages (could be optimized)
            format!("feed:*"),
        ];

        for key in keys {
            if key.contains('*') {
                // For wildcard keys, would need to use SCAN in production
                debug!("Wildcard invalidation: {}", key);
            } else {
                self.cache.delete(&key).await?;
            }
        }

        Ok(())
    }

    /// Invalidate caches when a comment is added
    pub async fn on_comment_added(&self, post_id: &str) -> Result<()> {
        self.cache
            .delete(&CacheKeyBuilder::post_comments(post_id))
            .await?;

        Ok(())
    }

    /// Invalidate search results (broad invalidation)
    pub async fn on_content_change(&self) -> Result<()> {
        // Would use SCAN + pattern matching in production
        debug!("Invalidating search result cache");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache_key_builder() {
        assert_eq!(CacheKeyBuilder::user_profile("user1"), "user:profile:user1");
        assert_eq!(CacheKeyBuilder::post_details("post1"), "post:details:post1");
        assert_eq!(CacheKeyBuilder::user_posts("user1"), "user:posts:user1");
        assert_eq!(CacheKeyBuilder::media("media1"), "media:media1");
    }

    #[test]
    fn test_cache_stats_hit_rate() {
        let stats = CacheStats {
            keyspace_hits: 70,
            keyspace_misses: 30,
            ..Default::default()
        };

        assert!((stats.hit_rate() - 70.0).abs() < 0.1);
    }

    #[test]
    fn test_cache_stats_no_data() {
        let stats = CacheStats::default();
        assert_eq!(stats.hit_rate(), 0.0);
    }

    #[test]
    fn test_cache_config_from_env() {
        let config = CacheConfig::from_env();
        assert!(!config.redis_url.is_empty());
        assert!(config.default_ttl > 0);
    }
}
