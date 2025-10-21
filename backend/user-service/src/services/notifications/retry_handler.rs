/// Retry handler for push notification failures
///
/// Implements exponential backoff retry strategy with dead-letter queue
use std::time::Duration;
use tokio::time::sleep;

/// Retry policy configuration
#[derive(Debug, Clone)]
pub struct RetryConfig {
    /// Initial delay between retries (default: 100ms)
    pub initial_delay: Duration,
    /// Maximum delay between retries (default: 5s)
    pub max_delay: Duration,
    /// Maximum number of retry attempts (default: 3)
    pub max_attempts: usize,
    /// Backoff multiplier (default: 2.0 for exponential)
    pub backoff_multiplier: f64,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            initial_delay: Duration::from_millis(100),
            max_delay: Duration::from_secs(5),
            max_attempts: 3,
            backoff_multiplier: 2.0,
        }
    }
}

impl RetryConfig {
    /// Calculate delay for a given attempt number
    pub fn calculate_delay(&self, attempt: usize) -> Duration {
        if attempt == 0 {
            return Duration::from_millis(0);
        }

        let delay_ms = (self.initial_delay.as_millis() as f64)
            * self.backoff_multiplier.powi((attempt - 1) as i32);

        let delay = Duration::from_millis(delay_ms as u64);

        // Cap at max delay
        if delay > self.max_delay {
            self.max_delay
        } else {
            delay
        }
    }
}

/// Retry handler for async operations
pub struct RetryHandler {
    config: RetryConfig,
}

impl RetryHandler {
    /// Create new retry handler with config
    pub fn new(config: RetryConfig) -> Self {
        Self { config }
    }

    /// Create retry handler with default config
    pub fn default() -> Self {
        Self::new(RetryConfig::default())
    }

    /// Execute operation with retry logic
    ///
    /// Returns Ok(result) on success, or Err(last_error) if all retries exhausted
    pub async fn execute<F, Fut, T, E>(&self, operation: F) -> Result<T, E>
    where
        F: Fn() -> Fut,
        Fut: std::future::Future<Output = Result<T, E>>,
    {
        let mut last_error = None;

        for attempt in 0..self.config.max_attempts {
            // Execute operation
            match operation().await {
                Ok(result) => return Ok(result),
                Err(e) => {
                    last_error = Some(e);

                    // Don't delay after last attempt
                    if attempt < self.config.max_attempts - 1 {
                        let delay = self.config.calculate_delay(attempt + 1);
                        sleep(delay).await;
                    }
                }
            }
        }

        // All retries exhausted
        Err(last_error.unwrap())
    }

    /// Check if error is retryable
    pub fn is_retryable(error: &str) -> bool {
        // Retryable errors: timeouts, rate limits, temporary server errors
        error.contains("timeout")
            || error.contains("429") // Rate limit
            || error.contains("500") // Internal server error
            || error.contains("502") // Bad gateway
            || error.contains("503") // Service unavailable
            || error.contains("504") // Gateway timeout
            || error.contains("connection")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_retry_config_default() {
        let config = RetryConfig::default();
        assert_eq!(config.initial_delay, Duration::from_millis(100));
        assert_eq!(config.max_delay, Duration::from_secs(5));
        assert_eq!(config.max_attempts, 3);
        assert_eq!(config.backoff_multiplier, 2.0);
    }

    #[test]
    fn test_calculate_delay_exponential() {
        let config = RetryConfig::default();

        // First retry: 100ms
        assert_eq!(config.calculate_delay(1), Duration::from_millis(100));

        // Second retry: 200ms
        assert_eq!(config.calculate_delay(2), Duration::from_millis(200));

        // Third retry: 400ms
        assert_eq!(config.calculate_delay(3), Duration::from_millis(400));
    }

    #[test]
    fn test_calculate_delay_caps_at_max() {
        let config = RetryConfig {
            initial_delay: Duration::from_secs(1),
            max_delay: Duration::from_secs(5),
            max_attempts: 10,
            backoff_multiplier: 2.0,
        };

        // After enough retries, should cap at max_delay
        let delay = config.calculate_delay(10);
        assert_eq!(delay, Duration::from_secs(5));
    }

    #[test]
    fn test_is_retryable_timeout() {
        assert!(RetryHandler::is_retryable("connection timeout"));
        assert!(RetryHandler::is_retryable("request timeout"));
    }

    #[test]
    fn test_is_retryable_rate_limit() {
        assert!(RetryHandler::is_retryable("429 Too Many Requests"));
    }

    #[test]
    fn test_is_retryable_server_errors() {
        assert!(RetryHandler::is_retryable("500 Internal Server Error"));
        assert!(RetryHandler::is_retryable("502 Bad Gateway"));
        assert!(RetryHandler::is_retryable("503 Service Unavailable"));
        assert!(RetryHandler::is_retryable("504 Gateway Timeout"));
    }

    #[test]
    fn test_not_retryable() {
        assert!(!RetryHandler::is_retryable("400 Bad Request"));
        assert!(!RetryHandler::is_retryable("401 Unauthorized"));
        assert!(!RetryHandler::is_retryable("404 Not Found"));
    }

    #[tokio::test]
    async fn test_retry_succeeds_first_attempt() {
        let handler = RetryHandler::default();
        let call_count = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let count_clone = call_count.clone();

        let result = handler
            .execute(move || {
                let count = count_clone.clone();
                async move {
                    count.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                    Ok::<i32, String>(42)
                }
            })
            .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
        assert_eq!(call_count.load(std::sync::atomic::Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn test_retry_succeeds_after_failures() {
        let handler = RetryHandler::default();
        let call_count = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let count_clone = call_count.clone();

        let result = handler
            .execute(move || {
                let count = count_clone.clone();
                async move {
                    let current = count.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
                    if current < 3 {
                        Err("temporary error".to_string())
                    } else {
                        Ok(42)
                    }
                }
            })
            .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
        assert_eq!(call_count.load(std::sync::atomic::Ordering::SeqCst), 3);
    }

    #[tokio::test]
    async fn test_retry_exhausts_attempts() {
        let handler = RetryHandler::default();
        let call_count = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let count_clone = call_count.clone();

        let result = handler
            .execute(move || {
                let count = count_clone.clone();
                async move {
                    count.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                    Err::<i32, String>("permanent error".to_string())
                }
            })
            .await;

        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "permanent error");
        assert_eq!(call_count.load(std::sync::atomic::Ordering::SeqCst), 3); // max_attempts
    }
}
