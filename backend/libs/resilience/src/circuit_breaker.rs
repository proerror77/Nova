/// Circuit Breaker implementation with sliding window error rate tracking
///
/// State transitions:
/// - Closed → Open: when error rate exceeds threshold or consecutive failures reach limit
/// - Open → HalfOpen: after timeout duration
/// - HalfOpen → Closed: when success count reaches threshold
/// - HalfOpen → Open: on any failure
use parking_lot::RwLock;
use std::collections::VecDeque;
use std::future::Future;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tracing::{info, warn};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitState {
    /// Normal operation, requests pass through
    Closed,
    /// Circuit is open, requests fail fast
    Open,
    /// Testing if service recovered, limited requests allowed
    HalfOpen,
}

#[derive(Debug, Clone)]
pub struct CircuitBreakerConfig {
    /// Consecutive failure count to trigger circuit open
    pub failure_threshold: u32,
    /// Success count in HalfOpen to close circuit
    pub success_threshold: u32,
    /// Duration to wait before transitioning from Open to HalfOpen
    pub timeout: Duration,
    /// Error rate threshold (0.0 - 1.0) to trigger circuit open
    pub error_rate_threshold: f64,
    /// Sliding window size for error rate calculation
    pub window_size: usize,
}

impl Default for CircuitBreakerConfig {
    fn default() -> Self {
        Self {
            failure_threshold: 5,
            success_threshold: 2,
            timeout: Duration::from_secs(60),
            error_rate_threshold: 0.5, // 50%
            window_size: 100,
        }
    }
}

#[derive(Clone)]
pub struct CircuitBreaker {
    config: CircuitBreakerConfig,
    state: Arc<RwLock<CircuitBreakerState>>,
}

struct CircuitBreakerState {
    current: CircuitState,
    consecutive_failures: u32,
    consecutive_successes: u32,
    opened_at: Option<Instant>,
    /// Sliding window: true = success, false = failure
    window: VecDeque<bool>,
}

#[derive(Debug, thiserror::Error)]
pub enum CircuitBreakerError {
    #[error("Circuit breaker is open - failing fast")]
    Open,
    #[error("Call failed: {0}")]
    CallFailed(String),
}

impl CircuitBreaker {
    pub fn new(config: CircuitBreakerConfig) -> Self {
        Self {
            state: Arc::new(RwLock::new(CircuitBreakerState {
                current: CircuitState::Closed,
                consecutive_failures: 0,
                consecutive_successes: 0,
                opened_at: None,
                window: VecDeque::with_capacity(config.window_size),
            })),
            config,
        }
    }

    /// Execute a future with circuit breaker protection
    pub async fn call<F, Fut, T, E>(&self, f: F) -> Result<T, CircuitBreakerError>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<T, E>>,
        E: std::fmt::Display,
    {
        // Fast path: check if circuit is open
        if self.should_reject_call() {
            return Err(CircuitBreakerError::Open);
        }

        // Execute the call
        match f().await {
            Ok(result) => {
                self.record_success();
                Ok(result)
            }
            Err(e) => {
                self.record_failure();
                Err(CircuitBreakerError::CallFailed(e.to_string()))
            }
        }
    }

    fn should_reject_call(&self) -> bool {
        let mut state = self.state.write();

        match state.current {
            CircuitState::Open => {
                // Check if timeout elapsed, transition to HalfOpen
                if let Some(opened_at) = state.opened_at {
                    if opened_at.elapsed() >= self.config.timeout {
                        info!("Circuit breaker: Open → HalfOpen");
                        state.current = CircuitState::HalfOpen;
                        state.consecutive_successes = 0;
                        state.consecutive_failures = 0;
                        false
                    } else {
                        true // Still open, reject
                    }
                } else {
                    true
                }
            }
            CircuitState::HalfOpen | CircuitState::Closed => false,
        }
    }

    fn record_success(&self) {
        let mut state = self.state.write();

        state.consecutive_successes += 1;
        state.consecutive_failures = 0;
        self.add_to_window(&mut state, true);

        if state.current == CircuitState::HalfOpen {
            if state.consecutive_successes >= self.config.success_threshold {
                info!("Circuit breaker: HalfOpen → Closed");
                state.current = CircuitState::Closed;
            }
        }
    }

    fn record_failure(&self) {
        let mut state = self.state.write();

        state.consecutive_failures += 1;
        state.consecutive_successes = 0;
        self.add_to_window(&mut state, false);

        match state.current {
            CircuitState::Closed => {
                let error_rate = self.calculate_error_rate(&state);

                if state.consecutive_failures >= self.config.failure_threshold
                    || error_rate >= self.config.error_rate_threshold
                {
                    warn!(
                        "Circuit breaker: Closed → Open (failures: {}, error_rate: {:.2}%)",
                        state.consecutive_failures,
                        error_rate * 100.0
                    );
                    state.current = CircuitState::Open;
                    state.opened_at = Some(Instant::now());
                }
            }
            CircuitState::HalfOpen => {
                warn!("Circuit breaker: HalfOpen → Open (test failed)");
                state.current = CircuitState::Open;
                state.opened_at = Some(Instant::now());
            }
            CircuitState::Open => {
                // Already open, nothing to do
            }
        }
    }

    fn add_to_window(&self, state: &mut CircuitBreakerState, success: bool) {
        if state.window.len() >= self.config.window_size {
            state.window.pop_front();
        }
        state.window.push_back(success);
    }

    fn calculate_error_rate(&self, state: &CircuitBreakerState) -> f64 {
        if state.window.is_empty() {
            return 0.0;
        }

        let failures = state.window.iter().filter(|&&x| !x).count();
        failures as f64 / state.window.len() as f64
    }

    /// Get current circuit state (for monitoring)
    pub fn state(&self) -> CircuitState {
        self.state.read().current
    }

    /// Get current error rate (for monitoring)
    pub fn error_rate(&self) -> f64 {
        let state = self.state.read();
        self.calculate_error_rate(&state)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_circuit_closed_to_open_on_consecutive_failures() {
        let config = CircuitBreakerConfig {
            failure_threshold: 3,
            ..Default::default()
        };
        let cb = CircuitBreaker::new(config);

        // Trigger 3 consecutive failures
        for _ in 0..3 {
            let _ = cb
                .call(|| async { Err::<(), _>("error") })
                .await;
        }

        // Circuit should be open
        assert_eq!(cb.state(), CircuitState::Open);

        // Next call should fail fast
        let result = cb.call(|| async { Ok::<_, String>(()) }).await;
        assert!(matches!(result, Err(CircuitBreakerError::Open)));
    }

    #[tokio::test]
    async fn test_circuit_open_to_halfopen_after_timeout() {
        let config = CircuitBreakerConfig {
            failure_threshold: 2,
            timeout: Duration::from_millis(100),
            ..Default::default()
        };
        let cb = CircuitBreaker::new(config);

        // Open the circuit
        for _ in 0..2 {
            let _ = cb.call(|| async { Err::<(), _>("error") }).await;
        }

        assert_eq!(cb.state(), CircuitState::Open);

        // Wait for timeout
        tokio::time::sleep(Duration::from_millis(150)).await;

        // Next call should transition to HalfOpen
        let _ = cb.call(|| async { Ok::<_, String>(()) }).await;
        assert_eq!(cb.state(), CircuitState::HalfOpen);
    }

    #[tokio::test]
    async fn test_circuit_halfopen_to_closed_on_success() {
        let config = CircuitBreakerConfig {
            failure_threshold: 2,
            success_threshold: 2,
            timeout: Duration::from_millis(100),
            ..Default::default()
        };
        let cb = CircuitBreaker::new(config);

        // Open the circuit
        for _ in 0..2 {
            let _ = cb.call(|| async { Err::<(), _>("error") }).await;
        }

        // Wait and transition to HalfOpen
        tokio::time::sleep(Duration::from_millis(150)).await;

        // 2 successful calls should close the circuit
        for _ in 0..2 {
            let _ = cb.call(|| async { Ok::<_, String>(()) }).await;
        }

        assert_eq!(cb.state(), CircuitState::Closed);
    }

    #[tokio::test]
    async fn test_circuit_halfopen_to_open_on_failure() {
        let config = CircuitBreakerConfig {
            failure_threshold: 2,
            timeout: Duration::from_millis(100),
            ..Default::default()
        };
        let cb = CircuitBreaker::new(config);

        // Open the circuit
        for _ in 0..2 {
            let _ = cb.call(|| async { Err::<(), _>("error") }).await;
        }

        // Wait and transition to HalfOpen
        tokio::time::sleep(Duration::from_millis(150)).await;
        let _ = cb.call(|| async { Ok::<_, String>(()) }).await;

        // A failure in HalfOpen should reopen the circuit
        let _ = cb.call(|| async { Err::<(), _>("error") }).await;
        assert_eq!(cb.state(), CircuitState::Open);
    }

    #[tokio::test]
    async fn test_error_rate_threshold() {
        let config = CircuitBreakerConfig {
            failure_threshold: 100, // High threshold to test error rate only
            error_rate_threshold: 0.5, // 50%
            window_size: 10,
            ..Default::default()
        };
        let cb = CircuitBreaker::new(config);

        // 6 failures out of 10 calls = 60% error rate
        for _ in 0..6 {
            let _ = cb.call(|| async { Err::<(), _>("error") }).await;
        }
        for _ in 0..4 {
            let _ = cb.call(|| async { Ok::<_, String>(()) }).await;
        }

        // Circuit should be open due to error rate
        assert_eq!(cb.state(), CircuitState::Open);
    }
}
