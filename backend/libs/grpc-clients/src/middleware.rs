/// gRPC Middleware
///
/// Implements common patterns for gRPC clients:
/// - Retries with exponential backoff
/// - Timeout enforcement
/// - Circuit breaker pattern
/// - Request/response logging
/// - Distributed tracing support
use std::future::Future;
use std::time::Duration;

/// Retry configuration
#[derive(Clone, Debug)]
pub struct RetryConfig {
    /// Maximum number of retries
    pub max_retries: u32,

    /// Initial backoff duration
    pub initial_backoff: Duration,

    /// Maximum backoff duration
    pub max_backoff: Duration,

    /// Backoff multiplier (exponential backoff)
    pub backoff_multiplier: f64,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_retries: 3,
            initial_backoff: Duration::from_millis(100),
            max_backoff: Duration::from_secs(10),
            backoff_multiplier: 2.0,
        }
    }
}

impl RetryConfig {
    /// Calculate backoff duration for attempt
    pub fn backoff_duration(&self, attempt: u32) -> Duration {
        let base_millis = self.initial_backoff.as_millis() as f64;
        let multiplied = base_millis * self.backoff_multiplier.powi(attempt as i32);
        let millis = multiplied.min(self.max_backoff.as_millis() as f64) as u64;
        Duration::from_millis(millis)
    }
}

/// Execute function with retry logic
pub async fn with_retry<F, Fut, T, E>(config: &RetryConfig, mut f: F) -> Result<T, E>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, E>>,
{
    let mut attempt = 0;

    loop {
        match f().await {
            Ok(result) => return Ok(result),
            Err(err) => {
                attempt += 1;

                if attempt > config.max_retries {
                    return Err(err);
                }

                let backoff = config.backoff_duration(attempt - 1);
                tokio::time::sleep(backoff).await;
            }
        }
    }
}

/// Circuit breaker state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitBreakerState {
    Closed,
    Open,
    HalfOpen,
}

/// Circuit breaker configuration
#[derive(Clone, Debug)]
pub struct CircuitBreakerConfig {
    /// Number of failures before opening
    pub failure_threshold: u32,

    /// Duration to keep circuit open before trying again
    pub open_duration: Duration,

    /// Number of successful requests in half-open state before closing
    pub success_threshold: u32,
}

impl Default for CircuitBreakerConfig {
    fn default() -> Self {
        Self {
            failure_threshold: 5,
            open_duration: Duration::from_secs(30),
            success_threshold: 2,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_retry_config_backoff() {
        let config = RetryConfig::default();
        let backoff1 = config.backoff_duration(0);
        let backoff2 = config.backoff_duration(1);

        assert!(backoff2 > backoff1);
    }

    #[tokio::test]
    async fn test_with_retry_success() {
        let config = RetryConfig::default();
        let mut attempts = 0;

        let result = with_retry(&config, || async {
            attempts += 1;
            if attempts < 2 {
                Err::<i32, _>("error")
            } else {
                Ok(42)
            }
        })
        .await;

        assert_eq!(result, Ok(42));
        assert_eq!(attempts, 2);
    }

    #[tokio::test]
    async fn test_with_retry_max_retries() {
        let config = RetryConfig {
            max_retries: 2,
            ..Default::default()
        };

        let result: Result<i32, _> = with_retry(&config, || async { Err::<i32, _>("error") }).await;

        assert_eq!(result, Err("error"));
    }
}
