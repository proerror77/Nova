//! Cache metrics for observability

use prometheus::{CounterVec, HistogramVec, Opts, Registry};
use std::sync::OnceLock;

static METRICS: OnceLock<CacheMetricsInner> = OnceLock::new();

struct CacheMetricsInner {
    hits: CounterVec,
    misses: CounterVec,
    negative_hits: CounterVec,
    writes: CounterVec,
    negative_writes: CounterVec,
    invalidations: CounterVec,
    errors: CounterVec,
}

impl CacheMetricsInner {
    fn new() -> Self {
        Self {
            hits: CounterVec::new(
                Opts::new("nova_cache_hits_total", "Total cache hits"),
                &["entity"],
            )
            .expect("valid metric definition"),
            misses: CounterVec::new(
                Opts::new("nova_cache_misses_total", "Total cache misses"),
                &["entity"],
            )
            .expect("valid metric definition"),
            negative_hits: CounterVec::new(
                Opts::new(
                    "nova_cache_negative_hits_total",
                    "Total negative cache hits",
                ),
                &["entity"],
            )
            .expect("valid metric definition"),
            writes: CounterVec::new(
                Opts::new("nova_cache_writes_total", "Total cache writes"),
                &["entity"],
            )
            .expect("valid metric definition"),
            negative_writes: CounterVec::new(
                Opts::new(
                    "nova_cache_negative_writes_total",
                    "Total negative cache writes",
                ),
                &["entity"],
            )
            .expect("valid metric definition"),
            invalidations: CounterVec::new(
                Opts::new(
                    "nova_cache_invalidations_total",
                    "Total cache invalidations",
                ),
                &["entity"],
            )
            .expect("valid metric definition"),
            errors: CounterVec::new(
                Opts::new("nova_cache_errors_total", "Total cache errors"),
                &["entity", "error_type"],
            )
            .expect("valid metric definition"),
        }
    }

    fn register(&self, registry: &Registry) -> Result<(), prometheus::Error> {
        registry.register(Box::new(self.hits.clone()))?;
        registry.register(Box::new(self.misses.clone()))?;
        registry.register(Box::new(self.negative_hits.clone()))?;
        registry.register(Box::new(self.writes.clone()))?;
        registry.register(Box::new(self.negative_writes.clone()))?;
        registry.register(Box::new(self.invalidations.clone()))?;
        registry.register(Box::new(self.errors.clone()))?;
        Ok(())
    }
}

fn get_metrics() -> &'static CacheMetricsInner {
    METRICS.get_or_init(CacheMetricsInner::new)
}

/// Extract entity type from cache key for metrics labeling
fn extract_entity(key: &str) -> &str {
    // Format: v{N}:{entity}:...
    let parts: Vec<&str> = key.split(':').collect();
    if parts.len() >= 2 {
        parts[1]
    } else {
        "unknown"
    }
}

/// Cache metrics wrapper
#[derive(Clone, Default)]
pub struct CacheMetrics;

impl CacheMetrics {
    pub fn new() -> Self {
        Self
    }

    /// Register metrics with a Prometheus registry
    pub fn register(registry: &Registry) -> Result<(), prometheus::Error> {
        get_metrics().register(registry)
    }

    pub fn record_hit(&self, key: &str) {
        let entity = extract_entity(key);
        get_metrics().hits.with_label_values(&[entity]).inc();
    }

    pub fn record_miss(&self, key: &str) {
        let entity = extract_entity(key);
        get_metrics().misses.with_label_values(&[entity]).inc();
    }

    pub fn record_negative_hit(&self, key: &str) {
        let entity = extract_entity(key);
        get_metrics()
            .negative_hits
            .with_label_values(&[entity])
            .inc();
    }

    pub fn record_write(&self, key: &str) {
        let entity = extract_entity(key);
        get_metrics().writes.with_label_values(&[entity]).inc();
    }

    pub fn record_negative_write(&self, key: &str) {
        let entity = extract_entity(key);
        get_metrics()
            .negative_writes
            .with_label_values(&[entity])
            .inc();
    }

    pub fn record_invalidation(&self, key: &str) {
        let entity = extract_entity(key);
        get_metrics()
            .invalidations
            .with_label_values(&[entity])
            .inc();
    }

    pub fn record_error(&self, key: &str, error_type: &str) {
        let entity = extract_entity(key);
        get_metrics()
            .errors
            .with_label_values(&[entity, error_type])
            .inc();
    }
}
