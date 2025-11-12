//! Error types for health check operations

use thiserror::Error;

/// Result type for health check operations
pub type Result<T> = std::result::Result<T, HealthCheckError>;

/// Errors that can occur during health checks
#[derive(Debug, Error)]
pub enum HealthCheckError {
    /// Database connection or query failure
    #[error("Database health check failed: {0}")]
    Database(String),

    /// Redis connection or command failure
    #[error("Cache health check failed: {0}")]
    Cache(String),

    /// Kafka connection or metadata fetch failure
    #[error("Message queue health check failed: {0}")]
    MessageQueue(String),

    /// Generic health check failure
    #[error("Health check failed: {0}")]
    Generic(String),
}

impl HealthCheckError {
    /// Create a database error
    pub fn database(msg: impl Into<String>) -> Self {
        Self::Database(msg.into())
    }

    /// Create a cache error
    pub fn cache(msg: impl Into<String>) -> Self {
        Self::Cache(msg.into())
    }

    /// Create a message queue error
    pub fn message_queue(msg: impl Into<String>) -> Self {
        Self::MessageQueue(msg.into())
    }

    /// Create a generic error
    pub fn generic(msg: impl Into<String>) -> Self {
        Self::Generic(msg.into())
    }
}
