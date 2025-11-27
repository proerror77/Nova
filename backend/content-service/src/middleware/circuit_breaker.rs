use chrono::{DateTime, Duration, Utc};
use std::future::Future;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{debug, error, warn};

use crate::error::{AppError, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitState {
    Closed,
    Open,
    HalfOpen,
}

#[derive(Debug, Clone)]
pub struct CircuitBreakerConfig {
    pub failure_threshold: usize,
    pub success_threshold: usize,
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

#[derive(Clone)]
pub struct CircuitBreaker {
    state: Arc<Mutex<CircuitBreakerState>>,
    config: CircuitBreakerConfig,
}

impl CircuitBreaker {
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

    pub async fn get_state(&self) -> CircuitState {
        let state = self.state.lock().await;
        state.state
    }

    async fn check_state(&self) -> Result<()> {
        let mut state = self.state.lock().await;

        match state.state {
            CircuitState::Closed => Ok(()),
            CircuitState::Open => {
                if let Some(last_failure) = state.last_failure_time {
                    let elapsed = Utc::now().signed_duration_since(last_failure);
                    let timeout = Duration::seconds(self.config.timeout_seconds);

                    if elapsed >= timeout {
                        debug!(
                            "Circuit breaker transitioning to HALF_OPEN after {:?}",
                            elapsed
                        );
                        state.state = CircuitState::HalfOpen;
                        state.success_count = 0;
                        state.last_state_change = Utc::now();
                        Ok(())
                    } else {
                        warn!(
                            "Circuit breaker OPEN - failing fast ({:?} since last failure)",
                            elapsed
                        );
                        Err(AppError::Internal(
                            "Circuit breaker is OPEN - service temporarily unavailable".to_string(),
                        ))
                    }
                } else {
                    error!("Circuit breaker OPEN but no last_failure_time recorded");
                    Err(AppError::Internal(
                        "Circuit breaker is OPEN - service temporarily unavailable".to_string(),
                    ))
                }
            }
            CircuitState::HalfOpen => Ok(()),
        }
    }

    async fn record_success(&self) {
        let mut state = self.state.lock().await;

        match state.state {
            CircuitState::Closed => {
                state.failure_count = 0;
            }
            CircuitState::HalfOpen => {
                state.success_count += 1;
                debug!(
                    "Circuit breaker HALF_OPEN success {}/{}",
                    state.success_count, self.config.success_threshold
                );

                if state.success_count >= self.config.success_threshold {
                    debug!("Circuit breaker transitioning to CLOSED");
                    state.state = CircuitState::Closed;
                    state.failure_count = 0;
                    state.success_count = 0;
                    state.last_state_change = Utc::now();
                }
            }
            CircuitState::Open => {
                warn!("Received success while circuit is OPEN - unexpected state");
            }
        }
    }

    async fn record_failure(&self) {
        let mut state = self.state.lock().await;

        state.failure_count += 1;
        state.last_failure_time = Some(Utc::now());

        match state.state {
            CircuitState::Closed => {
                if state.failure_count >= self.config.failure_threshold {
                    warn!(
                        "Circuit breaker transitioning to OPEN after {} failures",
                        state.failure_count
                    );
                    state.state = CircuitState::Open;
                    state.last_state_change = Utc::now();
                }
            }
            CircuitState::HalfOpen => {
                warn!("Circuit breaker HALF_OPEN failure - transitioning to OPEN");
                state.state = CircuitState::Open;
                state.failure_count = 0;
                state.success_count = 0;
                state.last_state_change = Utc::now();
            }
            CircuitState::Open => {}
        }
    }

    pub async fn call<F, Fut, T>(&self, operation: F) -> Result<T>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<T>>,
    {
        self.check_state().await?;

        match operation().await {
            Ok(result) => {
                self.record_success().await;
                Ok(result)
            }
            Err(err) => {
                self.record_failure().await;
                Err(err)
            }
        }
    }
}

impl Default for CircuitBreaker {
    fn default() -> Self {
        Self::new(CircuitBreakerConfig::default())
    }
}
