//! Resilience patterns for gRPC clients
//!
//! Implements:
//! - Circuit Breaker pattern (prevent cascading failures)
//! - Retry with exponential backoff (transient error handling)
//! - Request timeout enforcement

use std::future::Future;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime};
use tokio::time::sleep;
use tonic::Status;
use tracing::{debug, warn};

/// Circuit Breaker states
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitState {
    /// Circuit is closed, requests flow normally
    Closed,
    /// Circuit is open, requests are blocked
    Open,
    /// Circuit is half-open, testing if service recovered
    HalfOpen,
}

/// Simple Circuit Breaker implementation
///
/// Prevents cascading failures by blocking requests to a failing service.
/// Uses failure threshold and recovery timeout to manage state transitions.
pub struct CircuitBreaker {
    /// Current circuit state
    state: std::sync::RwLock<CircuitState>,
    /// Failure count in current window
    failure_count: AtomicU32,
    /// Last failure timestamp (millis since epoch)
    last_failure_time: AtomicU64,
    /// Failure threshold before opening circuit
    failure_threshold: u32,
    /// Time to wait before half-open (seconds)
    timeout_secs: u64,
}

impl CircuitBreaker {
    /// Create a new circuit breaker
    ///
    /// # Arguments
    /// * `failure_threshold` - Number of failures before opening circuit
    /// * `timeout_secs` - Seconds to wait in open state before half-open
    pub fn new(failure_threshold: u32, timeout_secs: u64) -> Arc<Self> {
        Arc::new(Self {
            state: std::sync::RwLock::new(CircuitState::Closed),
            failure_count: AtomicU32::new(0),
            last_failure_time: AtomicU64::new(0),
            failure_threshold,
            timeout_secs,
        })
    }

    /// Get current circuit state (with auto-transition to half-open)
    pub fn state(&self) -> CircuitState {
        let state = *self.state.read()
            .expect("Circuit breaker lock poisoned - this should never happen in production");

        // Auto-transition from Open → HalfOpen after timeout
        if state == CircuitState::Open {
            let now = SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .expect("System time before UNIX_EPOCH - check system clock")
                .as_secs();
            let last_failure = self.last_failure_time.load(Ordering::Relaxed);

            if now - last_failure >= self.timeout_secs {
                debug!("Circuit breaker transitioning: Open → HalfOpen (timeout expired)");
                *self.state.write()
                    .expect("Circuit breaker lock poisoned - this should never happen in production") = CircuitState::HalfOpen;
                return CircuitState::HalfOpen;
            }
        }

        state
    }

    /// Check if circuit allows request
    pub fn allows_request(&self) -> bool {
        self.state() != CircuitState::Open
    }

    /// Record successful request
    pub fn record_success(&self) {
        let mut state = self.state.write()
            .expect("Circuit breaker lock poisoned - this should never happen in production");

        match *state {
            CircuitState::HalfOpen => {
                debug!("Circuit breaker transitioning: HalfOpen → Closed (success)");
                *state = CircuitState::Closed;
                self.failure_count.store(0, Ordering::Relaxed);
            }
            CircuitState::Closed => {
                // Reset failure count on success
                self.failure_count.store(0, Ordering::Relaxed);
            }
            CircuitState::Open => {
                // Should not happen (request blocked), but handle gracefully
            }
        }
    }

    /// Record failed request
    pub fn record_failure(&self) {
        let failures = self.failure_count.fetch_add(1, Ordering::Relaxed) + 1;
        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .expect("System time before UNIX_EPOCH - check system clock")
            .as_secs();
        self.last_failure_time.store(now, Ordering::Relaxed);

        let mut state = self.state.write()
            .expect("Circuit breaker lock poisoned - this should never happen in production");

        match *state {
            CircuitState::Closed => {
                if failures >= self.failure_threshold {
                    warn!(
                        "Circuit breaker transitioning: Closed → Open ({} failures)",
                        failures
                    );
                    *state = CircuitState::Open;
                }
            }
            CircuitState::HalfOpen => {
                warn!("Circuit breaker transitioning: HalfOpen → Open (failure during test)");
                *state = CircuitState::Open;
            }
            CircuitState::Open => {
                // Already open
            }
        }
    }
}

/// Retry policy configuration
#[derive(Debug, Clone, Copy)]
pub struct RetryPolicy {
    /// Maximum number of retry attempts
    pub max_retries: u32,
    /// Initial backoff duration
    pub initial_backoff: Duration,
    /// Maximum backoff duration
    pub max_backoff: Duration,
    /// Backoff multiplier (exponential growth)
    pub backoff_multiplier: f64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            max_retries: 3,
            initial_backoff: Duration::from_millis(100),
            max_backoff: Duration::from_secs(5),
            backoff_multiplier: 2.0,
        }
    }
}

impl RetryPolicy {
    /// Calculate backoff duration for attempt N
    fn backoff_for_attempt(&self, attempt: u32) -> Duration {
        let backoff_ms = self.initial_backoff.as_millis() as f64
            * self.backoff_multiplier.powi(attempt as i32);
        let backoff_ms = backoff_ms.min(self.max_backoff.as_millis() as f64);
        Duration::from_millis(backoff_ms as u64)
    }
}

/// Execute a gRPC call with retry logic and circuit breaker protection
///
/// # Arguments
/// * `circuit_breaker` - Circuit breaker to prevent cascading failures
/// * `policy` - Retry policy configuration
/// * `service_name` - Name of service for logging
/// * `operation` - Async function that performs the gRPC call
///
/// # Returns
/// Result from the gRPC call, or circuit breaker error
pub async fn execute_with_retry<F, Fut, T>(
    circuit_breaker: &CircuitBreaker,
    policy: &RetryPolicy,
    service_name: &str,
    mut operation: F,
) -> Result<T, Status>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, Status>>,
{
    // Check circuit breaker
    if !circuit_breaker.allows_request() {
        warn!("{} circuit is OPEN, blocking request", service_name);
        return Err(Status::unavailable(format!(
            "{} is currently unavailable (circuit open)",
            service_name
        )));
    }

    let mut attempt = 0;
    let mut last_error = None;

    loop {
        match operation().await {
            Ok(result) => {
                // Success - record and return
                circuit_breaker.record_success();
                if attempt > 0 {
                    debug!(
                        "{} request succeeded after {} retries",
                        service_name, attempt
                    );
                }
                return Ok(result);
            }
            Err(err) => {
                // Check if error is retryable
                let is_retryable = is_retryable_error(&err);

                if !is_retryable {
                    // Non-retryable error (e.g., InvalidArgument) - fail immediately
                    debug!("{} request failed with non-retryable error", service_name);
                    circuit_breaker.record_failure();
                    return Err(err);
                }

                // Retryable error
                attempt += 1;
                last_error = Some(err);

                if attempt >= policy.max_retries {
                    // Max retries exceeded
                    warn!(
                        "{} request failed after {} attempts",
                        service_name, attempt
                    );
                    circuit_breaker.record_failure();
                    return Err(last_error.expect("last_error must be Some after retry loop"));
                }

                // Calculate backoff and retry
                let backoff = policy.backoff_for_attempt(attempt - 1);
                debug!(
                    "{} request failed (attempt {}/{}), retrying after {:?}",
                    service_name, attempt, policy.max_retries, backoff
                );
                sleep(backoff).await;
            }
        }
    }
}

/// Determine if a gRPC error is retryable
///
/// Retryable errors:
/// - Unavailable (service down, temporary network issue)
/// - DeadlineExceeded (timeout)
/// - ResourceExhausted (rate limit, may recover)
///
/// Non-retryable errors:
/// - InvalidArgument (bad request data)
/// - NotFound (resource doesn't exist)
/// - AlreadyExists (duplicate creation)
/// - PermissionDenied (auth failure)
/// - Unauthenticated (invalid token)
fn is_retryable_error(err: &Status) -> bool {
    matches!(
        err.code(),
        tonic::Code::Unavailable
            | tonic::Code::DeadlineExceeded
            | tonic::Code::ResourceExhausted
            | tonic::Code::Unknown // Network errors often map to Unknown
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_circuit_breaker_closed_to_open() {
        let cb = CircuitBreaker::new(3, 5);

        assert_eq!(cb.state(), CircuitState::Closed);
        assert!(cb.allows_request());

        // Record 2 failures - should stay closed
        cb.record_failure();
        cb.record_failure();
        assert_eq!(cb.state(), CircuitState::Closed);

        // 3rd failure - should open
        cb.record_failure();
        assert_eq!(cb.state(), CircuitState::Open);
        assert!(!cb.allows_request());
    }

    #[tokio::test]
    async fn test_circuit_breaker_half_open_to_closed() {
        let cb = CircuitBreaker::new(2, 1);

        // Open circuit
        cb.record_failure();
        cb.record_failure();
        assert_eq!(cb.state(), CircuitState::Open);

        // Wait for timeout
        tokio::time::sleep(Duration::from_secs(2)).await;
        assert_eq!(cb.state(), CircuitState::HalfOpen);

        // Success - should close
        cb.record_success();
        assert_eq!(cb.state(), CircuitState::Closed);
    }

    #[tokio::test]
    async fn test_circuit_breaker_half_open_to_open() {
        let cb = CircuitBreaker::new(2, 1);

        // Open circuit
        cb.record_failure();
        cb.record_failure();

        // Wait for half-open
        tokio::time::sleep(Duration::from_secs(2)).await;
        assert_eq!(cb.state(), CircuitState::HalfOpen);

        // Failure - should re-open
        cb.record_failure();
        assert_eq!(cb.state(), CircuitState::Open);
    }

    #[test]
    fn test_retry_policy_backoff() {
        let policy = RetryPolicy::default();

        // Attempt 0: 100ms
        assert_eq!(policy.backoff_for_attempt(0), Duration::from_millis(100));

        // Attempt 1: 200ms
        assert_eq!(policy.backoff_for_attempt(1), Duration::from_millis(200));

        // Attempt 2: 400ms
        assert_eq!(policy.backoff_for_attempt(2), Duration::from_millis(400));

        // Attempt 10: capped at max_backoff (5s)
        assert_eq!(policy.backoff_for_attempt(10), Duration::from_secs(5));
    }

    #[tokio::test]
    async fn test_execute_with_retry_success() {
        let cb = CircuitBreaker::new(3, 5);
        let policy = RetryPolicy::default();

        let result = execute_with_retry(&cb, &policy, "test-service", || async {
            Ok::<_, Status>("success")
        })
        .await;

        assert!(result.is_ok());
        assert_eq!(cb.state(), CircuitState::Closed);
    }

    #[tokio::test]
    async fn test_execute_with_retry_transient_failure() {
        let cb = CircuitBreaker::new(5, 5);
        let policy = RetryPolicy {
            max_retries: 3,
            initial_backoff: Duration::from_millis(10),
            max_backoff: Duration::from_millis(50),
            backoff_multiplier: 2.0,
        };

        let mut attempt_count = 0;
        let result = execute_with_retry(&cb, &policy, "test-service", || {
            attempt_count += 1;
            async move {
                if attempt_count < 3 {
                    Err(Status::unavailable("temporary error"))
                } else {
                    Ok("success")
                }
            }
        })
        .await;

        assert!(result.is_ok());
        assert_eq!(attempt_count, 3);
    }

    #[tokio::test]
    async fn test_execute_with_retry_non_retryable() {
        let cb = CircuitBreaker::new(5, 5);
        let policy = RetryPolicy::default();

        let mut attempt_count = 0;
        let result = execute_with_retry(&cb, &policy, "test-service", || {
            attempt_count += 1;
            async move { Err::<String, _>(Status::invalid_argument("bad request")) }
        })
        .await;

        assert!(result.is_err());
        assert_eq!(attempt_count, 1); // Should not retry
    }

    #[tokio::test]
    async fn test_circuit_breaker_blocks_requests() {
        let cb = CircuitBreaker::new(1, 10);
        let policy = RetryPolicy::default();

        // Open circuit
        cb.record_failure();
        assert_eq!(cb.state(), CircuitState::Open);

        // Request should be blocked
        let result = execute_with_retry(&cb, &policy, "test-service", || async {
            Ok::<_, Status>("should not execute")
        })
        .await;

        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code(), tonic::Code::Unavailable);
    }
}
