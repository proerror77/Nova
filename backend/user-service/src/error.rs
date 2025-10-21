use actix_web::{error::ResponseError, http::StatusCode, HttpResponse};
use serde::Serialize;
use thiserror::Error;

pub type Result<T> = std::result::Result<T, AppError>;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Authentication error: {0}")]
    Authentication(String),

    #[error("Authorization error: {0}")]
    Authorization(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Rate limit exceeded")]
    RateLimitExceeded,

    #[error("Internal server error: {0}")]
    Internal(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Token error: {0}")]
    Token(#[from] jsonwebtoken::errors::Error),

    #[error("Email error: {0}")]
    Email(String),

    #[error("Kafka error: {0}")]
    Kafka(#[from] rdkafka::error::KafkaError),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Configuration error: {0}")]
    Configuration(String),
}

/// Unified error response structure used across all API endpoints
/// Eliminates duplication of error response definitions across handlers
#[derive(Debug, Clone, Serialize)]
pub struct ErrorResponse {
    /// Error code/type (e.g., "Email already registered", "Invalid email format")
    pub error: String,
    /// Optional additional details about the error
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
}

impl ErrorResponse {
    /// Create a new error response with just an error message
    pub fn new(error: impl Into<String>) -> Self {
        Self {
            error: error.into(),
            details: None,
        }
    }

    /// Create a new error response with error message and additional details
    pub fn with_details(error: impl Into<String>, details: impl Into<String>) -> Self {
        Self {
            error: error.into(),
            details: Some(details.into()),
        }
    }
}

impl ResponseError for AppError {
    fn status_code(&self) -> StatusCode {
        match self {
            AppError::Database(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AppError::Redis(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AppError::Validation(_) => StatusCode::BAD_REQUEST,
            AppError::Authentication(_) => StatusCode::UNAUTHORIZED,
            AppError::Authorization(_) => StatusCode::FORBIDDEN,
            AppError::NotFound(_) => StatusCode::NOT_FOUND,
            AppError::Conflict(_) => StatusCode::CONFLICT,
            AppError::RateLimitExceeded => StatusCode::TOO_MANY_REQUESTS,
            AppError::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AppError::BadRequest(_) => StatusCode::BAD_REQUEST,
            AppError::Token(_) => StatusCode::UNAUTHORIZED,
            AppError::Email(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AppError::Kafka(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AppError::Io(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AppError::Configuration(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }

    fn error_response(&self) -> HttpResponse {
        let status_code = self.status_code();
        let error_type = match self {
            AppError::Database(_) => "DATABASE_ERROR",
            AppError::Redis(_) => "CACHE_ERROR",
            AppError::Validation(_) => "VALIDATION_ERROR",
            AppError::Authentication(_) => "AUTHENTICATION_ERROR",
            AppError::Authorization(_) => "AUTHORIZATION_ERROR",
            AppError::NotFound(_) => "NOT_FOUND",
            AppError::Conflict(_) => "CONFLICT",
            AppError::RateLimitExceeded => "RATE_LIMIT_EXCEEDED",
            AppError::Internal(_) => "INTERNAL_ERROR",
            AppError::BadRequest(_) => "BAD_REQUEST",
            AppError::Token(_) => "TOKEN_ERROR",
            AppError::Email(_) => "EMAIL_ERROR",
            AppError::Kafka(_) => "KAFKA_ERROR",
            AppError::Io(_) => "IO_ERROR",
            AppError::Configuration(_) => "CONFIGURATION_ERROR",
        };

        let error_message = self.to_string();
        let details = match self {
            AppError::Database(e) => Some(e.to_string()),
            AppError::Redis(e) => Some(e.to_string()),
            AppError::Token(e) => Some(e.to_string()),
            AppError::Kafka(e) => Some(e.to_string()),
            AppError::Io(e) => Some(e.to_string()),
            _ => None,
        };

        let error_response = ErrorResponse {
            error: error_message,
            details,
        };

        HttpResponse::build(status_code).json(error_response)
    }
}

// Convert validator errors to AppError
impl From<validator::ValidationErrors> for AppError {
    fn from(errors: validator::ValidationErrors) -> Self {
        AppError::Validation(errors.to_string())
    }
}

// Convert lettre errors to AppError
impl From<lettre::error::Error> for AppError {
    fn from(error: lettre::error::Error) -> Self {
        AppError::Email(error.to_string())
    }
}

impl From<lettre::transport::smtp::Error> for AppError {
    fn from(error: lettre::transport::smtp::Error) -> Self {
        AppError::Email(error.to_string())
    }
}

// Convert serde_json errors to AppError
impl From<serde_json::Error> for AppError {
    fn from(error: serde_json::Error) -> Self {
        AppError::Internal(format!("JSON serialization error: {}", error))
    }
}
