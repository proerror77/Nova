use thiserror::Error;
use tonic::Status as GrpcStatus;

pub type Result<T> = std::result::Result<T, AppError>;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("Database error: {0}")]
    Database(String),

    #[error("Redis error: {0}")]
    Redis(String),

    #[error("Feature not found: {0}")]
    NotFound(String),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Configuration error: {0}")]
    Configuration(String),

    #[error("Internal error: {0}")]
    Internal(String),

    #[error("Timeout error: {0}")]
    Timeout(String),

    #[error("Serialization error: {0}")]
    Serialization(String),
}

// Implement conversions from other error types
impl From<sqlx::Error> for AppError {
    fn from(err: sqlx::Error) -> Self {
        AppError::Database(err.to_string())
    }
}

impl From<redis::RedisError> for AppError {
    fn from(err: redis::RedisError) -> Self {
        AppError::Redis(err.to_string())
    }
}

impl From<serde_json::Error> for AppError {
    fn from(err: serde_json::Error) -> Self {
        AppError::Serialization(err.to_string())
    }
}

impl From<anyhow::Error> for AppError {
    fn from(err: anyhow::Error) -> Self {
        AppError::Internal(err.to_string())
    }
}

// Convert to gRPC Status for gRPC handlers
impl From<AppError> for GrpcStatus {
    fn from(err: AppError) -> Self {
        match err {
            AppError::NotFound(msg) => GrpcStatus::not_found(msg),
            AppError::Validation(msg) => GrpcStatus::invalid_argument(msg),
            AppError::Timeout(msg) => GrpcStatus::deadline_exceeded(msg),
            AppError::Database(msg) | AppError::Redis(msg) => {
                GrpcStatus::unavailable(msg)
            }
            _ => GrpcStatus::internal(err.to_string()),
        }
    }
}

// Convert from gRPC Status for client calls
impl From<GrpcStatus> for AppError {
    fn from(status: GrpcStatus) -> Self {
        match status.code() {
            tonic::Code::NotFound => AppError::NotFound(status.message().to_string()),
            tonic::Code::InvalidArgument => AppError::Validation(status.message().to_string()),
            tonic::Code::DeadlineExceeded => AppError::Timeout(status.message().to_string()),
            _ => AppError::Internal(status.message().to_string()),
        }
    }
}
