/// Cache performance metrics (Redis + in-memory caches)
use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec_with_registry, register_gauge_vec_with_registry,
    register_histogram_vec_with_registry, CounterVec, GaugeVec, HistogramVec,
};

use super::REGISTRY;

lazy_static! {
    // ======================
    // Counters - 缓存命中和失效
    // ======================

    /// Total cache hits (labels: cache_type, key_pattern)
    /// cache_type: feed, user_profile, post_metrics, etc.
    /// key_pattern: feed:{user_id}, user:{user_id}, etc.
    pub static ref CACHE_HITS: CounterVec = register_counter_vec_with_registry!(
        "cache_hits_total",
        "Total number of cache hits",
        &["cache_type", "key_pattern"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Total cache misses (labels: cache_type, key_pattern)
    pub static ref CACHE_MISSES: CounterVec = register_counter_vec_with_registry!(
        "cache_misses_total",
        "Total number of cache misses",
        &["cache_type", "key_pattern"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Total cache invalidations (labels: cache_type, reason)
    /// reason: ttl_expired, manual_invalidate, evicted
    pub static ref CACHE_INVALIDATIONS: CounterVec = register_counter_vec_with_registry!(
        "cache_invalidations_total",
        "Total number of cache invalidations",
        &["cache_type", "reason"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Total cache write operations (labels: cache_type, operation)
    /// operation: set, update, delete
    pub static ref CACHE_WRITES: CounterVec = register_counter_vec_with_registry!(
        "cache_writes_total",
        "Total number of cache write operations",
        &["cache_type", "operation"],
        REGISTRY
    )
    .expect("Failed to register metric");

    // ======================
    // Histograms - 缓存操作延迟
    // ======================

    /// Cache operation duration (labels: cache_type, operation)
    /// operation: get, set, delete, invalidate
    pub static ref CACHE_OPERATION_DURATION_MS: HistogramVec = register_histogram_vec_with_registry!(
        "cache_operation_duration_ms",
        "Time spent on cache operations (ms)",
        &["cache_type", "operation"],
        vec![1.0, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Cache entry size distribution (bytes)
    pub static ref CACHE_ENTRY_SIZE_BYTES: HistogramVec = register_histogram_vec_with_registry!(
        "cache_entry_size_bytes",
        "Size distribution of cached entries (bytes)",
        &["cache_type"],
        vec![100.0, 500.0, 1000.0, 5000.0, 10000.0, 50000.0, 100000.0],
        REGISTRY
    )
    .expect("Failed to register metric");

    // ======================
    // Gauges - 缓存实时状态
    // ======================

    /// Current cache hit rate percentage (labels: cache_type)
    /// Calculated as: hits / (hits + misses) * 100
    pub static ref CACHE_HIT_RATE_PERCENT: GaugeVec = register_gauge_vec_with_registry!(
        "cache_hit_rate_percent",
        "Current cache hit rate as a percentage (0-100)",
        &["cache_type"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Estimated cache memory usage (labels: cache_type)
    pub static ref CACHE_MEMORY_BYTES: GaugeVec = register_gauge_vec_with_registry!(
        "cache_memory_bytes",
        "Estimated memory usage of cache entries (bytes)",
        &["cache_type"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Number of entries in cache (labels: cache_type)
    pub static ref CACHE_ENTRY_COUNT: GaugeVec = register_gauge_vec_with_registry!(
        "cache_entry_count",
        "Number of entries currently in cache",
        &["cache_type"],
        REGISTRY
    )
    .expect("Failed to register metric");
}

/// Helper functions for recording cache metrics
pub mod helpers {
    use super::*;
    use std::time::Instant;

    /// Record a cache hit
    pub fn record_cache_hit(cache_type: &str, key_pattern: &str, duration_ms: u64) {
        CACHE_HITS
            .with_label_values(&[cache_type, key_pattern])
            .inc();
        CACHE_OPERATION_DURATION_MS
            .with_label_values(&[cache_type, "get"])
            .observe(duration_ms as f64);
    }

    /// Record a cache miss
    pub fn record_cache_miss(cache_type: &str, key_pattern: &str, duration_ms: u64) {
        CACHE_MISSES
            .with_label_values(&[cache_type, key_pattern])
            .inc();
        CACHE_OPERATION_DURATION_MS
            .with_label_values(&[cache_type, "get"])
            .observe(duration_ms as f64);
    }

    /// Record a cache set operation
    pub fn record_cache_set(cache_type: &str, duration_ms: u64, entry_size_bytes: usize) {
        CACHE_WRITES.with_label_values(&[cache_type, "set"]).inc();
        CACHE_OPERATION_DURATION_MS
            .with_label_values(&[cache_type, "set"])
            .observe(duration_ms as f64);
        CACHE_ENTRY_SIZE_BYTES
            .with_label_values(&[cache_type])
            .observe(entry_size_bytes as f64);
    }

    /// Record a cache invalidation
    pub fn record_cache_invalidation(cache_type: &str, reason: &str) {
        CACHE_INVALIDATIONS
            .with_label_values(&[cache_type, reason])
            .inc();
    }

    /// Update cache hit rate (calculated from hits and misses)
    pub fn update_cache_hit_rate(cache_type: &str, hit_rate_percent: f64) {
        CACHE_HIT_RATE_PERCENT
            .with_label_values(&[cache_type])
            .set(hit_rate_percent);
    }

    /// Update cache memory usage estimate
    pub fn update_cache_memory(cache_type: &str, memory_bytes: usize) {
        CACHE_MEMORY_BYTES
            .with_label_values(&[cache_type])
            .set(memory_bytes as f64);
    }

    /// Update cache entry count
    pub fn update_cache_entry_count(cache_type: &str, count: usize) {
        CACHE_ENTRY_COUNT
            .with_label_values(&[cache_type])
            .set(count as f64);
    }

    /// Timer guard for automatic cache operation duration tracking
    pub struct CacheTimer {
        start: Instant,
        cache_type: String,
        operation: String,
    }

    impl CacheTimer {
        pub fn new(cache_type: &str, operation: &str) -> Self {
            Self {
                start: Instant::now(),
                cache_type: cache_type.to_string(),
                operation: operation.to_string(),
            }
        }
    }

    impl Drop for CacheTimer {
        fn drop(&mut self) {
            let duration_ms = self.start.elapsed().as_millis() as u64;
            CACHE_OPERATION_DURATION_MS
                .with_label_values(&[&self.cache_type, &self.operation])
                .observe(duration_ms as f64);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_record_cache_hit() {
        helpers::record_cache_hit("feed", "feed:{user_id}", 15);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("cache_hits_total"));
        assert!(metrics.contains("cache_operation_duration_ms"));
    }

    #[test]
    fn test_record_cache_miss() {
        helpers::record_cache_miss("user_profile", "user:{user_id}", 25);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("cache_misses_total"));
    }

    #[test]
    fn test_record_cache_set() {
        helpers::record_cache_set("feed", 35, 2048);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("cache_writes_total"));
        assert!(metrics.contains("cache_entry_size_bytes"));
    }

    #[test]
    fn test_update_cache_hit_rate() {
        helpers::update_cache_hit_rate("feed", 92.5);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("cache_hit_rate_percent"));
    }

    #[test]
    fn test_cache_timer() {
        {
            let _timer = helpers::CacheTimer::new("redis", "get");
            std::thread::sleep(std::time::Duration::from_millis(20));
        }

        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("cache_operation_duration_ms"));
    }
}
