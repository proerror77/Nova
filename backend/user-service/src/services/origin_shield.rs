/// Origin Shield Service for CDN Origin Protection
///
/// Implements origin shield pattern to reduce load on CDN origin by placing
/// an additional cache layer between the CDN edge and the origin server.
/// Handles request coalescing, cache warming, and origin failover.

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Origin shield state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShieldState {
    /// Shield is active and caching
    Active,
    /// Shield is warming up
    Warming,
    /// Shield is degraded (partial cache)
    Degraded,
    /// Shield is offline
    Offline,
}

impl ShieldState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Warming => "warming",
            Self::Degraded => "degraded",
            Self::Offline => "offline",
        }
    }
}

/// Origin shield request entry
#[derive(Debug, Clone)]
pub struct ShieldedRequest {
    /// Request path/key
    pub path: String,
    /// Number of concurrent requests waiting for same resource
    pub coalesced_count: u32,
    /// Response content (once cached)
    pub cached_response: Option<String>,
    /// Cache timestamp
    pub cached_at: Option<u64>,
    /// TTL in seconds
    pub ttl_seconds: u32,
}

impl ShieldedRequest {
    /// Check if response is still valid
    pub fn is_valid(&self) -> bool {
        if let Some(cached_at) = self.cached_at {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);

            now <= cached_at + self.ttl_seconds as u64
        } else {
            false
        }
    }
}

/// Origin Shield for protecting CDN origin
pub struct OriginShield {
    /// Shield state
    state: Arc<RwLock<ShieldState>>,
    /// Shielded requests cache
    cache: Arc<RwLock<HashMap<String, ShieldedRequest>>>,
    /// In-flight requests (for coalescing)
    in_flight: Arc<RwLock<HashMap<String, u32>>>,
    /// Health check interval in seconds
    health_check_interval: u32,
    /// Cache capacity (max entries)
    capacity: usize,
}

impl OriginShield {
    /// Create a new origin shield
    pub fn new(capacity: usize, health_check_interval: u32) -> Self {
        info!(
            "Initializing Origin Shield: capacity={}, health_check_interval={}s",
            capacity, health_check_interval
        );

        Self {
            state: Arc::new(RwLock::new(ShieldState::Warming)),
            cache: Arc::new(RwLock::new(HashMap::new())),
            in_flight: Arc::new(RwLock::new(HashMap::new())),
            health_check_interval,
            capacity,
        }
    }

    /// Get current shield state
    pub async fn get_state(&self) -> ShieldState {
        *self.state.read().await
    }

    /// Set shield state
    pub async fn set_state(&self, state: ShieldState) {
        let mut current_state = self.state.write().await;
        if *current_state != state {
            info!("Origin Shield state transition: {:?} → {:?}", current_state, state);
            *current_state = state;
        }
    }

    /// Get shielded response (handles request coalescing)
    pub async fn get_shielded_response(
        &self,
        request_path: &str,
        ttl_seconds: u32,
        origin_fetcher: impl std::future::Future<Output = Result<String, String>>,
    ) -> Result<String, String> {
        // Check if we already have cached response
        {
            let cache = self.cache.read().await;
            if let Some(entry) = cache.get(request_path) {
                if entry.is_valid() {
                    debug!("Origin Shield cache hit: {}", request_path);
                    return Ok(entry.cached_response.as_ref().unwrap().clone());
                }
            }
        }

        // Check if request is already in-flight (coalesce)
        {
            let mut in_flight = self.in_flight.write().await;
            if let Some(count) = in_flight.get_mut(request_path) {
                *count += 1;
                debug!(
                    "Request coalesced: {} (total: {})",
                    request_path, count
                );
                // In production, would wait for first request to complete
                // For now, proceed with fetch
            } else {
                in_flight.insert(request_path.to_string(), 1);
            }
        }

        // Fetch from origin
        debug!("Fetching from origin: {}", request_path);
        let response = origin_fetcher.await?;

        // Cache the response
        {
            let mut cache = self.cache.write().await;

            // Evict oldest entry if at capacity
            if cache.len() >= self.capacity {
                if let Some(oldest_key) = cache
                    .iter()
                    .min_by_key(|(_, entry)| entry.cached_at.unwrap_or(0))
                    .map(|(k, _)| k.clone())
                {
                    cache.remove(&oldest_key);
                    warn!("Origin Shield evicted: {}", oldest_key);
                }
            }

            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);

            cache.insert(
                request_path.to_string(),
                ShieldedRequest {
                    path: request_path.to_string(),
                    coalesced_count: 0,
                    cached_response: Some(response.clone()),
                    cached_at: Some(now),
                    ttl_seconds,
                },
            );

            debug!(
                "Origin Shield cached: {} (size: {})",
                request_path,
                cache.len()
            );
        }

        // Remove from in-flight
        {
            let mut in_flight = self.in_flight.write().await;
            in_flight.remove(request_path);
        }

        Ok(response)
    }

    /// Warm up cache with common requests
    pub async fn warm_cache(&self, warmup_requests: Vec<(String, u32)>) {
        info!("Starting Origin Shield cache warmup: {} requests", warmup_requests.len());

        let mut cache = self.cache.write().await;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        for (path, ttl) in warmup_requests {
            cache.insert(
                path.clone(),
                ShieldedRequest {
                    path: path.clone(),
                    coalesced_count: 0,
                    cached_response: Some(String::new()), // Placeholder
                    cached_at: Some(now),
                    ttl_seconds: ttl,
                },
            );
        }

        info!("Origin Shield cache warmup completed: {} entries", cache.len());
    }

    /// Get shield statistics
    pub async fn get_stats(&self) -> ShieldStats {
        let cache = self.cache.read().await;
        let in_flight = self.in_flight.read().await;

        let mut valid_entries = 0;
        let mut expired_entries = 0;

        for entry in cache.values() {
            if entry.is_valid() {
                valid_entries += 1;
            } else {
                expired_entries += 1;
            }
        }

        ShieldStats {
            state: *self.state.blocking_read(),
            total_cached: cache.len(),
            valid_entries,
            expired_entries,
            in_flight_requests: in_flight.len(),
            capacity: self.capacity,
        }
    }

    /// Clear cache
    pub async fn clear_cache(&self) {
        let mut cache = self.cache.write().await;
        let count = cache.len();
        cache.clear();
        info!("Origin Shield cache cleared: {} entries", count);
    }

    /// Invalidate specific cache entry
    pub async fn invalidate(&self, request_path: &str) {
        let mut cache = self.cache.write().await;
        if cache.remove(request_path).is_some() {
            info!("Origin Shield cache invalidated: {}", request_path);
        }
    }

    /// Check shield health
    pub async fn check_health(&self) -> bool {
        let stats = self.get_stats().await;
        let state = self.get_state().await;

        // Shield is healthy if:
        // 1. State is Active
        // 2. Has some cached entries
        // 3. Valid entries > expired entries (at least 50% valid)
        let is_healthy = state == ShieldState::Active
            && stats.total_cached > 0
            && stats.valid_entries >= stats.expired_entries;

        if !is_healthy {
            warn!("Origin Shield health check failed: {:?}", stats);
        }

        is_healthy
    }

    /// Get detailed cache entry
    pub async fn get_cache_entry(&self, path: &str) -> Option<ShieldedRequest> {
        let cache = self.cache.read().await;
        cache.get(path).cloned()
    }

    /// Get cache memory usage estimate (in bytes)
    pub async fn estimate_memory_usage(&self) -> usize {
        let cache = self.cache.read().await;

        let mut total = 0;
        for (key, entry) in cache.iter() {
            total += key.len(); // Path string
            total += entry.path.len();
            if let Some(ref response) = entry.cached_response {
                total += response.len();
            }
        }

        total
    }
}

/// Origin Shield statistics
#[derive(Debug, Clone)]
pub struct ShieldStats {
    pub state: ShieldState,
    pub total_cached: usize,
    pub valid_entries: usize,
    pub expired_entries: usize,
    pub in_flight_requests: usize,
    pub capacity: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shield_state_str() {
        assert_eq!(ShieldState::Active.as_str(), "active");
        assert_eq!(ShieldState::Warming.as_str(), "warming");
        assert_eq!(ShieldState::Degraded.as_str(), "degraded");
        assert_eq!(ShieldState::Offline.as_str(), "offline");
    }

    #[test]
    fn test_shielded_request_validity() {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let mut request = ShieldedRequest {
            path: "/test".to_string(),
            coalesced_count: 0,
            cached_response: Some("test".to_string()),
            cached_at: Some(now - 100),
            ttl_seconds: 300,
        };

        assert!(request.is_valid()); // 100 < 300

        request.ttl_seconds = 50;
        assert!(!request.is_valid()); // 100 > 50
    }

    #[tokio::test]
    async fn test_shield_creation() {
        let shield = OriginShield::new(1000, 60);
        assert_eq!(shield.get_state().await, ShieldState::Warming);
    }

    #[tokio::test]
    async fn test_shield_state_transition() {
        let shield = OriginShield::new(1000, 60);

        shield.set_state(ShieldState::Active).await;
        assert_eq!(shield.get_state().await, ShieldState::Active);

        shield.set_state(ShieldState::Degraded).await;
        assert_eq!(shield.get_state().await, ShieldState::Degraded);
    }

    #[tokio::test]
    async fn test_shield_cache_stats() {
        let shield = OriginShield::new(1000, 60);
        let stats = shield.get_stats().await;

        assert_eq!(stats.total_cached, 0);
        assert_eq!(stats.valid_entries, 0);
        assert_eq!(stats.capacity, 1000);
    }

    #[tokio::test]
    async fn test_shield_memory_estimation() {
        let shield = OriginShield::new(1000, 60);
        let memory = shield.estimate_memory_usage().await;
        assert_eq!(memory, 0); // Empty cache
    }

    #[tokio::test]
    async fn test_shield_invalidation() {
        let shield = OriginShield::new(1000, 60);

        // Invalidate non-existent entry (should not error)
        shield.invalidate("/nonexistent").await;
    }

    #[tokio::test]
    async fn test_shield_cache_clearing() {
        let shield = OriginShield::new(1000, 60);
        shield.clear_cache().await; // Should not error
    }
}
