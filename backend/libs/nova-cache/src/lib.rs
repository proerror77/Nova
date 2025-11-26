//! Nova unified caching layer
//!
//! Provides a consistent caching strategy across all microservices with:
//! - Unified key schema with versioning
//! - Negative caching (cache miss sentinel)
//! - SCAN-based pattern invalidation (no blocking KEYS)
//! - Pipeline support for batch operations
//! - Metrics integration

mod error;
mod keys;
mod metrics;

pub mod feed;
pub mod graph;
pub mod post;
pub mod user;

pub use error::{CacheError, CacheResult};
pub use keys::{CacheKey, CACHE_VERSION};
pub use metrics::CacheMetrics;

use redis::aio::ConnectionManager;
use redis::{AsyncCommands, Pipeline};
use serde::{de::DeserializeOwned, Serialize};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tracing::{debug, warn};

/// Shared Redis connection manager
pub type SharedRedis = Arc<Mutex<ConnectionManager>>;

/// Cache miss sentinel value - used for negative caching
pub const CACHE_MISS_SENTINEL: &str = "__nova_cache_miss__";

/// Default TTL values (seconds)
pub mod ttl {
    pub const FEED: u64 = 300; // 5 minutes
    pub const FOLLOWING: u64 = 1800; // 30 minutes
    pub const FOLLOWERS: u64 = 1800; // 30 minutes
    pub const IS_FOLLOWING: u64 = 1800; // 30 minutes
    pub const POST: u64 = 3600; // 1 hour
    pub const USER: u64 = 3600; // 1 hour
    pub const SEARCH: u64 = 3600; // 1 hour
    pub const NEGATIVE: u64 = 60; // 1 minute for cache miss
}

/// Core cache operations trait
#[async_trait::async_trait]
pub trait CacheOperations: Send + Sync {
    /// Get a value from cache
    async fn get<T: DeserializeOwned + Send>(&self, key: &str) -> CacheResult<Option<T>>;

    /// Set a value in cache with TTL
    async fn set<T: Serialize + Send + Sync>(
        &self,
        key: &str,
        value: &T,
        ttl_secs: u64,
    ) -> CacheResult<()>;

    /// Delete a key from cache
    async fn del(&self, key: &str) -> CacheResult<()>;

    /// Check if key exists
    async fn exists(&self, key: &str) -> CacheResult<bool>;

    /// Set negative cache (cache miss marker)
    async fn set_negative(&self, key: &str) -> CacheResult<()>;

    /// Check if value is negative cache
    fn is_negative_cache(value: &str) -> bool {
        value == CACHE_MISS_SENTINEL
    }

    /// Batch delete using SCAN (non-blocking)
    async fn scan_del(&self, pattern: &str) -> CacheResult<usize>;

    /// Pipeline multiple SET operations
    async fn pipeline_set<T: Serialize + Send + Sync>(
        &self,
        items: &[(&str, &T, u64)],
    ) -> CacheResult<()>;

    /// Pipeline multiple DEL operations
    async fn pipeline_del(&self, keys: &[&str]) -> CacheResult<()>;
}

/// Nova cache client implementation
#[derive(Clone)]
pub struct NovaCache {
    redis: SharedRedis,
    metrics: CacheMetrics,
}

impl NovaCache {
    pub fn new(redis: SharedRedis) -> Self {
        Self {
            redis,
            metrics: CacheMetrics::new(),
        }
    }

    pub fn with_metrics(redis: SharedRedis, metrics: CacheMetrics) -> Self {
        Self { redis, metrics }
    }

    /// Add jitter to TTL to prevent thundering herd
    fn add_jitter(ttl_secs: u64) -> u64 {
        let jitter_percent = (rand::random::<u32>() % 10) as f64 / 100.0;
        let jitter = (ttl_secs as f64 * jitter_percent).round() as u64;
        ttl_secs + jitter
    }

    /// Get raw string value (for checking negative cache)
    pub async fn get_raw(&self, key: &str) -> CacheResult<Option<String>> {
        let mut conn = self.redis.lock().await;
        let result: Option<String> = conn.get(key).await.map_err(CacheError::Redis)?;
        Ok(result)
    }
}

#[async_trait::async_trait]
impl CacheOperations for NovaCache {
    async fn get<T: DeserializeOwned + Send>(&self, key: &str) -> CacheResult<Option<T>> {
        let mut conn = self.redis.lock().await;

        match conn.get::<_, Option<String>>(key).await {
            Ok(Some(data)) => {
                // Check for negative cache
                if Self::is_negative_cache(&data) {
                    debug!(key = %key, "Cache negative hit");
                    self.metrics.record_negative_hit(key);
                    return Ok(None);
                }

                match serde_json::from_str::<T>(&data) {
                    Ok(value) => {
                        debug!(key = %key, "Cache hit");
                        self.metrics.record_hit(key);
                        Ok(Some(value))
                    }
                    Err(e) => {
                        warn!(key = %key, error = %e, "Cache deserialization failed");
                        self.metrics.record_error(key, "deserialize");
                        // Delete corrupted cache entry
                        let _ = conn.del::<_, ()>(key).await;
                        Ok(None)
                    }
                }
            }
            Ok(None) => {
                debug!(key = %key, "Cache miss");
                self.metrics.record_miss(key);
                Ok(None)
            }
            Err(e) => {
                warn!(key = %key, error = %e, "Redis get error");
                self.metrics.record_error(key, "redis");
                Err(CacheError::Redis(e))
            }
        }
    }

    async fn set<T: Serialize + Send + Sync>(
        &self,
        key: &str,
        value: &T,
        ttl_secs: u64,
    ) -> CacheResult<()> {
        let data = serde_json::to_string(value).map_err(CacheError::Serialization)?;
        let ttl_with_jitter = Self::add_jitter(ttl_secs);

        let mut conn = self.redis.lock().await;
        conn.set_ex::<_, _, ()>(key, data, ttl_with_jitter)
            .await
            .map_err(CacheError::Redis)?;

        debug!(key = %key, ttl = ttl_with_jitter, "Cache set");
        self.metrics.record_write(key);
        Ok(())
    }

    async fn del(&self, key: &str) -> CacheResult<()> {
        let mut conn = self.redis.lock().await;
        conn.del::<_, ()>(key).await.map_err(CacheError::Redis)?;

        debug!(key = %key, "Cache delete");
        self.metrics.record_invalidation(key);
        Ok(())
    }

    async fn exists(&self, key: &str) -> CacheResult<bool> {
        let mut conn = self.redis.lock().await;
        let exists: bool = conn.exists(key).await.map_err(CacheError::Redis)?;
        Ok(exists)
    }

    async fn set_negative(&self, key: &str) -> CacheResult<()> {
        let mut conn = self.redis.lock().await;
        conn.set_ex::<_, _, ()>(key, CACHE_MISS_SENTINEL, ttl::NEGATIVE)
            .await
            .map_err(CacheError::Redis)?;

        debug!(key = %key, "Cache set negative");
        self.metrics.record_negative_write(key);
        Ok(())
    }

    async fn scan_del(&self, pattern: &str) -> CacheResult<usize> {
        let mut conn = self.redis.lock().await;
        let mut cursor: u64 = 0;
        let mut total_deleted = 0;

        loop {
            // Use SCAN instead of KEYS to avoid blocking
            let (next_cursor, keys): (u64, Vec<String>) = redis::cmd("SCAN")
                .arg(cursor)
                .arg("MATCH")
                .arg(pattern)
                .arg("COUNT")
                .arg(100)
                .query_async(&mut *conn)
                .await
                .map_err(CacheError::Redis)?;

            if !keys.is_empty() {
                // Use pipeline for batch delete
                let mut pipe = Pipeline::new();
                for key in &keys {
                    pipe.del(key);
                }
                pipe.query_async::<_, ()>(&mut *conn)
                    .await
                    .map_err(CacheError::Redis)?;

                total_deleted += keys.len();
            }

            cursor = next_cursor;
            if cursor == 0 {
                break;
            }
        }

        debug!(pattern = %pattern, deleted = total_deleted, "Cache scan delete");
        Ok(total_deleted)
    }

    async fn pipeline_set<T: Serialize + Send + Sync>(
        &self,
        items: &[(&str, &T, u64)],
    ) -> CacheResult<()> {
        if items.is_empty() {
            return Ok(());
        }

        let mut conn = self.redis.lock().await;
        let mut pipe = Pipeline::new();

        for (key, value, ttl) in items {
            let data = serde_json::to_string(value).map_err(CacheError::Serialization)?;
            let ttl_with_jitter = Self::add_jitter(*ttl);
            pipe.set_ex(*key, data, ttl_with_jitter);
        }

        pipe.query_async::<_, ()>(&mut *conn)
            .await
            .map_err(CacheError::Redis)?;

        debug!(count = items.len(), "Cache pipeline set");
        Ok(())
    }

    async fn pipeline_del(&self, keys: &[&str]) -> CacheResult<()> {
        if keys.is_empty() {
            return Ok(());
        }

        let mut conn = self.redis.lock().await;
        let mut pipe = Pipeline::new();

        for key in keys {
            pipe.del(*key);
        }

        pipe.query_async::<_, ()>(&mut *conn)
            .await
            .map_err(CacheError::Redis)?;

        debug!(count = keys.len(), "Cache pipeline delete");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_negative_cache() {
        assert!(NovaCache::is_negative_cache(CACHE_MISS_SENTINEL));
        assert!(!NovaCache::is_negative_cache("some_value"));
    }

    #[test]
    fn test_add_jitter() {
        let ttl = 300u64;
        let with_jitter = NovaCache::add_jitter(ttl);
        // Jitter should be 0-10% of TTL
        assert!(with_jitter >= ttl);
        assert!(with_jitter <= ttl + (ttl / 10));
    }
}
