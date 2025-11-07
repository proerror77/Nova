//! Prometheus metrics for content cleaner background job
//!
//! Tracks cleanup cycles, deleted content counts, and performance metrics

use once_cell::sync::Lazy;
use prometheus::{
    register_histogram_vec, register_int_counter_vec, register_int_gauge, HistogramVec,
    IntCounterVec, IntGauge,
};
use std::time::Duration;

/// Total number of cleanup cycles run (success/error)
static CLEANUP_RUNS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "content_cleaner_runs_total",
        "Total number of content cleanup cycles (success/error)",
        &["status"]
    )
    .expect("failed to register content_cleaner_runs_total")
});

/// Duration of cleanup operations
static CLEANUP_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    register_histogram_vec!(
        "content_cleaner_duration_seconds",
        "Duration of content cleanup operations",
        &["operation"],
        vec![0.001, 0.01, 0.1, 0.5, 1.0, 5.0, 10.0, 30.0, 60.0]
    )
    .expect("failed to register content_cleaner_duration_seconds")
});

/// Number of users checked in last cleanup cycle
static USERS_CHECKED: Lazy<IntGauge> = Lazy::new(|| {
    register_int_gauge!(
        "content_cleaner_users_checked",
        "Number of users checked in last cleanup cycle"
    )
    .expect("failed to register content_cleaner_users_checked")
});

/// Total content items deleted per type
static CONTENT_DELETED_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "content_cleaner_deleted_total",
        "Total content items deleted from deleted users",
        &["content_type"]
    )
    .expect("failed to register content_cleaner_deleted_total")
});

/// Record a cleanup cycle completion
pub fn record_cleanup_run(status: &str) {
    CLEANUP_RUNS_TOTAL.with_label_values(&[status]).inc();
}

/// Record cleanup operation duration
pub fn record_cleanup_duration(operation: &str, duration: Duration) {
    CLEANUP_DURATION_SECONDS
        .with_label_values(&[operation])
        .observe(duration.as_secs_f64());
}

/// Set number of users checked
pub fn set_users_checked(count: i64) {
    USERS_CHECKED.set(count);
}

/// Record content deletion
pub fn record_content_deleted(content_type: &str, count: u64) {
    CONTENT_DELETED_TOTAL
        .with_label_values(&[content_type])
        .inc_by(count);
}
