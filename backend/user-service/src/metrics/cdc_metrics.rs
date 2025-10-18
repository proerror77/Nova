/// CDC (Change Data Capture) consumer metrics for Debezium/Kafka
use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec_with_registry, register_gauge_vec_with_registry,
    register_histogram_vec_with_registry, CounterVec, GaugeVec, HistogramVec,
};

use super::REGISTRY;

lazy_static! {
    // ======================
    // Counters - CDC 消息处理
    // ======================

    /// Total CDC messages consumed from Kafka (labels: table, operation)
    /// table: users, posts, likes, comments, etc.
    /// operation: create, update, delete, read
    pub static ref CDC_MESSAGES_CONSUMED: CounterVec = register_counter_vec_with_registry!(
        "cdc_messages_consumed_total",
        "Total number of CDC messages consumed from Kafka topics",
        &["table", "operation"],
        REGISTRY
    )
    .unwrap();

    /// Successful CDC inserts into ClickHouse (labels: table)
    pub static ref CDC_INSERTS_SUCCESS: CounterVec = register_counter_vec_with_registry!(
        "cdc_inserts_success_total",
        "Total successful CDC inserts into ClickHouse",
        &["table"],
        REGISTRY
    )
    .unwrap();

    /// Failed CDC inserts into ClickHouse (labels: table, error_type)
    pub static ref CDC_INSERTS_FAILED: CounterVec = register_counter_vec_with_registry!(
        "cdc_inserts_failed_total",
        "Total failed CDC inserts into ClickHouse",
        &["table", "error_type"],
        REGISTRY
    )
    .unwrap();

    /// Total Kafka offset commits (labels: topic)
    pub static ref CDC_OFFSETS_COMMITTED: CounterVec = register_counter_vec_with_registry!(
        "cdc_offsets_committed_total",
        "Total number of Kafka consumer offset commits",
        &["topic"],
        REGISTRY
    )
    .unwrap();

    // ======================
    // Histograms - CDC 延迟分布
    // ======================

    /// CDC message processing duration (labels: table)
    /// Buckets optimized for typical database replication latency: 10ms ~ 1000ms
    pub static ref CDC_MESSAGE_PROCESSING_DURATION_MS: HistogramVec = register_histogram_vec_with_registry!(
        "cdc_message_processing_duration_ms",
        "Time spent processing a single CDC message (ms)",
        &["table"],
        vec![10.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0],
        REGISTRY
    )
    .unwrap();

    /// Kafka offset commit duration (labels: topic)
    pub static ref CDC_OFFSET_COMMIT_DURATION_MS: HistogramVec = register_histogram_vec_with_registry!(
        "cdc_offset_commit_duration_ms",
        "Time spent committing Kafka consumer offsets (ms)",
        &["topic"],
        vec![5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0],
        REGISTRY
    )
    .unwrap();

    // ======================
    // Gauges - CDC 实时状态
    // ======================

    /// Current consumer lag per partition (labels: table, partition)
    /// 表示当前消费者与 Kafka topic 最新 offset 的差距(消息数)
    pub static ref CDC_CONSUMER_LAG_MESSAGES: GaugeVec = register_gauge_vec_with_registry!(
        "cdc_consumer_lag_messages",
        "Number of messages behind the Kafka topic head (per partition)",
        &["table", "partition"],
        REGISTRY
    )
    .unwrap();

    /// Consumer lag age in seconds (labels: table)
    /// 表示最后消费的消息时间戳与当前时间的差距(秒)
    pub static ref CDC_LAG_AGE_SECONDS: GaugeVec = register_gauge_vec_with_registry!(
        "cdc_lag_age_seconds",
        "Time difference between now and the last consumed message timestamp (seconds)",
        &["table"],
        REGISTRY
    )
    .unwrap();
}

/// Helper functions for recording CDC metrics
pub mod helpers {
    use super::*;
    use std::time::Instant;

    /// Record a successful CDC message consumption
    pub fn record_message_consumed(table: &str, operation: &str) {
        CDC_MESSAGES_CONSUMED
            .with_label_values(&[table, operation])
            .inc();
    }

    /// Record a successful CDC insert into ClickHouse
    pub fn record_insert_success(table: &str, duration_ms: u64) {
        CDC_INSERTS_SUCCESS.with_label_values(&[table]).inc();
        CDC_MESSAGE_PROCESSING_DURATION_MS
            .with_label_values(&[table])
            .observe(duration_ms as f64);
    }

    /// Record a failed CDC insert into ClickHouse
    pub fn record_insert_failure(table: &str, error_type: &str, duration_ms: u64) {
        CDC_INSERTS_FAILED
            .with_label_values(&[table, error_type])
            .inc();
        CDC_MESSAGE_PROCESSING_DURATION_MS
            .with_label_values(&[table])
            .observe(duration_ms as f64);
    }

    /// Record a Kafka offset commit
    pub fn record_offset_commit(topic: &str, duration_ms: u64) {
        CDC_OFFSETS_COMMITTED.with_label_values(&[topic]).inc();
        CDC_OFFSET_COMMIT_DURATION_MS
            .with_label_values(&[topic])
            .observe(duration_ms as f64);
    }

    /// Update consumer lag (messages behind)
    pub fn update_consumer_lag(table: &str, partition: i32, lag_messages: i64) {
        CDC_CONSUMER_LAG_MESSAGES
            .with_label_values(&[table, &partition.to_string()])
            .set(lag_messages as f64);
    }

    /// Update lag age (time difference)
    pub fn update_lag_age_seconds(table: &str, lag_seconds: i64) {
        CDC_LAG_AGE_SECONDS
            .with_label_values(&[table])
            .set(lag_seconds as f64);
    }

    /// Timer guard for automatic CDC processing duration tracking
    pub struct CdcTimer {
        start: Instant,
        table: String,
    }

    impl CdcTimer {
        pub fn new(table: &str) -> Self {
            Self {
                start: Instant::now(),
                table: table.to_string(),
            }
        }

        pub fn finish_success(self) {
            let duration_ms = self.start.elapsed().as_millis() as u64;
            record_insert_success(&self.table, duration_ms);
        }

        pub fn finish_failure(self, error_type: &str) {
            let duration_ms = self.start.elapsed().as_millis() as u64;
            record_insert_failure(&self.table, error_type, duration_ms);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_record_message_consumed() {
        helpers::record_message_consumed("users", "create");
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("cdc_messages_consumed_total"));
    }

    #[test]
    fn test_record_insert_success() {
        helpers::record_insert_success("posts", 150);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("cdc_inserts_success_total"));
        assert!(metrics.contains("cdc_message_processing_duration_ms"));
    }

    #[test]
    fn test_update_consumer_lag() {
        helpers::update_consumer_lag("users", 0, 1500);
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("cdc_consumer_lag_messages"));
    }

    #[test]
    fn test_cdc_timer() {
        let timer = helpers::CdcTimer::new("comments");
        std::thread::sleep(std::time::Duration::from_millis(50));
        timer.finish_success();

        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("cdc_inserts_success_total"));
    }
}
