//! Feed Cleaner Metrics
//!
//! Prometheus metrics for feed cleaner background job

use once_cell::sync::Lazy;
use prometheus::{
    register_histogram_vec, register_int_counter_vec, register_int_gauge, HistogramVec,
    IntCounterVec, IntGauge,
};
use std::time::Duration;

static CLEANUP_RUNS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "feed_cleaner_runs_total",
        "Total feed cleanup cycles (success/error)",
        &["status"]
    )
    .expect("Failed to register feed cleaner runs metric")
});

static CLEANUP_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    register_histogram_vec!(
        "feed_cleaner_duration_seconds",
        "Duration of feed cleanup operations",
        &["operation"],
        vec![0.001, 0.01, 0.1, 0.5, 1.0, 5.0, 10.0, 30.0, 60.0]
    )
    .expect("Failed to register feed cleaner duration metric")
});

static USERS_CHECKED: Lazy<IntGauge> = Lazy::new(|| {
    register_int_gauge!(
        "feed_cleaner_users_checked",
        "Number of users checked in last cleanup cycle"
    )
    .expect("Failed to register feed cleaner users checked metric")
});

static CONTENT_DELETED_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "feed_cleaner_content_deleted_total",
        "Total content deleted from deleted users",
        &["content_type"]
    )
    .expect("Failed to register feed cleaner content deleted metric")
});

/// Record cleanup run result (success/error)
pub fn record_cleanup_run(status: &str) {
    CLEANUP_RUNS_TOTAL.with_label_values(&[status]).inc();
}

/// Record cleanup operation duration
pub fn record_cleanup_duration(operation: &str, duration: Duration) {
    CLEANUP_DURATION_SECONDS
        .with_label_values(&[operation])
        .observe(duration.as_secs_f64());
}

/// Set number of users checked in current cycle
pub fn set_users_checked(count: i64) {
    USERS_CHECKED.set(count);
}

/// Record content deletion count by type (experiments/assignments/metrics)
pub fn record_content_deleted(content_type: &str, count: u64) {
    CONTENT_DELETED_TOTAL
        .with_label_values(&[content_type])
        .inc_by(count);
}
