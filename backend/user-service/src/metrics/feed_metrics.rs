/// Feed API and ranking performance metrics
use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec_with_registry, register_gauge_vec_with_registry,
    register_histogram_vec_with_registry, CounterVec, GaugeVec, HistogramVec,
};

use super::REGISTRY;

lazy_static! {
    // ======================
    // Counters - Feed API 请求统计
    // ======================

    /// Total feed API requests (labels: source, status)
    /// source: cache_hit, clickhouse_query, fallback_postgres
    /// status: success, error, timeout
    pub static ref FEED_API_REQUESTS: CounterVec = register_counter_vec_with_registry!(
        "feed_api_requests_total",
        "Total number of feed API requests",
        &["source", "status"],
        REGISTRY
    )
    .unwrap();

    /// Total feed cache operations (labels: operation, result)
    /// operation: get, set, invalidate
    /// result: hit, miss, error
    pub static ref FEED_CACHE_OPERATIONS: CounterVec = register_counter_vec_with_registry!(
        "feed_cache_operations_total",
        "Total feed cache operations",
        &["operation", "result"],
        REGISTRY
    )
    .unwrap();

    /// Total fallback to PostgreSQL (cache + ClickHouse unavailable)
    pub static ref FEED_FALLBACK_POSTGRES: CounterVec = register_counter_vec_with_registry!(
        "feed_fallback_postgres_total",
        "Total feed requests falling back to PostgreSQL",
        &["reason"],
        REGISTRY
    )
    .unwrap();

    // ======================
    // Histograms - Feed API 延迟分布
    // ======================

    /// Feed API end-to-end latency (labels: source)
    /// Includes cache lookup, ClickHouse query, ranking, and serialization
    pub static ref FEED_API_LATENCY_MS: HistogramVec = register_histogram_vec_with_registry!(
        "feed_api_latency_ms",
        "Feed API request latency (ms)",
        &["source"],
        vec![10.0, 50.0, 100.0, 150.0, 250.0, 500.0, 800.0, 1000.0, 2000.0],
        REGISTRY
    )
    .unwrap();

    /// Feed ranking computation duration (labels: strategy)
    /// strategy: freshness_boost, engagement_score, affinity_personalization
    pub static ref FEED_RANKING_DURATION_MS: HistogramVec = register_histogram_vec_with_registry!(
        "feed_ranking_duration_ms",
        "Time spent computing feed ranking scores (ms)",
        &["strategy"],
        vec![5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0],
        REGISTRY
    )
    .unwrap();

    /// ClickHouse query latency breakdown (labels: query_type)
    /// query_type: events_lookup, post_metrics_1h, user_affinity_90d
    pub static ref FEED_CLICKHOUSE_QUERY_MS: HistogramVec = register_histogram_vec_with_registry!(
        "feed_clickhouse_query_ms",
        "ClickHouse query latency for feed data (ms)",
        &["query_type"],
        vec![10.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0],
        REGISTRY
    )
    .unwrap();

    // ======================
    // Gauges - Feed 实时状态
    // ======================

    /// Current feed cache hit rate (percentage)
    pub static ref FEED_CACHE_HIT_RATE: GaugeVec = register_gauge_vec_with_registry!(
        "feed_cache_hit_rate_percent",
        "Current feed cache hit rate (0-100%)",
        &["cache_layer"],
        REGISTRY
    )
    .unwrap();

    /// Kafka consumer lag for events topic (seconds)
    pub static ref FEED_KAFKA_LAG_SECONDS: GaugeVec = register_gauge_vec_with_registry!(
        "feed_kafka_lag_seconds",
        "Time lag between Kafka events and feed visibility (seconds)",
        &["partition"],
        REGISTRY
    )
    .unwrap();

    /// Current number of posts in feed cache
    pub static ref FEED_CACHE_SIZE: GaugeVec = register_gauge_vec_with_registry!(
        "feed_cache_size",
        "Number of cached feed entries",
        &["cache_layer"],
        REGISTRY
    )
    .unwrap();

    /// Feed API request rate (requests per second)
    pub static ref FEED_API_REQUEST_RATE: GaugeVec = register_gauge_vec_with_registry!(
        "feed_api_request_rate",
        "Current feed API request rate (req/s)",
        &["source"],
        REGISTRY
    )
    .unwrap();

    // ======================
    // Phase 3 Enhancements
    // ======================

    /// Circuit breaker state for ClickHouse queries
    /// 0=Closed, 1=HalfOpen, 2=Open
    pub static ref CIRCUIT_BREAKER_STATE: GaugeVec = register_gauge_vec_with_registry!(
        "feed_circuit_breaker_state",
        "Circuit breaker state (0=Closed, 1=HalfOpen, 2=Open)",
        &["service"],
        REGISTRY
    )
    .unwrap();

    /// Posts removed by deduplication
    pub static ref DEDUP_POSTS_REMOVED: CounterVec = register_counter_vec_with_registry!(
        "feed_dedup_posts_removed_total",
        "Total posts removed by deduplication",
        &["reason"],
        REGISTRY
    )
    .unwrap();

    /// Posts removed by saturation control
    pub static ref SATURATION_POSTS_REMOVED: CounterVec = register_counter_vec_with_registry!(
        "feed_saturation_posts_removed_total",
        "Total posts removed by author saturation control",
        &["rule"],
        REGISTRY
    )
    .unwrap();

    /// Number of users with warmed cache (Top 1000)
    pub static ref TOP_1000_USERS_WARMED: GaugeVec = register_gauge_vec_with_registry!(
        "feed_top_1000_users_warmed",
        "Number of top 1000 users with warmed cache",
        &["status"],
        REGISTRY
    )
    .unwrap();

    /// Cache invalidation events
    pub static ref CACHE_INVALIDATIONS: CounterVec = register_counter_vec_with_registry!(
        "feed_cache_invalidations_total",
        "Total cache invalidation events",
        &["event_type"],
        REGISTRY
    )
    .unwrap();
}

/// Helper functions for recording feed metrics
pub mod helpers {
    use super::*;
    use std::time::Instant;

    /// Record a feed API request
    pub fn record_feed_request(source: &str, status: &str, latency_ms: u64) {
        FEED_API_REQUESTS.with_label_values(&[source, status]).inc();
        FEED_API_LATENCY_MS
            .with_label_values(&[source])
            .observe(latency_ms as f64);
    }

    /// Record a feed cache operation
    pub fn record_cache_operation(operation: &str, result: &str) {
        FEED_CACHE_OPERATIONS
            .with_label_values(&[operation, result])
            .inc();
    }

    /// Record a fallback to PostgreSQL
    pub fn record_fallback_postgres(reason: &str) {
        FEED_FALLBACK_POSTGRES.with_label_values(&[reason]).inc();
    }

    /// Record feed ranking computation duration
    pub fn record_ranking_duration(strategy: &str, duration_ms: u64) {
        FEED_RANKING_DURATION_MS
            .with_label_values(&[strategy])
            .observe(duration_ms as f64);
    }

    /// Record ClickHouse query latency for feed data
    pub fn record_clickhouse_query(query_type: &str, duration_ms: u64) {
        FEED_CLICKHOUSE_QUERY_MS
            .with_label_values(&[query_type])
            .observe(duration_ms as f64);
    }

    /// Update feed cache hit rate
    pub fn update_cache_hit_rate(cache_layer: &str, hit_rate_percent: f64) {
        FEED_CACHE_HIT_RATE
            .with_label_values(&[cache_layer])
            .set(hit_rate_percent);
    }

    /// Update Kafka consumer lag
    pub fn update_kafka_lag(partition: i32, lag_seconds: i64) {
        FEED_KAFKA_LAG_SECONDS
            .with_label_values(&[&partition.to_string()])
            .set(lag_seconds as f64);
    }

    /// Update feed cache size
    pub fn update_cache_size(cache_layer: &str, size: usize) {
        FEED_CACHE_SIZE
            .with_label_values(&[cache_layer])
            .set(size as f64);
    }

    /// Update feed API request rate
    pub fn update_request_rate(source: &str, rate: f64) {
        FEED_API_REQUEST_RATE.with_label_values(&[source]).set(rate);
    }

    /// Update circuit breaker state (0=Closed, 1=HalfOpen, 2=Open)
    pub fn update_circuit_breaker_state(service: &str, state: u8) {
        CIRCUIT_BREAKER_STATE
            .with_label_values(&[service])
            .set(state as f64);
    }

    /// Record posts removed by deduplication
    pub fn record_dedup_removed(reason: &str, count: usize) {
        DEDUP_POSTS_REMOVED
            .with_label_values(&[reason])
            .inc_by(count as f64);
    }

    /// Record posts removed by saturation control
    pub fn record_saturation_removed(rule: &str, count: usize) {
        SATURATION_POSTS_REMOVED
            .with_label_values(&[rule])
            .inc_by(count as f64);
    }

    /// Update top 1000 users warmed count
    pub fn update_top_1000_warmed(status: &str, count: usize) {
        TOP_1000_USERS_WARMED
            .with_label_values(&[status])
            .set(count as f64);
    }

    /// Record cache invalidation event
    pub fn record_cache_invalidation(event_type: &str) {
        CACHE_INVALIDATIONS.with_label_values(&[event_type]).inc();
    }

    /// Timer guard for automatic feed API latency tracking
    pub struct FeedApiTimer {
        start: Instant,
        source: String,
    }

    impl FeedApiTimer {
        pub fn new(source: &str) -> Self {
            Self {
                start: Instant::now(),
                source: source.to_string(),
            }
        }

        pub fn finish_success(self) {
            let latency_ms = self.start.elapsed().as_millis() as u64;
            record_feed_request(&self.source, "success", latency_ms);
        }

        pub fn finish_error(self) {
            let latency_ms = self.start.elapsed().as_millis() as u64;
            record_feed_request(&self.source, "error", latency_ms);
        }
    }

    /// Timer guard for feed ranking computation
    pub struct RankingTimer {
        start: Instant,
        strategy: String,
    }

    impl RankingTimer {
        pub fn new(strategy: &str) -> Self {
            Self {
                start: Instant::now(),
                strategy: strategy.to_string(),
            }
        }
    }

    impl Drop for RankingTimer {
        fn drop(&mut self) {
            let duration_ms = self.start.elapsed().as_millis() as u64;
            record_ranking_duration(&self.strategy, duration_ms);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_record_feed_request() {
        helpers::record_feed_request("cache_hit", "success", 85);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("feed_api_requests_total"));
        assert!(metrics.contains("feed_api_latency_ms"));
    }

    #[test]
    fn test_record_cache_operation() {
        helpers::record_cache_operation("get", "hit");
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("feed_cache_operations_total"));
    }

    #[test]
    fn test_record_fallback_postgres() {
        helpers::record_fallback_postgres("clickhouse_timeout");
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("feed_fallback_postgres_total"));
    }

    #[test]
    fn test_record_clickhouse_query() {
        helpers::record_clickhouse_query("events_lookup", 120);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("feed_clickhouse_query_ms"));
    }

    #[test]
    fn test_feed_api_timer() {
        {
            let timer = helpers::FeedApiTimer::new("cache_hit");
            std::thread::sleep(std::time::Duration::from_millis(50));
            timer.finish_success();
        }

        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("feed_api_requests_total"));
    }

    #[test]
    fn test_ranking_timer() {
        {
            let _timer = helpers::RankingTimer::new("freshness_boost");
            std::thread::sleep(std::time::Duration::from_millis(30));
        }

        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("feed_ranking_duration_ms"));
    }
}
