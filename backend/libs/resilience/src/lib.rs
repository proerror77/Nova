/// Resilience patterns for microservices
/// Based on Codex P0 recommendations for timeouts and circuit breaking
///
/// This module provides:
/// - Configurable timeouts for all external calls
/// - Circuit breaker pattern implementation
/// - Retry logic with exponential backoff
/// - Request budgeting and load shedding

use anyhow::{Context, Result};
use std::future::Future;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::timeout;
use tower::limit::ConcurrencyLimit;
use tower::timeout::Timeout;
use tower::{Service, ServiceBuilder, ServiceExt};

/// Default timeout configurations per Codex recommendations
pub struct TimeoutConfig {
    /// Database query timeout (Codex: 10-30s)
    pub database: Duration,
    /// gRPC call timeout (Codex: 10s)
    pub grpc: Duration,
    /// HTTP external call timeout
    pub http: Duration,
    /// Redis operation timeout (Codex: 5s)
    pub cache: Duration,
    /// Kafka produce timeout
    pub kafka: Duration,
}

impl Default for TimeoutConfig {
    fn default() -> Self {
        Self {
            database: Duration::from_secs(10),
            grpc: Duration::from_secs(10),
            http: Duration::from_secs(30),
            cache: Duration::from_secs(5),
            kafka: Duration::from_secs(5),
        }
    }
}

/// Execute a future with timeout
pub async fn with_timeout<F, T>(
    duration: Duration,
    operation_name: &str,
    future: F,
) -> Result<T>
where
    F: Future<Output = Result<T>>,
{
    timeout(duration, future)
        .await
        .with_context(|| format!("{} timed out after {:?}", operation_name, duration))?
        .with_context(|| format!("{} failed", operation_name))
}

/// Database operations with timeout
pub async fn with_db_timeout<F, T>(future: F) -> Result<T>
where
    F: Future<Output = Result<T>>,
{
    with_timeout(
        TimeoutConfig::default().database,
        "Database operation",
        future,
    )
    .await
}

/// gRPC calls with timeout
pub async fn with_grpc_timeout<F, T>(future: F) -> Result<T>
where
    F: Future<Output = Result<T>>,
{
    with_timeout(TimeoutConfig::default().grpc, "gRPC call", future).await
}

/// Cache operations with timeout
pub async fn with_cache_timeout<F, T>(future: F) -> Result<T>
where
    F: Future<Output = Result<T>>,
{
    with_timeout(TimeoutConfig::default().cache, "Cache operation", future).await
}

/// Circuit breaker implementation
pub struct CircuitBreaker {
    failure_threshold: u32,
    success_threshold: u32,
    timeout: Duration,
    half_open_max_calls: u32,
    state: Arc<tokio::sync::RwLock<CircuitState>>,
}

#[derive(Debug, Clone)]
enum CircuitState {
    Closed {
        failure_count: u32,
    },
    Open {
        opened_at: std::time::Instant,
    },
    HalfOpen {
        success_count: u32,
        failure_count: u32,
        calls_count: u32,
    },
}

impl CircuitBreaker {
    pub fn new(failure_threshold: u32, success_threshold: u32, timeout: Duration) -> Self {
        Self {
            failure_threshold,
            success_threshold,
            timeout,
            half_open_max_calls: 3,
            state: Arc::new(tokio::sync::RwLock::new(CircuitState::Closed {
                failure_count: 0,
            })),
        }
    }

    pub async fn call<F, T>(&self, f: F) -> Result<T>
    where
        F: Future<Output = Result<T>>,
    {
        // Check circuit state
        let mut state = self.state.write().await;

        match &*state {
            CircuitState::Open { opened_at } => {
                if opened_at.elapsed() < self.timeout {
                    return Err(anyhow::anyhow!("Circuit breaker is open"));
                }
                // Transition to half-open
                *state = CircuitState::HalfOpen {
                    success_count: 0,
                    failure_count: 0,
                    calls_count: 0,
                };
            }
            CircuitState::HalfOpen { calls_count, .. } => {
                if *calls_count >= self.half_open_max_calls {
                    return Err(anyhow::anyhow!("Circuit breaker is half-open, max calls reached"));
                }
            }
            _ => {}
        }
        drop(state);

        // Execute the function
        let result = f.await;

        // Update state based on result
        let mut state = self.state.write().await;
        match &result {
            Ok(_) => self.on_success(&mut state),
            Err(_) => self.on_failure(&mut state),
        }

        result
    }

    fn on_success(&self, state: &mut CircuitState) {
        match state {
            CircuitState::Closed { failure_count } => {
                *failure_count = 0;
            }
            CircuitState::HalfOpen {
                success_count,
                calls_count,
                ..
            } => {
                *success_count += 1;
                *calls_count += 1;

                if *success_count >= self.success_threshold {
                    *state = CircuitState::Closed { failure_count: 0 };
                }
            }
            _ => {}
        }
    }

    fn on_failure(&self, state: &mut CircuitState) {
        match state {
            CircuitState::Closed { failure_count } => {
                *failure_count += 1;

                if *failure_count >= self.failure_threshold {
                    *state = CircuitState::Open {
                        opened_at: std::time::Instant::now(),
                    };
                }
            }
            CircuitState::HalfOpen { .. } => {
                *state = CircuitState::Open {
                    opened_at: std::time::Instant::now(),
                };
            }
            _ => {}
        }
    }
}

/// Retry with exponential backoff
pub async fn retry_with_backoff<F, T, Fut>(
    mut f: F,
    max_retries: u32,
    initial_delay: Duration,
) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T>>,
{
    let mut delay = initial_delay;
    let mut last_error = None;

    for attempt in 0..=max_retries {
        match f().await {
            Ok(result) => return Ok(result),
            Err(e) => {
                last_error = Some(e);

                if attempt < max_retries {
                    tokio::time::sleep(delay).await;
                    delay *= 2; // Exponential backoff
                }
            }
        }
    }

    Err(last_error.unwrap())
        .context(format!("Failed after {} retries", max_retries))
}

/// Request budgeting to prevent fan-out explosion
pub struct RequestBudget {
    semaphore: Arc<tokio::sync::Semaphore>,
    max_concurrent: usize,
}

impl RequestBudget {
    pub fn new(max_concurrent: usize) -> Self {
        Self {
            semaphore: Arc::new(tokio::sync::Semaphore::new(max_concurrent)),
            max_concurrent,
        }
    }

    pub async fn execute<F, T>(&self, f: F) -> Result<T>
    where
        F: Future<Output = Result<T>>,
    {
        let _permit = self.semaphore.acquire().await
            .context("Failed to acquire request budget permit")?;

        f.await
    }
}

/// Load shedding when system is overloaded
pub struct LoadShedder {
    current_load: Arc<std::sync::atomic::AtomicU64>,
    max_load: u64,
}

impl LoadShedder {
    pub fn new(max_load: u64) -> Self {
        Self {
            current_load: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            max_load,
        }
    }

    pub async fn execute<F, T>(&self, f: F) -> Result<T>
    where
        F: Future<Output = Result<T>>,
    {
        use std::sync::atomic::Ordering;

        let current = self.current_load.fetch_add(1, Ordering::SeqCst);

        if current >= self.max_load {
            self.current_load.fetch_sub(1, Ordering::SeqCst);
            return Err(anyhow::anyhow!("System overloaded, shedding load"));
        }

        let result = f.await;
        self.current_load.fetch_sub(1, Ordering::SeqCst);
        result
    }
}

/// Create a resilient service stack with all protections
pub fn build_resilient_service<S>(service: S) -> impl Service<(), Response = S::Response, Error = S::Error>
where
    S: Service<()> + Clone,
{
    ServiceBuilder::new()
        .timeout(Duration::from_secs(30))
        .concurrency_limit(100)
        .buffer(100)
        .service(service)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_timeout_succeeds() {
        let result = with_timeout(
            Duration::from_secs(1),
            "test",
            async { Ok::<_, anyhow::Error>(42) },
        )
        .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
    }

    #[tokio::test]
    async fn test_timeout_fails() {
        let result = with_timeout(
            Duration::from_millis(10),
            "test",
            async {
                tokio::time::sleep(Duration::from_secs(1)).await;
                Ok::<_, anyhow::Error>(42)
            },
        )
        .await;

        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_circuit_breaker() {
        let cb = CircuitBreaker::new(2, 2, Duration::from_secs(1));

        // First failure
        let _ = cb.call(async { Err(anyhow::anyhow!("error")) }).await;

        // Second failure - should open circuit
        let _ = cb.call(async { Err(anyhow::anyhow!("error")) }).await;

        // Third call should fail immediately (circuit open)
        let result = cb.call(async { Ok::<_, anyhow::Error>(42) }).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_retry_with_backoff() {
        let counter = std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0));
        let counter_clone = counter.clone();

        let result = retry_with_backoff(
            move || {
                let count = counter_clone.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                async move {
                    if count < 2 {
                        Err(anyhow::anyhow!("error"))
                    } else {
                        Ok(42)
                    }
                }
            },
            3,
            Duration::from_millis(10),
        )
        .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
        assert_eq!(counter.load(std::sync::atomic::Ordering::SeqCst), 3);
    }
}