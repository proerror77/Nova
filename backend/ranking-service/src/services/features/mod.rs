// ============================================
// Feature Client Module
// ============================================
// Provides real-time feature retrieval for ranking
// from Redis cache, feature-store gRPC, or PostgreSQL fallback

pub mod grpc_client;

pub use grpc_client::{FeatureSource, GrpcFeatureClient, PostFeatureSet, UserFeatureSet};

use anyhow::Result;
use redis::AsyncCommands;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, warn};
use uuid::Uuid;

/// Feature client for retrieving quality scores and other ranking features
pub struct FeatureClient {
    redis: redis::Client,
    /// Local cache for frequently accessed features (LRU-like)
    local_cache: Arc<RwLock<HashMap<String, CachedFeature>>>,
    /// TTL for local cache entries in seconds
    local_cache_ttl: u64,
}

#[derive(Clone)]
struct CachedFeature {
    value: f32,
    cached_at: std::time::Instant,
}

impl FeatureClient {
    pub fn new(redis: redis::Client) -> Self {
        Self {
            redis,
            local_cache: Arc::new(RwLock::new(HashMap::new())),
            local_cache_ttl: 60, // 1 minute local cache
        }
    }

    /// Get author quality score
    /// Key format: author_quality:{author_id}
    pub async fn get_author_quality(&self, author_id: &str) -> f32 {
        self.get_feature(&format!("author_quality:{}", author_id), 0.5)
            .await
    }

    /// Get content quality score
    /// Key format: content_quality:{content_id}
    pub async fn get_content_quality(&self, content_id: &str) -> f32 {
        self.get_feature(&format!("content_quality:{}", content_id), 0.5)
            .await
    }

    /// Get author ID for a post
    /// Key format: content_author:{content_id}
    pub async fn get_content_author(&self, content_id: &str) -> Option<Uuid> {
        let key = format!("content_author:{}", content_id);
        match self.get_string_feature(&key).await {
            Some(author_str) => Uuid::parse_str(&author_str).ok(),
            None => None,
        }
    }

    /// Get average completion rate for content
    /// Key format: content_completion:{content_id}
    pub async fn get_content_completion_rate(&self, content_id: &str) -> f32 {
        self.get_feature(&format!("content_completion:{}", content_id), 0.5)
            .await
    }

    /// Batch get features for multiple content IDs
    /// Returns map of content_id -> ContentFeatures
    pub async fn batch_get_content_features(
        &self,
        content_ids: &[String],
    ) -> HashMap<String, ContentFeatures> {
        if content_ids.is_empty() {
            return HashMap::new();
        }

        let mut result = HashMap::new();

        // Build Redis keys
        let quality_keys: Vec<String> = content_ids
            .iter()
            .map(|id| format!("content_quality:{}", id))
            .collect();

        let author_keys: Vec<String> = content_ids
            .iter()
            .map(|id| format!("content_author:{}", id))
            .collect();

        let completion_keys: Vec<String> = content_ids
            .iter()
            .map(|id| format!("content_completion:{}", id))
            .collect();

        // Batch fetch from Redis
        let quality_scores = self.batch_get_features(&quality_keys, 0.5).await;
        let author_ids = self.batch_get_string_features(&author_keys).await;
        let completion_rates = self.batch_get_features(&completion_keys, 0.5).await;

        // Combine results
        for (i, content_id) in content_ids.iter().enumerate() {
            let quality_key = &quality_keys[i];
            let author_key = &author_keys[i];
            let completion_key = &completion_keys[i];

            let author_id = author_ids
                .get(author_key)
                .and_then(|s| Uuid::parse_str(s).ok());

            let author_quality = if let Some(aid) = &author_id {
                self.get_author_quality(&aid.to_string()).await
            } else {
                0.5
            };

            result.insert(
                content_id.clone(),
                ContentFeatures {
                    content_quality: *quality_scores.get(quality_key).unwrap_or(&0.5),
                    author_quality,
                    author_id,
                    completion_rate: *completion_rates.get(completion_key).unwrap_or(&0.5),
                },
            );
        }

        result
    }

    /// Get a single numeric feature from Redis
    async fn get_feature(&self, key: &str, default: f32) -> f32 {
        // Check local cache first
        {
            let cache = self.local_cache.read().await;
            if let Some(cached) = cache.get(key) {
                if cached.cached_at.elapsed().as_secs() < self.local_cache_ttl {
                    return cached.value;
                }
            }
        }

        // Fetch from Redis
        match self.redis.get_multiplexed_async_connection().await {
            Ok(mut conn) => {
                let result: Result<Option<f32>, _> = conn.get(key).await;
                match result {
                    Ok(Some(value)) => {
                        // Update local cache
                        let mut cache = self.local_cache.write().await;
                        cache.insert(
                            key.to_string(),
                            CachedFeature {
                                value,
                                cached_at: std::time::Instant::now(),
                            },
                        );
                        value
                    }
                    Ok(None) => {
                        debug!("Feature not found in Redis: {}", key);
                        default
                    }
                    Err(e) => {
                        warn!("Redis error fetching {}: {}", key, e);
                        default
                    }
                }
            }
            Err(e) => {
                warn!("Failed to get Redis connection: {}", e);
                default
            }
        }
    }

    /// Get a single string feature from Redis
    async fn get_string_feature(&self, key: &str) -> Option<String> {
        match self.redis.get_multiplexed_async_connection().await {
            Ok(mut conn) => {
                let result: Result<Option<String>, _> = conn.get(key).await;
                match result {
                    Ok(value) => value,
                    Err(e) => {
                        warn!("Redis error fetching {}: {}", key, e);
                        None
                    }
                }
            }
            Err(e) => {
                warn!("Failed to get Redis connection: {}", e);
                None
            }
        }
    }

    /// Batch get numeric features from Redis using MGET
    async fn batch_get_features(&self, keys: &[String], default: f32) -> HashMap<String, f32> {
        if keys.is_empty() {
            return HashMap::new();
        }

        let mut result: HashMap<String, f32> = keys.iter().map(|k| (k.clone(), default)).collect();

        match self.redis.get_multiplexed_async_connection().await {
            Ok(mut conn) => {
                let values: Result<Vec<Option<String>>, _> =
                    redis::cmd("MGET").arg(keys).query_async(&mut conn).await;

                match values {
                    Ok(vals) => {
                        for (i, val) in vals.into_iter().enumerate() {
                            if let Some(v) = val {
                                if let Ok(parsed) = v.parse::<f32>() {
                                    result.insert(keys[i].clone(), parsed);
                                }
                            }
                        }
                    }
                    Err(e) => {
                        warn!("Redis MGET error: {}", e);
                    }
                }
            }
            Err(e) => {
                warn!("Failed to get Redis connection for batch: {}", e);
            }
        }

        result
    }

    /// Batch get string features from Redis using MGET
    async fn batch_get_string_features(&self, keys: &[String]) -> HashMap<String, String> {
        if keys.is_empty() {
            return HashMap::new();
        }

        let mut result = HashMap::new();

        match self.redis.get_multiplexed_async_connection().await {
            Ok(mut conn) => {
                let values: Result<Vec<Option<String>>, _> =
                    redis::cmd("MGET").arg(keys).query_async(&mut conn).await;

                match values {
                    Ok(vals) => {
                        for (i, val) in vals.into_iter().enumerate() {
                            if let Some(v) = val {
                                result.insert(keys[i].clone(), v);
                            }
                        }
                    }
                    Err(e) => {
                        warn!("Redis MGET error for strings: {}", e);
                    }
                }
            }
            Err(e) => {
                warn!("Failed to get Redis connection for batch strings: {}", e);
            }
        }

        result
    }

    /// Set a feature in Redis (for testing or cache warming)
    pub async fn set_feature(&self, key: &str, value: f32, ttl_seconds: u64) -> Result<()> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let _: () = conn.set_ex(key, value, ttl_seconds).await?;
        Ok(())
    }

    /// Clear local cache (for testing)
    pub async fn clear_local_cache(&self) {
        let mut cache = self.local_cache.write().await;
        cache.clear();
    }
}

/// Content features structure
#[derive(Debug, Clone, Default)]
pub struct ContentFeatures {
    pub content_quality: f32,
    pub author_quality: f32,
    pub author_id: Option<Uuid>,
    pub completion_rate: f32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_feature_client_defaults() {
        // This test would need a mock Redis connection
        // For now, just test the structure compiles
        let _features = ContentFeatures::default();
        assert_eq!(_features.content_quality, 0.0);
    }
}
