/// Prometheus metrics for resilience patterns
#[cfg(feature = "metrics")]
use prometheus::{
    register_histogram_vec, register_int_counter_vec, Histogram, HistogramVec, IntCounterVec,
};

#[cfg(feature = "metrics")]
use once_cell::sync::Lazy;

#[cfg(feature = "metrics")]
static CIRCUIT_BREAKER_STATE_TRANSITIONS: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "resilience_circuit_breaker_state_transitions_total",
        "Total number of circuit breaker state transitions",
        &["from", "to"]
    )
    .expect("Failed to register circuit breaker state transitions metric")
});

#[cfg(feature = "metrics")]
static CIRCUIT_BREAKER_CALLS: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "resilience_circuit_breaker_calls_total",
        "Total number of circuit breaker calls",
        &["state", "result"]
    )
    .expect("Failed to register circuit breaker calls metric")
});

#[cfg(feature = "metrics")]
static CIRCUIT_BREAKER_OPEN_DURATION: Lazy<Histogram> = Lazy::new(|| {
    prometheus::register_histogram!(
        "resilience_circuit_breaker_open_duration_seconds",
        "Duration circuit breaker remained open"
    )
    .expect("Failed to register circuit breaker open duration metric")
});

#[cfg(feature = "metrics")]
static TIMEOUT_OPERATIONS: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "resilience_timeout_operations_total",
        "Total number of timeout operations",
        &["result"]
    )
    .expect("Failed to register timeout operations metric")
});

#[cfg(feature = "metrics")]
static RETRY_ATTEMPTS: Lazy<HistogramVec> = Lazy::new(|| {
    register_histogram_vec!(
        "resilience_retry_attempts",
        "Number of retry attempts before success or failure",
        &["result"]
    )
    .expect("Failed to register retry attempts metric")
});

/// Metrics collector for circuit breaker
#[cfg(feature = "metrics")]
pub struct CircuitBreakerMetrics;

#[cfg(feature = "metrics")]
impl CircuitBreakerMetrics {
    pub fn record_state_transition(from: &str, to: &str) {
        CIRCUIT_BREAKER_STATE_TRANSITIONS
            .with_label_values(&[from, to])
            .inc();
    }

    pub fn record_call(state: &str, result: &str) {
        CIRCUIT_BREAKER_CALLS
            .with_label_values(&[state, result])
            .inc();
    }

    pub fn record_open_duration(duration_secs: f64) {
        CIRCUIT_BREAKER_OPEN_DURATION.observe(duration_secs);
    }
}

/// Metrics collector for timeouts
#[cfg(feature = "metrics")]
pub struct TimeoutMetrics;

#[cfg(feature = "metrics")]
impl TimeoutMetrics {
    pub fn record_operation(result: &str) {
        TIMEOUT_OPERATIONS.with_label_values(&[result]).inc();
    }
}

/// Metrics collector for retries
#[cfg(feature = "metrics")]
pub struct RetryMetrics;

#[cfg(feature = "metrics")]
impl RetryMetrics {
    pub fn record_attempts(result: &str, attempts: u32) {
        RETRY_ATTEMPTS
            .with_label_values(&[result])
            .observe(attempts as f64);
    }
}

// No-op implementations when metrics feature is disabled
#[cfg(not(feature = "metrics"))]
pub struct CircuitBreakerMetrics;

#[cfg(not(feature = "metrics"))]
impl CircuitBreakerMetrics {
    pub fn record_state_transition(_from: &str, _to: &str) {}
    pub fn record_call(_state: &str, _result: &str) {}
    pub fn record_open_duration(_duration_secs: f64) {}
}

#[cfg(not(feature = "metrics"))]
pub struct TimeoutMetrics;

#[cfg(not(feature = "metrics"))]
impl TimeoutMetrics {
    pub fn record_operation(_result: &str) {}
}

#[cfg(not(feature = "metrics"))]
pub struct RetryMetrics;

#[cfg(not(feature = "metrics"))]
impl RetryMetrics {
    pub fn record_attempts(_result: &str, _attempts: u32) {}
}
