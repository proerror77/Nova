/// Circuit Breaker pattern implementation for fault tolerance
///
/// Prevents cascading failures by tracking errors and opening the circuit
/// when error threshold is exceeded.
use chrono::{DateTime, Duration, Utc};
use std::future::Future;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{debug, error, warn};

use crate::error::{AppError, Result};

/// Circuit breaker states
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitState {
    /// Circuit is closed - requests pass through normally
    Closed,
    /// Circuit is open - requests fail fast without calling downstream
    Open,
    /// Circuit is half-open - testing if downstream has recovered
    HalfOpen,
}

/// Circuit breaker configuration
#[derive(Debug, Clone)]
pub struct CircuitBreakerConfig {
    /// Number of failures before opening circuit
    pub failure_threshold: usize,
    /// Number of successes to close circuit from half-open
    pub success_threshold: usize,
    /// Time to wait before attempting half-open (seconds)
    pub timeout_seconds: i64,
}

impl Default for CircuitBreakerConfig {
    fn default() -> Self {
        Self {
            failure_threshold: 3,
            success_threshold: 3,
            timeout_seconds: 30,
        }
    }
}

/// Circuit breaker state tracking
#[derive(Debug)]
struct CircuitBreakerState {
    state: CircuitState,
    failure_count: usize,
    success_count: usize,
    last_failure_time: Option<DateTime<Utc>>,
    last_state_change: DateTime<Utc>,
}

impl Default for CircuitBreakerState {
    fn default() -> Self {
        Self {
            state: CircuitState::Closed,
            failure_count: 0,
            success_count: 0,
            last_failure_time: None,
            last_state_change: Utc::now(),
        }
    }
}

/// Circuit Breaker for protecting downstream services
///
/// # Example
/// ```ignore
/// let breaker = CircuitBreaker::new(CircuitBreakerConfig::default());
///
/// // Call protected function
/// let result = breaker.call(|| async {
///     // Your risky operation here
///     Ok::<_, AppError>(42)
/// }).await?;
/// ```
#[derive(Clone)]
pub struct CircuitBreaker {
    state: Arc<Mutex<CircuitBreakerState>>,
    config: CircuitBreakerConfig,
}

impl CircuitBreaker {
    /// Create a new circuit breaker with given configuration
    pub fn new(config: CircuitBreakerConfig) -> Self {
        debug!(
            "Circuit breaker created: failure_threshold={}, success_threshold={}, timeout={}s",
            config.failure_threshold, config.success_threshold, config.timeout_seconds
        );

        Self {
            state: Arc::new(Mutex::new(CircuitBreakerState::default())),
            config,
        }
    }

    /// Create with default configuration
    pub fn default() -> Self {
        Self::new(CircuitBreakerConfig::default())
    }

    /// Get current circuit state
    pub async fn get_state(&self) -> CircuitState {
        let state = self.state.lock().await;
        state.state
    }

    /// Check and update circuit state before calling downstream
    async fn check_state(&self) -> Result<()> {
        let mut state = self.state.lock().await;

        match state.state {
            CircuitState::Closed => {
                // Circuit is closed - allow request
                Ok(())
            }
            CircuitState::Open => {
                // Check if timeout has elapsed
                if let Some(last_failure) = state.last_failure_time {
                    let elapsed = Utc::now().signed_duration_since(last_failure);
                    let timeout = Duration::seconds(self.config.timeout_seconds);

                    if elapsed >= timeout {
                        // Transition to half-open
                        debug!(
                            "Circuit breaker transitioning to HALF_OPEN after {:?}",
                            elapsed
                        );
                        state.state = CircuitState::HalfOpen;
                        state.success_count = 0;
                        state.last_state_change = Utc::now();
                        Ok(())
                    } else {
                        // Still in timeout - fail fast
                        warn!(
                            "Circuit breaker OPEN - failing fast ({:?} since last failure)",
                            elapsed
                        );
                        Err(AppError::Internal(
                            "Circuit breaker is OPEN - service temporarily unavailable".to_string(),
                        ))
                    }
                } else {
                    // No last_failure_time but state is Open - should not happen
                    error!("Circuit breaker in inconsistent state: OPEN but no last_failure_time");
                    Err(AppError::Internal(
                        "Circuit breaker is OPEN - service temporarily unavailable".to_string(),
                    ))
                }
            }
            CircuitState::HalfOpen => {
                // Allow limited requests to test recovery
                Ok(())
            }
        }
    }

    /// Record successful downstream call
    async fn record_success(&self) {
        let mut state = self.state.lock().await;

        match state.state {
            CircuitState::Closed => {
                // Reset failure count on success
                state.failure_count = 0;
            }
            CircuitState::HalfOpen => {
                state.success_count += 1;
                debug!(
                    "Circuit breaker HALF_OPEN success {}/{}",
                    state.success_count, self.config.success_threshold
                );

                if state.success_count >= self.config.success_threshold {
                    // Transition to closed
                    debug!("Circuit breaker transitioning to CLOSED");
                    state.state = CircuitState::Closed;
                    state.failure_count = 0;
                    state.success_count = 0;
                    state.last_state_change = Utc::now();
                }
            }
            CircuitState::Open => {
                // Should not happen - requests should be blocked
                warn!("Received success while circuit is OPEN - this should not happen");
            }
        }
    }

    /// Record failed downstream call
    async fn record_failure(&self) {
        let mut state = self.state.lock().await;

        state.failure_count += 1;
        state.last_failure_time = Some(Utc::now());

        match state.state {
            CircuitState::Closed => {
                debug!(
                    "Circuit breaker CLOSED failure {}/{}",
                    state.failure_count, self.config.failure_threshold
                );

                if state.failure_count >= self.config.failure_threshold {
                    // Transition to open
                    warn!(
                        "Circuit breaker transitioning to OPEN after {} failures",
                        state.failure_count
                    );
                    state.state = CircuitState::Open;
                    state.last_state_change = Utc::now();
                }
            }
            CircuitState::HalfOpen => {
                // Single failure in half-open immediately opens circuit
                warn!("Circuit breaker HALF_OPEN failure - reopening circuit");
                state.state = CircuitState::Open;
                state.success_count = 0;
                state.last_state_change = Utc::now();
            }
            CircuitState::Open => {
                // Already open - just update counts
                debug!("Circuit breaker OPEN - additional failure recorded");
            }
        }
    }

    /// Execute a function with circuit breaker protection
    ///
    /// # Arguments
    /// * `f` - Async function to execute
    ///
    /// # Returns
    /// * `Ok(T)` - Function succeeded
    /// * `Err(AppError::ServiceUnavailable)` - Circuit is open
    /// * `Err(AppError)` - Function failed
    pub async fn call<F, Fut, T>(&self, f: F) -> Result<T>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<T>>,
    {
        // Check state before calling
        self.check_state().await?;

        // Execute function
        match f().await {
            Ok(result) => {
                self.record_success().await;
                Ok(result)
            }
            Err(e) => {
                self.record_failure().await;
                Err(e)
            }
        }
    }

    /// Get circuit breaker statistics
    pub async fn get_stats(&self) -> CircuitBreakerStats {
        let state = self.state.lock().await;
        CircuitBreakerStats {
            state: state.state,
            failure_count: state.failure_count,
            success_count: state.success_count,
            last_failure_time: state.last_failure_time,
            last_state_change: state.last_state_change,
        }
    }

    /// Reset circuit breaker to closed state (for testing/manual intervention)
    pub async fn reset(&self) {
        let mut state = self.state.lock().await;
        *state = CircuitBreakerState::default();
        debug!("Circuit breaker manually reset to CLOSED");
    }
}

/// Circuit breaker statistics for monitoring
#[derive(Debug, Clone)]
pub struct CircuitBreakerStats {
    pub state: CircuitState,
    pub failure_count: usize,
    pub success_count: usize,
    pub last_failure_time: Option<DateTime<Utc>>,
    pub last_state_change: DateTime<Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn failing_operation() -> Result<()> {
        Err(AppError::Internal("Simulated failure".to_string()))
    }

    async fn successful_operation() -> Result<i32> {
        Ok(42)
    }

    #[tokio::test]
    async fn test_circuit_breaker_closed_state() {
        let cb = CircuitBreaker::new(CircuitBreakerConfig {
            failure_threshold: 3,
            success_threshold: 2,
            timeout_seconds: 1,
        });

        // Initial state should be Closed
        assert_eq!(cb.get_state().await, CircuitState::Closed);

        // Successful call should keep it closed
        let result = cb.call(|| successful_operation()).await;
        assert!(result.is_ok());
        assert_eq!(cb.get_state().await, CircuitState::Closed);
    }

    #[tokio::test]
    async fn test_circuit_breaker_opens_after_failures() {
        let cb = CircuitBreaker::new(CircuitBreakerConfig {
            failure_threshold: 3,
            success_threshold: 2,
            timeout_seconds: 1,
        });

        // 3 failures should open the circuit
        for _ in 0..3 {
            let _ = cb.call(|| failing_operation()).await;
        }

        assert_eq!(cb.get_state().await, CircuitState::Open);

        // Next call should fail fast without executing
        let result = cb.call(|| successful_operation()).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_circuit_breaker_half_open_transition() {
        let cb = CircuitBreaker::new(CircuitBreakerConfig {
            failure_threshold: 2,
            success_threshold: 2,
            timeout_seconds: 1,
        });

        // Open the circuit
        for _ in 0..2 {
            let _ = cb.call(|| failing_operation()).await;
        }

        assert_eq!(cb.get_state().await, CircuitState::Open);

        // Wait for timeout
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

        // Next call should transition to half-open
        let _ = cb.call(|| successful_operation()).await;
        let state = cb.get_state().await;
        assert!(state == CircuitState::HalfOpen || state == CircuitState::Closed);
    }

    #[tokio::test]
    async fn test_circuit_breaker_reset() {
        let cb = CircuitBreaker::new(CircuitBreakerConfig::default());

        // Open the circuit
        for _ in 0..3 {
            let _ = cb.call(|| failing_operation()).await;
        }

        assert_eq!(cb.get_state().await, CircuitState::Open);

        // Reset
        cb.reset().await;
        assert_eq!(cb.get_state().await, CircuitState::Closed);
    }
}
