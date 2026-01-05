/// Retry policy with exponential backoff and jitter
use rand::Rng;
use std::future::Future;
use std::time::Duration;
use tracing::warn;

#[derive(Debug, Clone)]
pub struct RetryConfig {
    /// Maximum number of retry attempts
    pub max_retries: u32,
    /// Initial backoff duration
    pub initial_backoff: Duration,
    /// Maximum backoff duration
    pub max_backoff: Duration,
    /// Backoff multiplier for exponential backoff
    pub backoff_multiplier: f64,
    /// Add random jitter to backoff (±30%)
    pub jitter: bool,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_retries: 3,
            initial_backoff: Duration::from_millis(100),
            max_backoff: Duration::from_secs(10),
            backoff_multiplier: 2.0,
            jitter: true,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum RetryError<E> {
    #[error("Max retries ({0}) exceeded")]
    MaxRetriesExceeded(u32),
    #[error("Operation failed: {0}")]
    OperationFailed(E),
}

/// Execute a future with retry logic
pub async fn with_retry<F, Fut, T, E>(config: RetryConfig, mut f: F) -> Result<T, RetryError<E>>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, E>>,
    E: std::fmt::Display,
{
    let mut attempt = 0;
    let mut backoff = config.initial_backoff;

    loop {
        match f().await {
            Ok(result) => return Ok(result),
            Err(_e) => {
                attempt += 1;

                if attempt > config.max_retries {
                    warn!("Max retries ({}) reached", config.max_retries);
                    return Err(RetryError::MaxRetriesExceeded(config.max_retries));
                }

                let delay = calculate_backoff(backoff, config.jitter);

                warn!(
                    "Retry attempt {}/{}, waiting {:?}",
                    attempt, config.max_retries, delay
                );

                tokio::time::sleep(delay).await;

                // Exponential backoff
                backoff = Duration::from_millis(
                    ((backoff.as_millis() as f64 * config.backoff_multiplier)
                        .min(config.max_backoff.as_millis() as f64)) as u64,
                );
            }
        }
    }
}

fn calculate_backoff(base: Duration, jitter: bool) -> Duration {
    if jitter {
        let mut rng = rand::rng();
        let jitter_factor = 1.0 + rng.gen_range(-0.3..0.3); // ±30%
        Duration::from_millis((base.as_millis() as f64 * jitter_factor) as u64)
    } else {
        base
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::sync::Arc;

    #[tokio::test]
    async fn test_retry_success_on_first_attempt() {
        let config = RetryConfig::default();
        let counter = Arc::new(AtomicU32::new(0));
        let counter_clone = counter.clone();

        let result = with_retry(config, move || {
            counter_clone.fetch_add(1, Ordering::SeqCst);
            async { Ok::<_, String>(42) }
        })
        .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
        assert_eq!(counter.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn test_retry_success_after_failures() {
        let config = RetryConfig {
            max_retries: 3,
            initial_backoff: Duration::from_millis(10),
            jitter: false,
            ..Default::default()
        };

        let counter = Arc::new(AtomicU32::new(0));
        let counter_clone = counter.clone();

        let result = with_retry(config, move || {
            let count = counter_clone.fetch_add(1, Ordering::SeqCst);
            async move {
                if count < 2 {
                    Err("temporary error")
                } else {
                    Ok(42)
                }
            }
        })
        .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
        assert_eq!(counter.load(Ordering::SeqCst), 3);
    }

    #[tokio::test]
    async fn test_retry_max_retries_exceeded() {
        let config = RetryConfig {
            max_retries: 2,
            initial_backoff: Duration::from_millis(10),
            jitter: false,
            ..Default::default()
        };

        let counter = Arc::new(AtomicU32::new(0));
        let counter_clone = counter.clone();

        let result = with_retry(config, move || {
            counter_clone.fetch_add(1, Ordering::SeqCst);
            async { Err::<i32, _>("persistent error") }
        })
        .await;

        assert!(result.is_err());
        assert!(matches!(result, Err(RetryError::MaxRetriesExceeded(2))));
        assert_eq!(counter.load(Ordering::SeqCst), 3); // Initial + 2 retries
    }

    #[tokio::test]
    async fn test_exponential_backoff() {
        let config = RetryConfig {
            max_retries: 3,
            initial_backoff: Duration::from_millis(10),
            backoff_multiplier: 2.0,
            jitter: false,
            ..Default::default()
        };

        let start = std::time::Instant::now();

        let _ = with_retry(config, || async { Err::<i32, _>("error") }).await;

        let elapsed = start.elapsed();

        // Expected: 10ms + 20ms + 40ms = 70ms minimum
        assert!(elapsed >= Duration::from_millis(70));
    }
}
