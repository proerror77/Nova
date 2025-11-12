use std::sync::Arc;
use std::time::{Duration, Instant};
use thiserror::Error;
use tokio::sync::RwLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitBreakerState {
    Closed,
    Open,
    HalfOpen,
}

#[derive(Debug, Clone)]
pub struct CircuitBreakerConfig {
    pub failure_threshold: u32,
    pub success_threshold: u32,
    pub timeout: Duration,
}

impl Default for CircuitBreakerConfig {
    fn default() -> Self {
        Self {
            failure_threshold: 3,
            success_threshold: 3,
            timeout: Duration::from_secs(30),
        }
    }
}

#[derive(Debug, Error)]
pub enum CircuitBreakerError {
    #[error("Circuit breaker is open")]
    Open,
    #[error("Operation failed: {0}")]
    OperationFailed(String),
}

struct CircuitBreakerInner {
    state: CircuitBreakerState,
    failure_count: u32,
    success_count: u32,
    last_failure_time: Option<Instant>,
    config: CircuitBreakerConfig,
}

pub struct CircuitBreaker {
    inner: Arc<RwLock<CircuitBreakerInner>>,
}

impl CircuitBreaker {
    pub fn new(config: CircuitBreakerConfig) -> Self {
        Self {
            inner: Arc::new(RwLock::new(CircuitBreakerInner {
                state: CircuitBreakerState::Closed,
                failure_count: 0,
                success_count: 0,
                last_failure_time: None,
                config,
            })),
        }
    }

    pub async fn call<F, Fut, T, E>(&self, f: F) -> Result<T, CircuitBreakerError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<T, E>>,
        E: std::fmt::Display,
    {
        // Check state
        {
            let inner = self.inner.read().await;
            if inner.state == CircuitBreakerState::Open {
                // Check if timeout has passed
                if let Some(last_failure) = inner.last_failure_time {
                    if last_failure.elapsed() < inner.config.timeout {
                        return Err(CircuitBreakerError::Open);
                    }
                }
            }
        }

        // Transition to HalfOpen if timeout passed
        {
            let mut inner = self.inner.write().await;
            if inner.state == CircuitBreakerState::Open {
                if let Some(last_failure) = inner.last_failure_time {
                    if last_failure.elapsed() >= inner.config.timeout {
                        inner.state = CircuitBreakerState::HalfOpen;
                        inner.success_count = 0;
                        tracing::info!("Circuit breaker transitioning to HalfOpen");
                    }
                }
            }
        }

        // Execute operation
        match f().await {
            Ok(result) => {
                self.on_success().await;
                Ok(result)
            }
            Err(e) => {
                self.on_failure().await;
                Err(CircuitBreakerError::OperationFailed(e.to_string()))
            }
        }
    }

    async fn on_success(&self) {
        let mut inner = self.inner.write().await;
        match inner.state {
            CircuitBreakerState::HalfOpen => {
                inner.success_count += 1;
                if inner.success_count >= inner.config.success_threshold {
                    inner.state = CircuitBreakerState::Closed;
                    inner.failure_count = 0;
                    inner.success_count = 0;
                    tracing::info!("Circuit breaker closed");
                }
            }
            CircuitBreakerState::Closed => {
                inner.failure_count = 0;
            }
            _ => {}
        }
    }

    async fn on_failure(&self) {
        let mut inner = self.inner.write().await;
        match inner.state {
            CircuitBreakerState::Closed => {
                inner.failure_count += 1;
                if inner.failure_count >= inner.config.failure_threshold {
                    inner.state = CircuitBreakerState::Open;
                    inner.last_failure_time = Some(Instant::now());
                    tracing::warn!("Circuit breaker opened");
                }
            }
            CircuitBreakerState::HalfOpen => {
                inner.state = CircuitBreakerState::Open;
                inner.last_failure_time = Some(Instant::now());
                inner.success_count = 0;
                tracing::warn!("Circuit breaker reopened from HalfOpen");
            }
            _ => {}
        }
    }

    pub async fn state(&self) -> CircuitBreakerState {
        self.inner.read().await.state
    }
}
