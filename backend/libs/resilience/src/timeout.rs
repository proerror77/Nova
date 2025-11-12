/// Timeout wrapper for async operations
use std::future::Future;
use std::time::Duration;
use tokio::time::timeout;

#[derive(Debug, Clone)]
pub struct TimeoutConfig {
    pub duration: Duration,
}

impl Default for TimeoutConfig {
    fn default() -> Self {
        Self {
            duration: Duration::from_secs(30),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum TimeoutError {
    #[error("Operation timed out after {0:?}")]
    Elapsed(Duration),
    #[error("Operation failed: {0}")]
    OperationFailed(String),
}

/// Execute a future with timeout
pub async fn with_timeout<F, T>(
    duration: Duration,
    future: F,
) -> Result<T, TimeoutError>
where
    F: Future<Output = T>,
{
    timeout(duration, future)
        .await
        .map_err(|_| TimeoutError::Elapsed(duration))
}

/// Execute a fallible future with timeout
pub async fn with_timeout_result<F, T, E>(
    duration: Duration,
    future: F,
) -> Result<T, TimeoutError>
where
    F: Future<Output = Result<T, E>>,
    E: std::fmt::Display,
{
    match timeout(duration, future).await {
        Ok(Ok(result)) => Ok(result),
        Ok(Err(e)) => Err(TimeoutError::OperationFailed(e.to_string())),
        Err(_) => Err(TimeoutError::Elapsed(duration)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_timeout_success() {
        let result = with_timeout(Duration::from_secs(1), async { 42 }).await;
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
    }

    #[tokio::test]
    async fn test_timeout_elapsed() {
        let result = with_timeout(Duration::from_millis(10), async {
            tokio::time::sleep(Duration::from_secs(1)).await;
            42
        })
        .await;

        assert!(result.is_err());
        assert!(matches!(result, Err(TimeoutError::Elapsed(_))));
    }

    #[tokio::test]
    async fn test_timeout_result_success() {
        let result =
            with_timeout_result(Duration::from_secs(1), async { Ok::<_, String>(42) }).await;
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
    }

    #[tokio::test]
    async fn test_timeout_result_operation_failed() {
        let result = with_timeout_result(Duration::from_secs(1), async {
            Err::<i32, _>("operation failed")
        })
        .await;

        assert!(result.is_err());
        assert!(matches!(result, Err(TimeoutError::OperationFailed(_))));
    }
}
