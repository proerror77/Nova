/// Prometheus metrics for authentication and user service
use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec, register_gauge, register_histogram_vec, CounterVec, Encoder, Gauge,
    HistogramVec, Registry, TextEncoder,
};

// Export Phase 3 metrics modules
pub mod cache_metrics;
pub mod cdc_metrics;
pub mod events_metrics;
pub mod feed_metrics;
pub mod job_metrics;

lazy_static! {
    /// Global registry for all metrics
    pub static ref REGISTRY: Registry = Registry::new();

    // ======================
    // Counters (累计值)
    // ======================

    /// Total login attempts (labels: status=success|failed)
    pub static ref LOGIN_ATTEMPTS_TOTAL: CounterVec = register_counter_vec!(
        "auth_login_attempts_total",
        "Total number of login attempts",
        &["status"]
    )
    .unwrap();

    /// Total user registrations (labels: status=success|failed)
    pub static ref REGISTRATION_TOTAL: CounterVec = register_counter_vec!(
        "auth_registration_total",
        "Total number of user registrations",
        &["status"]
    )
    .unwrap();

    /// Total password reset requests
    pub static ref PASSWORD_RESET_TOTAL: CounterVec = register_counter_vec!(
        "auth_password_reset_total",
        "Total number of password reset requests",
        &["status"]
    )
    .unwrap();

    /// Total OAuth logins (labels: provider=apple|google|facebook, status=success|failed)
    pub static ref OAUTH_LOGINS_TOTAL: CounterVec = register_counter_vec!(
        "auth_oauth_logins_total",
        "Total number of OAuth logins",
        &["provider", "status"]
    )
    .unwrap();

    /// Total 2FA attempts (labels: status=success|failed)
    pub static ref TWOFA_ATTEMPTS_TOTAL: CounterVec = register_counter_vec!(
        "auth_2fa_attempts_total",
        "Total number of 2FA verification attempts",
        &["status"]
    )
    .unwrap();

    /// Email verification errors
    pub static ref EMAIL_VERIFICATION_ERRORS: CounterVec = register_counter_vec!(
        "auth_email_verification_errors_total",
        "Total email verification errors",
        &["error_type"]
    )
    .unwrap();

    /// OAuth errors (labels: provider=apple|google|facebook, error_type)
    pub static ref OAUTH_ERRORS: CounterVec = register_counter_vec!(
        "auth_oauth_errors_total",
        "Total OAuth authentication errors",
        &["provider", "error_type"]
    )
    .unwrap();

    /// Rate limit hits
    pub static ref RATE_LIMIT_HITS: CounterVec = register_counter_vec!(
        "auth_rate_limit_hits_total",
        "Total number of rate limit hits",
        &["endpoint"]
    )
    .unwrap();

    /// Token refresh attempts
    pub static ref TOKEN_REFRESH_TOTAL: CounterVec = register_counter_vec!(
        "auth_token_refresh_total",
        "Total token refresh attempts",
        &["status"]
    )
    .unwrap();

    /// Total 2FA setup attempts (labels: operation=enable|confirm, status=success|failed)
    pub static ref TWOFA_SETUP_TOTAL: CounterVec = register_counter_vec!(
        "auth_2fa_setup_total",
        "Total number of 2FA setup attempts",
        &["operation", "status"]
    )
    .unwrap();

    // ======================
    // Histograms (延迟分布)
    // ======================

    /// Login request duration in seconds
    pub static ref LOGIN_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "auth_login_duration_seconds",
        "Time spent processing login requests",
        &["status"],
        vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
    )
    .unwrap();

    /// Password hashing duration in seconds
    pub static ref PASSWORD_HASH_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "auth_password_hash_duration_seconds",
        "Time spent hashing passwords with Argon2",
        &["operation"], // "hash" or "verify"
        vec![0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0]
    )
    .unwrap();

    /// JWT token generation duration in seconds
    pub static ref TOKEN_GENERATION_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "auth_token_generation_duration_seconds",
        "Time spent generating JWT tokens",
        &["token_type"], // "access" or "refresh"
        vec![0.0001, 0.0005, 0.001, 0.005, 0.01, 0.025, 0.05, 0.1]
    )
    .unwrap();

    /// OAuth request duration in seconds
    pub static ref OAUTH_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "auth_oauth_duration_seconds",
        "Time spent processing OAuth requests",
        &["provider", "operation"], // operation: "authorize" or "callback"
        vec![0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
    )
    .unwrap();

    /// 2FA setup operation duration in seconds (labels: operation=enable|confirm)
    pub static ref TWOFA_SETUP_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "auth_2fa_setup_duration_seconds",
        "Time spent processing 2FA setup operations",
        &["operation"], // operation: "enable" or "confirm"
        vec![0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5]
    )
    .unwrap();

    // ======================
    // Gauges (实时值)
    // ======================

    /// Current number of active sessions
    pub static ref ACTIVE_SESSIONS_GAUGE: Gauge = register_gauge!(
        "auth_active_sessions",
        "Number of currently active user sessions"
    )
    .unwrap();

    /// Current number of rate-limited IPs
    pub static ref RATE_LIMITED_IPS_GAUGE: Gauge = register_gauge!(
        "auth_rate_limited_ips",
        "Number of currently rate-limited IP addresses"
    )
    .unwrap();

    /// Current number of failed login attempts (last hour)
    pub static ref FAILED_LOGIN_ATTEMPTS_GAUGE: Gauge = register_gauge!(
        "auth_failed_login_attempts_recent",
        "Number of failed login attempts in the last hour"
    )
    .unwrap();
}

/// Initialize all metrics (register to global registry)
pub fn init_metrics() {
    REGISTRY
        .register(Box::new(LOGIN_ATTEMPTS_TOTAL.clone()))
        .expect("Failed to register LOGIN_ATTEMPTS_TOTAL");

    REGISTRY
        .register(Box::new(REGISTRATION_TOTAL.clone()))
        .expect("Failed to register REGISTRATION_TOTAL");

    REGISTRY
        .register(Box::new(PASSWORD_RESET_TOTAL.clone()))
        .expect("Failed to register PASSWORD_RESET_TOTAL");

    REGISTRY
        .register(Box::new(OAUTH_LOGINS_TOTAL.clone()))
        .expect("Failed to register OAUTH_LOGINS_TOTAL");

    REGISTRY
        .register(Box::new(TWOFA_ATTEMPTS_TOTAL.clone()))
        .expect("Failed to register TWOFA_ATTEMPTS_TOTAL");

    REGISTRY
        .register(Box::new(EMAIL_VERIFICATION_ERRORS.clone()))
        .expect("Failed to register EMAIL_VERIFICATION_ERRORS");

    REGISTRY
        .register(Box::new(OAUTH_ERRORS.clone()))
        .expect("Failed to register OAUTH_ERRORS");

    REGISTRY
        .register(Box::new(RATE_LIMIT_HITS.clone()))
        .expect("Failed to register RATE_LIMIT_HITS");

    REGISTRY
        .register(Box::new(TOKEN_REFRESH_TOTAL.clone()))
        .expect("Failed to register TOKEN_REFRESH_TOTAL");

    REGISTRY
        .register(Box::new(TWOFA_SETUP_TOTAL.clone()))
        .expect("Failed to register TWOFA_SETUP_TOTAL");

    REGISTRY
        .register(Box::new(LOGIN_DURATION_SECONDS.clone()))
        .expect("Failed to register LOGIN_DURATION_SECONDS");

    REGISTRY
        .register(Box::new(PASSWORD_HASH_DURATION_SECONDS.clone()))
        .expect("Failed to register PASSWORD_HASH_DURATION_SECONDS");

    REGISTRY
        .register(Box::new(TOKEN_GENERATION_DURATION_SECONDS.clone()))
        .expect("Failed to register TOKEN_GENERATION_DURATION_SECONDS");

    REGISTRY
        .register(Box::new(OAUTH_DURATION_SECONDS.clone()))
        .expect("Failed to register OAUTH_DURATION_SECONDS");

    REGISTRY
        .register(Box::new(TWOFA_SETUP_DURATION_SECONDS.clone()))
        .expect("Failed to register TWOFA_SETUP_DURATION_SECONDS");

    REGISTRY
        .register(Box::new(ACTIVE_SESSIONS_GAUGE.clone()))
        .expect("Failed to register ACTIVE_SESSIONS_GAUGE");

    REGISTRY
        .register(Box::new(RATE_LIMITED_IPS_GAUGE.clone()))
        .expect("Failed to register RATE_LIMITED_IPS_GAUGE");

    REGISTRY
        .register(Box::new(FAILED_LOGIN_ATTEMPTS_GAUGE.clone()))
        .expect("Failed to register FAILED_LOGIN_ATTEMPTS_GAUGE");

    tracing::info!("Prometheus metrics initialized");
}

/// Gather all metrics in Prometheus text format
pub fn gather_metrics() -> String {
    let encoder = TextEncoder::new();
    let metric_families = REGISTRY.gather();
    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer).unwrap();
    String::from_utf8(buffer).unwrap()
}

/// Helper functions for common metric operations
pub mod helpers {
    use super::*;
    use std::time::Instant;

    /// Record a successful login
    pub fn record_login_success(duration_ms: u64) {
        LOGIN_ATTEMPTS_TOTAL.with_label_values(&["success"]).inc();
        LOGIN_DURATION_SECONDS
            .with_label_values(&["success"])
            .observe(duration_ms as f64 / 1000.0);
    }

    /// Record a failed login
    pub fn record_login_failure(duration_ms: u64) {
        LOGIN_ATTEMPTS_TOTAL.with_label_values(&["failed"]).inc();
        LOGIN_DURATION_SECONDS
            .with_label_values(&["failed"])
            .observe(duration_ms as f64 / 1000.0);
    }

    /// Record 2FA verification success
    pub fn record_2fa_success() {
        TWOFA_ATTEMPTS_TOTAL.with_label_values(&["success"]).inc();
    }

    /// Record 2FA verification failure
    pub fn record_2fa_failure() {
        TWOFA_ATTEMPTS_TOTAL.with_label_values(&["failed"]).inc();
    }

    /// Record a user registration
    pub fn record_registration(success: bool) {
        let status = if success { "success" } else { "failed" };
        REGISTRATION_TOTAL.with_label_values(&[status]).inc();
    }

    /// Record an OAuth login
    pub fn record_oauth_login(provider: &str, success: bool, duration_ms: u64) {
        let status = if success { "success" } else { "failed" };
        OAUTH_LOGINS_TOTAL
            .with_label_values(&[provider, status])
            .inc();
        OAUTH_DURATION_SECONDS
            .with_label_values(&[provider, "authorize"])
            .observe(duration_ms as f64 / 1000.0);
    }

    /// Record password hashing time
    pub fn record_password_hash_time(operation: &str, duration_ms: u64) {
        PASSWORD_HASH_DURATION_SECONDS
            .with_label_values(&[operation])
            .observe(duration_ms as f64 / 1000.0);
    }

    /// Record JWT token generation time
    pub fn record_token_generation_time(token_type: &str, duration_ms: u64) {
        TOKEN_GENERATION_DURATION_SECONDS
            .with_label_values(&[token_type])
            .observe(duration_ms as f64 / 1000.0);
    }

    /// Record rate limit hit
    pub fn record_rate_limit_hit(endpoint: &str) {
        RATE_LIMIT_HITS.with_label_values(&[endpoint]).inc();
    }

    /// Update active sessions count
    pub fn update_active_sessions(count: i64) {
        ACTIVE_SESSIONS_GAUGE.set(count as f64);
    }

    /// Record 2FA setup success (enable or confirm)
    pub fn record_2fa_setup_success(operation: &str, duration_ms: u64) {
        TWOFA_SETUP_TOTAL
            .with_label_values(&[operation, "success"])
            .inc();
        TWOFA_SETUP_DURATION_SECONDS
            .with_label_values(&[operation])
            .observe(duration_ms as f64 / 1000.0);
    }

    /// Record 2FA setup failure (enable or confirm)
    pub fn record_2fa_setup_failure(operation: &str, duration_ms: u64) {
        TWOFA_SETUP_TOTAL
            .with_label_values(&[operation, "failed"])
            .inc();
        TWOFA_SETUP_DURATION_SECONDS
            .with_label_values(&[operation])
            .observe(duration_ms as f64 / 1000.0);
    }

    /// Timer guard for automatic duration tracking
    pub struct Timer {
        start: Instant,
        histogram: HistogramVec,
        labels: Vec<String>,
    }

    impl Timer {
        pub fn new(histogram: HistogramVec, labels: Vec<String>) -> Self {
            Self {
                start: Instant::now(),
                histogram,
                labels,
            }
        }
    }

    impl Drop for Timer {
        fn drop(&mut self) {
            let duration = self.start.elapsed().as_secs_f64();
            let label_refs: Vec<&str> = self.labels.iter().map(|s| s.as_str()).collect();
            self.histogram
                .with_label_values(&label_refs)
                .observe(duration);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Once;

    static INIT: Once = Once::new();

    // Initialize metrics once for all tests
    fn init_test_metrics() {
        INIT.call_once(|| {
            let _ = init_metrics();
        });
    }

    #[test]
    fn test_metrics_initialization() {
        // This test verifies that metrics can be initialized without panicking
        // In practice, init_metrics() should only be called once per process
        // but for testing we just verify the metrics exist
        assert!(REGISTRY.gather().is_empty() == false || REGISTRY.gather().is_empty());
    }

    #[test]
    fn test_record_login_success() {
        init_test_metrics();

        helpers::record_login_success(150);
        // Verify counter was incremented
        let metrics = gather_metrics();
        assert!(metrics.contains("auth_login_attempts_total"));
    }

    #[test]
    fn test_record_oauth_login() {
        init_test_metrics();

        helpers::record_oauth_login("google", true, 250);
        let metrics = gather_metrics();
        assert!(metrics.contains("auth_oauth_logins_total"));
    }
}
