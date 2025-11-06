use redis::{aio::ConnectionManager, AsyncCommands, RedisError};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CacheError {
    #[error("Redis error: {0}")]
    Redis(#[from] RedisError),
    #[error("serialization error: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("cache miss")]
    CacheMiss,
}

#[derive(Clone)]
pub struct RedisCache {
    conn: ConnectionManager,
    default_ttl: Duration,
}

impl RedisCache {
    pub async fn new(redis_url: &str, default_ttl_secs: u64) -> Result<Self, CacheError> {
        let client = redis::Client::open(redis_url)?;
        let conn = ConnectionManager::new(client).await?;

        Ok(Self {
            conn,
            default_ttl: Duration::from_secs(default_ttl_secs),
        })
    }

    pub async fn get<T>(&self, key: &str) -> Result<T, CacheError>
    where
        T: for<'de> Deserialize<'de>,
    {
        let mut conn = self.conn.clone();
        let value: Option<String> = conn.get(key).await?;

        match value {
            Some(v) => Ok(serde_json::from_str(&v)?),
            None => Err(CacheError::CacheMiss),
        }
    }

    pub async fn set<T>(
        &self,
        key: &str,
        value: &T,
        ttl: Option<Duration>,
    ) -> Result<(), CacheError>
    where
        T: Serialize + ?Sized,
    {
        let mut conn = self.conn.clone();
        let serialized = serde_json::to_string(value)?;
        let ttl_secs = ttl.unwrap_or(self.default_ttl).as_secs();

        conn.set_ex(key, serialized, ttl_secs).await?;
        Ok(())
    }

    pub async fn get_search_suggestions(&self, prefix: &str) -> Result<Vec<String>, CacheError> {
        let key = format!("search:suggestions:{}", prefix.to_lowercase());
        self.get(&key).await
    }

    pub async fn set_search_suggestions(
        &self,
        prefix: &str,
        suggestions: &[String],
    ) -> Result<(), CacheError> {
        let key = format!("search:suggestions:{}", prefix.to_lowercase());
        // Cache suggestions for 24 hours
        self.set(&key, suggestions, Some(Duration::from_secs(86400)))
            .await
    }

    pub async fn get_trending_searches(
        &self,
        time_window: &str,
    ) -> Result<Vec<TrendingSearchCache>, CacheError> {
        let key = format!("search:trending:{}", time_window);
        self.get(&key).await
    }

    pub async fn set_trending_searches(
        &self,
        time_window: &str,
        searches: &[TrendingSearchCache],
    ) -> Result<(), CacheError> {
        let key = format!("search:trending:{}", time_window);
        // Cache trending searches for 5 minutes
        self.set(&key, searches, Some(Duration::from_secs(300)))
            .await
    }

    pub async fn get_search_results_cache(
        &self,
        cache_key: &str,
    ) -> Result<CachedSearchResults, CacheError> {
        let key = format!("search:results:{}", cache_key);
        self.get(&key).await
    }

    pub async fn set_search_results_cache(
        &self,
        cache_key: &str,
        results: &CachedSearchResults,
    ) -> Result<(), CacheError> {
        let key = format!("search:results:{}", cache_key);
        // Cache search results for 5 minutes
        self.set(&key, results, Some(Duration::from_secs(300)))
            .await
    }

    pub async fn invalidate_pattern(&self, pattern: &str) -> Result<(), CacheError> {
        let mut conn = self.conn.clone();
        let keys: Vec<String> = redis::cmd("KEYS")
            .arg(pattern)
            .query_async(&mut conn)
            .await?;

        if !keys.is_empty() {
            conn.del::<_, ()>(keys).await?;
        }

        Ok(())
    }

    pub async fn health_check(&self) -> Result<(), CacheError> {
        let mut conn = self.conn.clone();
        let _: String = redis::cmd("PING").query_async(&mut conn).await?;
        Ok(())
    }

    pub async fn increment_search_count(
        &self,
        query: &str,
        time_window: &str,
    ) -> Result<i64, CacheError> {
        let mut conn = self.conn.clone();
        let key = format!("search:count:{}:{}", time_window, query.to_lowercase());
        let count: i64 = conn.incr(&key, 1).await?;

        // Set expiry based on time window
        let ttl = match time_window {
            "1h" => 3600,
            "24h" => 86400,
            "7d" => 604800,
            _ => 3600,
        };
        conn.expire::<_, ()>(&key, ttl).await?;

        Ok(count)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrendingSearchCache {
    pub query: String,
    pub search_count: u32,
    pub trend_score: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedSearchResults {
    pub post_ids: Vec<String>,
    pub user_ids: Vec<String>,
    pub hashtags: Vec<String>,
    pub total_count: i32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires running Redis instance
    async fn test_redis_connection() {
        let cache = RedisCache::new("redis://localhost:6379", 3600)
            .await
            .expect("Failed to connect to Redis");

        cache.health_check().await.expect("Health check failed");
    }

    #[tokio::test]
    #[ignore]
    async fn test_set_and_get() {
        let cache = RedisCache::new("redis://localhost:6379", 3600)
            .await
            .unwrap();

        let key = "test:key";
        let value = vec!["suggestion1".to_string(), "suggestion2".to_string()];

        cache
            .set(key, &value, None)
            .await
            .expect("Failed to set value");

        let retrieved: Vec<String> = cache.get(key).await.expect("Failed to get value");

        assert_eq!(retrieved, value);
    }
}
