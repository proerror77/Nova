use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use std::collections::HashMap;
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;

pub use crate::services::neo4j_client::{UserId, UserNode, RecommendationResult};

/// Cache entry with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheEntry<T> {
    pub key: String,
    pub value: T,
    pub created_at: u64,
    pub last_accessed: u64,
    pub ttl_seconds: u64,
}

impl<T> CacheEntry<T> {
    /// Check if cache entry has expired
    pub fn is_expired(&self) -> bool {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        (now - self.created_at) > self.ttl_seconds
    }

    /// Update last accessed time
    pub fn touch(&mut self) {
        self.last_accessed = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
    }
}

/// Cache invalidation strategy
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CacheInvalidation {
    TTL,
    EventBased,
    OnWrite,
}

/// Cache hit/miss statistics
#[derive(Debug, Clone, Default)]
pub struct CacheStats {
    pub hits: u64,
    pub misses: u64,
    pub evictions: u64,
}

impl CacheStats {
    pub fn hit_rate(&self) -> f32 {
        if self.hits + self.misses == 0 {
            0.0
        } else {
            self.hits as f32 / (self.hits + self.misses) as f32
        }
    }
}

/// Redis cache manager for social graph queries
pub struct CacheManager {
    // In-memory store for demo/testing
    cache: Arc<RwLock<HashMap<String, (Vec<u8>, u64)>>>,
    max_size: usize,
    default_ttl: Duration,
    stats: Arc<RwLock<CacheStats>>,
}

impl CacheManager {
    /// Create a new cache manager
    pub fn new(max_size: usize, default_ttl: Duration) -> Self {
        Self {
            cache: Arc::new(RwLock::new(HashMap::new())),
            max_size,
            default_ttl,
            stats: Arc::new(RwLock::new(CacheStats::default())),
        }
    }

    /// Get cached value by key
    pub async fn get<T: for<'de> Deserialize<'de>>(&self, key: &str) -> Option<T> {
        let mut cache = self.cache.write().await;

        if let Some((data, _)) = cache.get(key) {
            // Deserialize and check if expired
            if let Ok(value) = bincode::deserialize::<CacheEntry<T>>(data) {
                if !value.is_expired() {
                    // Update stats
                    let mut stats = futures::executor::block_on(self.stats.write());
                    stats.hits += 1;
                    drop(stats);

                    return Some(value.value);
                } else {
                    // Remove expired entry
                    cache.remove(key);
                }
            }
        }

        // Update stats
        let mut stats = self.stats.write().await;
        stats.misses += 1;

        None
    }

    /// Set cached value with optional TTL
    pub async fn set<T: Serialize>(&self, key: String, value: T, ttl: Option<Duration>) -> Result<(), String> {
        let ttl_secs = ttl.unwrap_or(self.default_ttl).as_secs();

        let entry = CacheEntry {
            key: key.clone(),
            value,
            created_at: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
            last_accessed: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
            ttl_seconds: ttl_secs,
        };

        let data = bincode::serialize(&entry).map_err(|e| e.to_string())?;

        let mut cache = self.cache.write().await;

        // Check if we need to evict entries
        if cache.len() >= self.max_size {
            self.evict_lru(&mut cache).await;
        }

        cache.insert(key, (data, SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs()));

        Ok(())
    }

    /// Invalidate cache entry
    pub async fn invalidate(&self, key: &str) -> bool {
        let mut cache = self.cache.write().await;
        cache.remove(key).is_some()
    }

    /// Invalidate multiple cache entries by pattern
    pub async fn invalidate_pattern(&self, pattern: &str) -> usize {
        let mut cache = self.cache.write().await;
        let keys_to_remove: Vec<_> = cache
            .keys()
            .filter(|k| k.contains(pattern))
            .cloned()
            .collect();

        let count = keys_to_remove.len();
        for key in keys_to_remove {
            cache.remove(&key);
        }

        count
    }

    /// Get cache statistics
    pub async fn get_stats(&self) -> CacheStats {
        self.stats.read().await.clone()
    }

    /// Clear all cache
    pub async fn clear(&self) {
        let mut cache = self.cache.write().await;
        cache.clear();

        let mut stats = self.stats.write().await;
        *stats = CacheStats::default();
    }

    /// Warm up cache with hot data
    pub async fn warm_up<T: Serialize>(&self, entries: Vec<(String, T, Option<Duration>)>) -> Result<usize, String> {
        let mut count = 0;

        for (key, value, ttl) in entries {
            self.set(key, value, ttl).await?;
            count += 1;
        }

        Ok(count)
    }

    /// Get cache size
    pub async fn size(&self) -> usize {
        let cache = self.cache.read().await;
        cache.len()
    }

    /// Evict least recently used entry
    async fn evict_lru(&self, cache: &mut HashMap<String, (Vec<u8>, u64)>) {
        let mut stats = self.stats.write().await;
        stats.evictions += 1;

        if let Some((key, _)) = cache
            .iter()
            .min_by_key(|(_, (_, accessed))| *accessed)
            .map(|(k, v)| (k.clone(), v.clone()))
        {
            cache.remove(&key);
        }
    }

    /// Cache wrapper for user relationships
    pub async fn cache_user_relationships(
        &self,
        user_id: &UserId,
        relationships: Vec<UserNode>,
        ttl: Option<Duration>,
    ) -> Result<(), String> {
        let key = format!("social:user:{}:relationships", user_id);
        self.set(key, relationships, ttl).await
    }

    /// Get cached user relationships
    pub async fn get_user_relationships(&self, user_id: &UserId) -> Option<Vec<UserNode>> {
        let key = format!("social:user:{}:relationships", user_id);
        self.get(&key).await
    }

    /// Cache wrapper for recommendations
    pub async fn cache_recommendations(
        &self,
        user_id: &UserId,
        recommendations: Vec<RecommendationResult>,
        ttl: Option<Duration>,
    ) -> Result<(), String> {
        let key = format!("social:user:{}:recommendations", user_id);
        self.set(key, recommendations, ttl).await
    }

    /// Get cached recommendations
    pub async fn get_recommendations(&self, user_id: &UserId) -> Option<Vec<RecommendationResult>> {
        let key = format!("social:user:{}:recommendations", user_id);
        self.get(&key).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_cache_manager_creation() {
        let manager = CacheManager::new(100, Duration::from_secs(300));
        assert_eq!(manager.max_size, 100);
    }

    #[tokio::test]
    async fn test_cache_set_get() {
        let manager = CacheManager::new(100, Duration::from_secs(300));

        let value = vec!["alice".to_string(), "bob".to_string(), "charlie".to_string()];
        manager.set("users".to_string(), value.clone(), None).await.unwrap();

        let retrieved: Option<Vec<String>> = manager.get("users").await;
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap(), value);
    }

    #[tokio::test]
    async fn test_cache_miss() {
        let manager = CacheManager::new(100, Duration::from_secs(300));

        let result: Option<String> = manager.get("nonexistent").await;
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_cache_invalidate() {
        let manager = CacheManager::new(100, Duration::from_secs(300));

        let value = "test_value".to_string();
        manager.set("key1".to_string(), value, None).await.unwrap();

        let retrieved: Option<String> = manager.get("key1").await;
        assert!(retrieved.is_some());

        let invalidated = manager.invalidate("key1").await;
        assert!(invalidated);

        let result: Option<String> = manager.get("key1").await;
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_cache_invalidate_pattern() {
        let manager = CacheManager::new(100, Duration::from_secs(300));

        manager.set("social:user:1:relationships".to_string(), "value1".to_string(), None).await.unwrap();
        manager.set("social:user:2:relationships".to_string(), "value2".to_string(), None).await.unwrap();
        manager.set("other:key".to_string(), "value3".to_string(), None).await.unwrap();

        let invalidated = manager.invalidate_pattern("social:user").await;
        assert_eq!(invalidated, 2);

        let size = manager.size().await;
        assert_eq!(size, 1);
    }

    #[tokio::test]
    async fn test_cache_stats() {
        let manager = CacheManager::new(100, Duration::from_secs(300));

        manager.set("key1".to_string(), "value1".to_string(), None).await.unwrap();

        // Cause some hits and misses
        let _: Option<String> = manager.get("key1").await;
        let _: Option<String> = manager.get("key1").await;
        let _: Option<String> = manager.get("nonexistent").await;

        let stats = manager.get_stats().await;
        assert!(stats.hits >= 2);
        assert_eq!(stats.misses, 1);
    }

    #[tokio::test]
    async fn test_cache_hit_rate() {
        let manager = CacheManager::new(100, Duration::from_secs(300));

        manager.set("key1".to_string(), "value1".to_string(), None).await.unwrap();

        for _ in 0..8 {
            let _: Option<String> = manager.get("key1").await;
        }

        for _ in 0..2 {
            let _: Option<String> = manager.get("nonexistent").await;
        }

        let stats = manager.get_stats().await;
        let hit_rate = stats.hit_rate();
        assert!(hit_rate > 0.7 && hit_rate <= 1.0);
    }

    #[tokio::test]
    async fn test_cache_clear() {
        let manager = CacheManager::new(100, Duration::from_secs(300));

        manager.set("key1".to_string(), "value1".to_string(), None).await.unwrap();
        manager.set("key2".to_string(), "value2".to_string(), None).await.unwrap();

        let size_before = manager.size().await;
        assert_eq!(size_before, 2);

        manager.clear().await;

        let size_after = manager.size().await;
        assert_eq!(size_after, 0);
    }

    #[tokio::test]
    async fn test_user_relationships_cache() {
        let manager = CacheManager::new(100, Duration::from_secs(300));

        let mut user1 = UserNode::new("user1".to_string(), "alice".to_string());
        user1.follower_count = 100;

        let relationships = vec![user1];

        manager.cache_user_relationships(&"alice".to_string(), relationships.clone(), None).await.unwrap();

        let cached = manager.get_user_relationships(&"alice".to_string()).await;
        assert!(cached.is_some());
        assert_eq!(cached.unwrap().len(), 1);
    }

    #[tokio::test]
    async fn test_warm_up_cache() {
        let manager = CacheManager::new(100, Duration::from_secs(300));

        let entries = vec![
            ("key1".to_string(), "value1".to_string(), None),
            ("key2".to_string(), "value2".to_string(), None),
            ("key3".to_string(), "value3".to_string(), None),
        ];

        let count = manager.warm_up(entries).await.unwrap();
        assert_eq!(count, 3);

        let size = manager.size().await;
        assert_eq!(size, 3);
    }

    #[tokio::test]
    async fn test_cache_size() {
        let manager = CacheManager::new(100, Duration::from_secs(300));

        assert_eq!(manager.size().await, 0);

        manager.set("key1".to_string(), "value1".to_string(), None).await.unwrap();
        assert_eq!(manager.size().await, 1);

        manager.set("key2".to_string(), "value2".to_string(), None).await.unwrap();
        assert_eq!(manager.size().await, 2);
    }
}
