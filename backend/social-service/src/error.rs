/// Error types for social-service
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ServiceError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("gRPC error: {0}")]
    Grpc(#[from] tonic::Status),

    #[error("Outbox error: {0}")]
    Outbox(#[from] transactional_outbox::OutboxError),

    #[error("Invalid input: {0}")]
    InvalidInput(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Internal error: {0}")]
    Internal(String),
}

/// Convert ServiceError to tonic::Status for gRPC responses
impl From<ServiceError> for tonic::Status {
    fn from(err: ServiceError) -> Self {
        match err {
            ServiceError::InvalidInput(msg) => tonic::Status::invalid_argument(msg),
            ServiceError::NotFound(msg) => tonic::Status::not_found(msg),
            ServiceError::Database(e) => {
                tonic::Status::internal(format!("Database error: {}", e))
            }
            ServiceError::Redis(e) => tonic::Status::internal(format!("Redis error: {}", e)),
            ServiceError::Config(msg) => tonic::Status::internal(format!("Config error: {}", msg)),
            ServiceError::Grpc(status) => status,
            ServiceError::Outbox(e) => tonic::Status::internal(format!("Outbox error: {}", e)),
            ServiceError::Internal(msg) => tonic::Status::internal(msg),
        }
    }
}

/// Result type alias for service operations
pub type ServiceResult<T> = Result<T, ServiceError>;
