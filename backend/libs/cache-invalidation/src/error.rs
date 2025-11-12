//! Error types for cache invalidation operations

use thiserror::Error;

/// Cache invalidation errors
#[derive(Error, Debug)]
pub enum InvalidationError {
    /// Redis connection or operation error
    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),

    /// Message serialization/deserialization error
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    /// Invalid message format received
    #[error("Invalid message format: {0}")]
    InvalidMessage(String),

    /// Callback execution failed
    #[error("Callback execution failed: {0}")]
    CallbackFailed(String),

    /// Connection timeout
    #[error("Connection timeout: {0}")]
    Timeout(String),

    /// Configuration error
    #[error("Configuration error: {0}")]
    Configuration(String),
}

// Note: anyhow::Error already has a blanket From implementation for all std::error::Error types
// So InvalidationError is automatically convertible to anyhow::Error via the thiserror derive

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let err = InvalidationError::InvalidMessage("test".to_string());
        assert_eq!(err.to_string(), "Invalid message format: test");

        let err = InvalidationError::CallbackFailed("callback error".to_string());
        assert_eq!(err.to_string(), "Callback execution failed: callback error");
    }

    #[test]
    fn test_error_from_serde() {
        let json_err = serde_json::from_str::<String>("invalid json");
        assert!(json_err.is_err());

        let err: InvalidationError = json_err.unwrap_err().into();
        assert!(matches!(err, InvalidationError::Serialization(_)));
    }

    #[test]
    fn test_error_conversion() {
        let err = InvalidationError::Timeout("connection timeout".to_string());
        // Test that error can be used with Result<T, InvalidationError>
        let result: Result<(), InvalidationError> = Err(err);
        assert!(result.is_err());
    }
}
