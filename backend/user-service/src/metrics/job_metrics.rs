//! Job Metrics for Prometheus
//!
//! 追踪后台任务的执行状态、延迟和错误率

use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec_with_registry, register_gauge_vec_with_registry,
    register_histogram_vec_with_registry, CounterVec, GaugeVec, HistogramVec,
};

use super::REGISTRY;

lazy_static! {
    // ======================
    // Counters (累计值)
    // ======================

    /// Total job executions (labels: job_name, status=success|failed)
    pub static ref JOB_RUNS_TOTAL: CounterVec = register_counter_vec_with_registry!(
        "job_runs_total",
        "Total number of job executions",
        &["job_name", "status"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Total DLQ messages sent (labels: job_name)
    pub static ref JOB_DLQ_MESSAGES_TOTAL: CounterVec = register_counter_vec_with_registry!(
        "job_dlq_messages_total",
        "Total number of DLQ messages sent for failed jobs",
        &["job_name"],
        REGISTRY
    )
    .expect("Failed to register metric");

    // ======================
    // Histograms (延迟分布)
    // ======================

    /// Job execution duration in seconds (labels: job_name)
    pub static ref JOB_DURATION_SECONDS: HistogramVec = register_histogram_vec_with_registry!(
        "job_duration_seconds",
        "Time spent executing jobs",
        &["job_name"],
        vec![0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0],
        REGISTRY
    )
    .expect("Failed to register metric");

    // ======================
    // Gauges (实时值)
    // ======================

    /// Last successful job run timestamp (labels: job_name)
    pub static ref JOB_LAST_SUCCESS_TIMESTAMP: GaugeVec = register_gauge_vec_with_registry!(
        "job_last_success_timestamp",
        "Unix timestamp of the last successful job execution",
        &["job_name"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Job health status (0=unhealthy, 1=healthy) (labels: job_name)
    pub static ref JOB_HEALTH: GaugeVec = register_gauge_vec_with_registry!(
        "job_health",
        "Health status of job (0=unhealthy, 1=healthy)",
        &["job_name"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Consecutive job failures (labels: job_name)
    pub static ref JOB_CONSECUTIVE_FAILURES: GaugeVec = register_gauge_vec_with_registry!(
        "job_consecutive_failures",
        "Number of consecutive failures for a job",
        &["job_name"],
        REGISTRY
    )
    .expect("Failed to register metric");

    /// Items processed in last job run (labels: job_name)
    pub static ref JOB_ITEMS_PROCESSED: GaugeVec = register_gauge_vec_with_registry!(
        "job_items_processed",
        "Number of items processed in the last job execution",
        &["job_name"],
        REGISTRY
    )
    .expect("Failed to register metric");
}

/// Helper functions for job metrics
pub mod helpers {
    use super::*;
    use std::time::Instant;

    /// Record a successful job run
    pub fn record_job_success(job_name: &str, duration_ms: u64, items_processed: usize) {
        JOB_RUNS_TOTAL
            .with_label_values(&[job_name, "success"])
            .inc();

        JOB_DURATION_SECONDS
            .with_label_values(&[job_name])
            .observe(duration_ms as f64 / 1000.0);

        JOB_LAST_SUCCESS_TIMESTAMP
            .with_label_values(&[job_name])
            .set(chrono::Utc::now().timestamp() as f64);

        JOB_HEALTH.with_label_values(&[job_name]).set(1.0);

        JOB_CONSECUTIVE_FAILURES
            .with_label_values(&[job_name])
            .set(0.0);

        JOB_ITEMS_PROCESSED
            .with_label_values(&[job_name])
            .set(items_processed as f64);
    }

    /// Record a failed job run
    pub fn record_job_failure(job_name: &str, duration_ms: u64, consecutive_failures: u32) {
        JOB_RUNS_TOTAL
            .with_label_values(&[job_name, "failed"])
            .inc();

        JOB_DURATION_SECONDS
            .with_label_values(&[job_name])
            .observe(duration_ms as f64 / 1000.0);

        JOB_HEALTH.with_label_values(&[job_name]).set(0.0);

        JOB_CONSECUTIVE_FAILURES
            .with_label_values(&[job_name])
            .set(consecutive_failures as f64);
    }

    /// Record a DLQ message sent
    pub fn record_dlq_message(job_name: &str) {
        JOB_DLQ_MESSAGES_TOTAL.with_label_values(&[job_name]).inc();
    }

    /// Timer guard for automatic job duration tracking
    pub struct JobTimer {
        start: Instant,
        job_name: String,
    }

    impl JobTimer {
        pub fn new(job_name: String) -> Self {
            Self {
                start: Instant::now(),
                job_name,
            }
        }

        pub fn elapsed_ms(&self) -> u64 {
            self.start.elapsed().as_millis() as u64
        }

        pub fn observe_success(self, items_processed: usize) {
            record_job_success(&self.job_name, self.elapsed_ms(), items_processed);
        }

        pub fn observe_failure(self, consecutive_failures: u32) {
            record_job_failure(&self.job_name, self.elapsed_ms(), consecutive_failures);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_record_job_success() {
        helpers::record_job_success("test_job", 150, 100);

        // Verify metrics were recorded (basic smoke test)
        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("job_runs_total"));
        assert!(metrics.contains("job_duration_seconds"));
    }

    #[test]
    fn test_record_job_failure() {
        helpers::record_job_failure("test_job", 250, 3);

        let metrics = super::super::gather_metrics();
        assert!(metrics.contains("job_runs_total"));
        assert!(metrics.contains("job_consecutive_failures"));
    }

    #[test]
    fn test_job_timer() {
        let timer = helpers::JobTimer::new("test_job".to_string());
        std::thread::sleep(std::time::Duration::from_millis(10));
        assert!(timer.elapsed_ms() >= 10);
    }
}
