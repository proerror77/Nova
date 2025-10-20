/// ClickHouse query profiler for performance monitoring and slow query detection
use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec_with_registry, register_histogram_vec_with_registry, CounterVec,
    HistogramVec,
};
use std::time::Instant;
use tracing::{info, warn};

use crate::metrics::REGISTRY;

lazy_static! {
    /// ClickHouse query duration distribution (labels: query_type)
    /// query_type: feed_ranking, events_insert, materialized_view_refresh, etc.
    pub static ref CLICKHOUSE_QUERY_DURATION_MS: HistogramVec = register_histogram_vec_with_registry!(
        "clickhouse_query_duration_ms",
        "ClickHouse query execution duration (ms)",
        &["query_type"],
        vec![10.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0, 10000.0],
        REGISTRY
    )
    .unwrap();

    /// Total slow queries detected (labels: query_type)
    /// Slow query threshold: > 500ms
    pub static ref CLICKHOUSE_SLOW_QUERIES: CounterVec = register_counter_vec_with_registry!(
        "clickhouse_slow_queries_total",
        "Total number of slow queries (> 500ms)",
        &["query_type"],
        REGISTRY
    )
    .unwrap();

    /// Total ClickHouse query errors (labels: query_type, error_type)
    pub static ref CLICKHOUSE_QUERY_ERRORS: CounterVec = register_counter_vec_with_registry!(
        "clickhouse_query_errors_total",
        "Total ClickHouse query errors",
        &["query_type", "error_type"],
        REGISTRY
    )
    .unwrap();

    /// Rows scanned per query (labels: query_type)
    pub static ref CLICKHOUSE_ROWS_SCANNED: HistogramVec = register_histogram_vec_with_registry!(
        "clickhouse_rows_scanned",
        "Number of rows scanned by ClickHouse queries",
        &["query_type"],
        vec![100.0, 1000.0, 10000.0, 100000.0, 1000000.0],
        REGISTRY
    )
    .unwrap();
}

/// Query profiler for automatic timing and logging
pub struct QueryProfiler {
    start: Instant,
    query_type: String,
    query_preview: String,
}

impl QueryProfiler {
    /// Create a new query profiler
    ///
    /// # Arguments
    /// * `query_type` - Type of query (e.g., "feed_ranking", "events_insert")
    /// * `query_text` - Full query text (will be truncated for logging)
    pub fn new(query_type: &str, query_text: &str) -> Self {
        let query_preview = if query_text.len() > 100 {
            format!("{}...", &query_text[..100])
        } else {
            query_text.to_string()
        };

        Self {
            start: Instant::now(),
            query_type: query_type.to_string(),
            query_preview,
        }
    }

    /// Finish profiling and record metrics for a successful query
    pub fn finish_success(self, rows_scanned: usize) {
        let duration_ms = self.start.elapsed().as_millis() as u64;

        // Record duration
        CLICKHOUSE_QUERY_DURATION_MS
            .with_label_values(&[&self.query_type])
            .observe(duration_ms as f64);

        // Record rows scanned
        CLICKHOUSE_ROWS_SCANNED
            .with_label_values(&[&self.query_type])
            .observe(rows_scanned as f64);

        // Detect slow queries (> 500ms)
        if duration_ms > 500 {
            CLICKHOUSE_SLOW_QUERIES
                .with_label_values(&[&self.query_type])
                .inc();

            warn!(
                "[SLOW QUERY] type={} duration_ms={} rows={} query={}",
                self.query_type, duration_ms, rows_scanned, self.query_preview
            );
        } else {
            info!(
                "[QUERY] type={} duration_ms={} rows={}",
                self.query_type, duration_ms, rows_scanned
            );
        }
    }

    /// Finish profiling and record metrics for a failed query
    pub fn finish_error(self, error_type: &str) {
        let duration_ms = self.start.elapsed().as_millis() as u64;

        CLICKHOUSE_QUERY_ERRORS
            .with_label_values(&[&self.query_type, error_type])
            .inc();

        warn!(
            "[QUERY ERROR] type={} duration_ms={} error={} query={}",
            self.query_type, duration_ms, error_type, self.query_preview
        );
    }
}

/// Helper functions for common query profiling scenarios
pub mod helpers {
    use super::*;

    /// Profile a feed ranking query
    pub fn profile_feed_ranking(query: &str) -> QueryProfiler {
        QueryProfiler::new("feed_ranking", query)
    }

    /// Profile an events insert query
    pub fn profile_events_insert(query: &str) -> QueryProfiler {
        QueryProfiler::new("events_insert", query)
    }

    /// Profile a materialized view refresh
    pub fn profile_mv_refresh(query: &str) -> QueryProfiler {
        QueryProfiler::new("materialized_view_refresh", query)
    }

    /// Profile a post metrics aggregation query
    pub fn profile_post_metrics(query: &str) -> QueryProfiler {
        QueryProfiler::new("post_metrics_aggregation", query)
    }

    /// Profile a user affinity query
    pub fn profile_user_affinity(query: &str) -> QueryProfiler {
        QueryProfiler::new("user_affinity", query)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_query_profiler_success() {
        let profiler = QueryProfiler::new("test_query", "SELECT * FROM events WHERE user_id = 123");
        std::thread::sleep(std::time::Duration::from_millis(30));
        profiler.finish_success(1500);

        let metrics = crate::metrics::gather_metrics();
        assert!(metrics.contains("clickhouse_query_duration_ms"));
        assert!(metrics.contains("clickhouse_rows_scanned"));
    }

    #[test]
    fn test_query_profiler_slow_query() {
        let profiler = QueryProfiler::new("slow_query", "SELECT * FROM large_table");
        std::thread::sleep(std::time::Duration::from_millis(600));
        profiler.finish_success(1000000);

        let metrics = crate::metrics::gather_metrics();
        assert!(metrics.contains("clickhouse_slow_queries_total"));
    }

    #[test]
    fn test_query_profiler_error() {
        let profiler = QueryProfiler::new("error_query", "SELECT invalid syntax");
        profiler.finish_error("syntax_error");

        let metrics = crate::metrics::gather_metrics();
        assert!(metrics.contains("clickhouse_query_errors_total"));
    }

    #[test]
    fn test_query_preview_truncation() {
        let long_query = "SELECT ".to_string() + &"column, ".repeat(50) + "FROM table";
        let profiler = QueryProfiler::new("truncate_test", &long_query);
        assert!(profiler.query_preview.len() <= 103); // 100 chars + "..."
    }
}
