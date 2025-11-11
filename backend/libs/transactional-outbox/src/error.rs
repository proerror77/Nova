//! Error types for the transactional outbox library.

use thiserror::Error;
use uuid::Uuid;

/// Result type alias for outbox operations.
pub type OutboxResult<T> = Result<T, OutboxError>;

/// Errors that can occur during outbox operations.
#[derive(Error, Debug)]
pub enum OutboxError {
    /// Database operation failed
    #[error("Database error: {0}")]
    DatabaseError(#[from] sqlx::Error),

    /// Event not found in outbox
    #[error("Event not found: {0}")]
    EventNotFound(Uuid),

    /// Failed to publish event to message broker
    #[error("Publish failed: {0}")]
    PublishFailed(String),

    /// Serialization/deserialization error
    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    /// Generic error with context
    #[error("Outbox error: {0}")]
    Other(#[from] anyhow::Error),
}
