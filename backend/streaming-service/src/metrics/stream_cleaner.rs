/// Prometheus Metrics for Stream Cleaner (Phase 4 - Spec 007)
///
/// Monitors cleanup operations for deleted broadcaster streaming data:
/// - Cleanup cycle success/failure rates
/// - Operation durations (collect, validate, cleanup)
/// - User count checked per cycle
/// - Content deletion counts (streams, keys, sessions)
use std::time::Duration;

use once_cell::sync::Lazy;
use prometheus::{
    register_histogram_vec, register_int_counter_vec, register_int_gauge, HistogramVec,
    IntCounterVec, IntGauge,
};

/// Total cleanup cycles executed (success/error)
static CLEANUP_RUNS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "stream_cleaner_runs_total",
        "Total stream cleanup cycles executed (success/error)",
        &["status"]
    )
    .unwrap()
});

/// Duration of cleanup operations in seconds
///
/// Operations:
/// - collect_user_ids: UNION query to collect broadcaster/viewer IDs
/// - validate_users: Batch gRPC calls to auth-service
/// - cleanup_streams: UPDATE/DELETE operations per user
/// - batch_grpc_call: Individual batch API latency
static CLEANUP_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    register_histogram_vec!(
        "stream_cleaner_duration_seconds",
        "Duration of stream cleanup operations in seconds",
        &["operation"],
        vec![0.001, 0.01, 0.1, 0.5, 1.0, 5.0, 10.0, 30.0, 60.0]
    )
    .unwrap()
});

/// Number of users checked in last cleanup cycle
static USERS_CHECKED: Lazy<IntGauge> = Lazy::new(|| {
    register_int_gauge!(
        "stream_cleaner_users_checked",
        "Number of users checked in last cleanup cycle"
    )
    .unwrap()
});

/// Total content deleted from deleted broadcasters
///
/// Content types:
/// - streams_ended: Streams soft-deleted (status = 'ended')
/// - keys_revoked: Stream keys soft-deleted (is_active = false)
/// - sessions_deleted: Viewer sessions hard-deleted
static CONTENT_DELETED_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "stream_cleaner_content_deleted_total",
        "Total content deleted from deleted broadcasters",
        &["content_type"]
    )
    .unwrap()
});

/// Record cleanup cycle execution result
///
/// status: "success" | "error"
pub fn record_cleanup_run(status: &str) {
    CLEANUP_RUNS_TOTAL.with_label_values(&[status]).inc();
}

/// Record duration of cleanup operation
///
/// operation: "collect_user_ids" | "validate_users" | "cleanup_streams" | "batch_grpc_call"
pub fn record_cleanup_duration(operation: &str, duration: Duration) {
    CLEANUP_DURATION_SECONDS
        .with_label_values(&[operation])
        .observe(duration.as_secs_f64());
}

/// Set number of users checked in current cycle
pub fn set_users_checked(count: i64) {
    USERS_CHECKED.set(count);
}

/// Record content deletion count
///
/// content_type: "streams_ended" | "keys_revoked" | "sessions_deleted"
pub fn record_content_deleted(content_type: &str, count: u64) {
    CONTENT_DELETED_TOTAL
        .with_label_values(&[content_type])
        .inc_by(count);
}
