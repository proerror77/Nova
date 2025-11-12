//! Error types for idempotent consumer library

use thiserror::Error;

/// Result type for idempotency operations
pub type IdempotencyResult<T> = Result<T, IdempotencyError>;

/// Errors that can occur during idempotent event processing
#[derive(Error, Debug)]
pub enum IdempotencyError {
    /// Database operation failed (connection, query execution, etc.)
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    /// Event processing logic failed with custom error
    #[error("Event processing failed: {0}")]
    ProcessingFailed(String),

    /// Event ID validation failed (empty, too long, invalid format)
    #[error("Invalid event ID: {0}")]
    InvalidEventId(String),

    /// JSON serialization/deserialization error for metadata
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// Generic error with context
    #[error("{0}")]
    Other(#[from] anyhow::Error),
}

impl IdempotencyError {
    /// Check if error is a duplicate key violation (event already processed)
    ///
    /// This is NOT an error condition - it's the expected behavior for idempotency.
    /// We use INSERT ... ON CONFLICT and check rows_affected to detect duplicates.
    pub fn is_duplicate_key(&self) -> bool {
        match self {
            IdempotencyError::Database(sqlx_err) => {
                // PostgreSQL unique violation error code: 23505
                if let Some(db_err) = sqlx_err.as_database_error() {
                    db_err.code().as_deref() == Some("23505")
                } else {
                    false
                }
            }
            _ => false,
        }
    }

    /// Check if error is transient (should retry)
    pub fn is_transient(&self) -> bool {
        match self {
            IdempotencyError::Database(sqlx_err) => {
                // Connection errors, pool timeout, etc. are transient
                matches!(
                    sqlx_err,
                    sqlx::Error::PoolTimedOut | sqlx::Error::PoolClosed
                )
            }
            _ => false,
        }
    }
}
