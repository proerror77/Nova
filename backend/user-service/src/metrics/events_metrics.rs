/// Event ingestion and processing metrics (Kafka → ClickHouse pipeline)
use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec_with_registry, register_gauge_vec_with_registry,
    register_histogram_vec_with_registry, CounterVec, GaugeVec, HistogramVec,
};

use super::REGISTRY;

lazy_static! {
    // ======================
    // Counters - 事件消费和去重
    // ======================

    /// Total events consumed from Kafka (labels: status)
    /// status: success (inserted), duplicate (skipped), error (failed)
    pub static ref EVENTS_CONSUMED: CounterVec = register_counter_vec_with_registry!(
        "events_consumed_total",
        "Total number of events consumed from Kafka user events topic",
        &["status"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Total events inserted into ClickHouse (labels: batch_size)
    /// Tracks batch insert efficiency
    pub static ref EVENTS_INSERTED: CounterVec = register_counter_vec_with_registry!(
        "events_inserted_total",
        "Total number of events successfully inserted into ClickHouse",
        &["batch_size"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Deduplication cache hits (event already processed)
    pub static ref EVENTS_DEDUP_HITS: CounterVec = register_counter_vec_with_registry!(
        "events_dedup_hits_total",
        "Total number of duplicate events detected via dedup cache",
        &["action"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Deduplication cache misses (new event)
    pub static ref EVENTS_DEDUP_MISSES: CounterVec = register_counter_vec_with_registry!(
        "events_dedup_misses_total",
        "Total number of new events (cache miss)",
        &["action"],
        REGISTRY
    )
    .expect("Failed to register metric");

    // ======================
    // Histograms - 事件处理延迟
    // ======================

    /// End-to-end event processing latency (labels: stage)
    /// Tracks latency from event creation → Kafka → ClickHouse → materialized view
    /// Stages: kafka_consume, clickhouse_insert, total_e2e
    pub static ref EVENTS_PROCESSING_LATENCY_MS: HistogramVec = register_histogram_vec_with_registry!(
        "events_processing_latency_ms",
        "Time spent processing events at different stages (ms)",
        &["stage"],
        vec![10.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Batch insert size distribution
    /// Helps optimize batch size configuration
    pub static ref EVENTS_BATCH_SIZE: HistogramVec = register_histogram_vec_with_registry!(
        "events_batch_size",
        "Number of events in each batch insert",
        &["action"],
        vec![10.0, 50.0, 100.0, 250.0, 500.0, 1000.0],
        REGISTRY
    )
    .expect("Failed to register metric");

    // ======================
    // Gauges - 消费者实时状态
    // ======================

    /// Current consumer lag in seconds (time behind)
    pub static ref EVENTS_CONSUMER_LAG_SECONDS: GaugeVec = register_gauge_vec_with_registry!(
        "events_consumer_lag_seconds",
        "Time difference between now and last consumed event timestamp (seconds)",
        &["partition"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Current dedup cache size (entries)
    pub static ref EVENTS_DEDUP_CACHE_SIZE: GaugeVec = register_gauge_vec_with_registry!(
        "events_dedup_cache_size",
        "Number of entries in the deduplication cache",
        &["cache_type"],
        REGISTRY
    )
    .expect("Failed to register metric");
}

/// Helper functions for recording event metrics
pub mod helpers {
    use super::*;
    use std::time::Instant;

    /// Record a successfully consumed event
    pub fn record_event_consumed(action: &str, is_duplicate: bool) {
        let status = if is_duplicate { "duplicate" } else { "success" };
        EVENTS_CONSUMED.with_label_values(&[status]).inc();

        if is_duplicate {
            EVENTS_DEDUP_HITS.with_label_values(&[action]).inc();
        } else {
            EVENTS_DEDUP_MISSES.with_label_values(&[action]).inc();
        }
    }

    /// Record a failed event consumption
    pub fn record_event_error() {
        EVENTS_CONSUMED.with_label_values(&["error"]).inc();
    }

    /// Record batch insert into ClickHouse
    pub fn record_batch_insert(batch_size: usize, duration_ms: u64) {
        let size_label = format!("{}", batch_size);
        EVENTS_INSERTED.with_label_values(&[&size_label]).inc();

        EVENTS_PROCESSING_LATENCY_MS
            .with_label_values(&["clickhouse_insert"])
            .observe(duration_ms as f64);
    }

    /// Record end-to-end event processing latency
    pub fn record_e2e_latency(latency_ms: u64) {
        EVENTS_PROCESSING_LATENCY_MS
            .with_label_values(&["total_e2e"])
            .observe(latency_ms as f64);
    }

    /// Update consumer lag (time behind)
    pub fn update_consumer_lag(partition: i32, lag_seconds: i64) {
        EVENTS_CONSUMER_LAG_SECONDS
            .with_label_values(&[&partition.to_string()])
            .set(lag_seconds as f64);
    }

    /// Update dedup cache size
    pub fn update_dedup_cache_size(cache_type: &str, size: usize) {
        EVENTS_DEDUP_CACHE_SIZE
            .with_label_values(&[cache_type])
            .set(size as f64);
    }

    /// Timer guard for automatic event processing duration tracking
    pub struct EventTimer {
        start: Instant,
        stage: String,
    }

    impl EventTimer {
        pub fn new(stage: &str) -> Self {
            Self {
                start: Instant::now(),
                stage: stage.to_string(),
            }
        }
    }

    impl Drop for EventTimer {
        fn drop(&mut self) {
            let duration_ms = self.start.elapsed().as_millis() as u64;
            EVENTS_PROCESSING_LATENCY_MS
                .with_label_values(&[&self.stage])
                .observe(duration_ms as f64);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_record_event_consumed() {
        helpers::record_event_consumed("view", false);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("events_consumed_total"));
        assert!(metrics.contains("events_dedup_misses_total"));
    }

    #[test]
    fn test_record_event_duplicate() {
        helpers::record_event_consumed("like", true);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("events_dedup_hits_total"));
    }

    #[test]
    fn test_record_batch_insert() {
        helpers::record_batch_insert(100, 250);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("events_inserted_total"));
        assert!(metrics.contains("events_processing_latency_ms"));
    }

    #[test]
    fn test_event_timer() {
        {
            let _timer = helpers::EventTimer::new("kafka_consume");
            std::thread::sleep(std::time::Duration::from_millis(30));
        }

        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("events_processing_latency_ms"));
    }
}
