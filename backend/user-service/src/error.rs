use actix_web::{error::ResponseError, http::StatusCode, HttpResponse};
use error_types::ErrorResponse;
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
        let (error_type, code) = match self {
            AppError::Database(_) => ("server_error", error_types::error_codes::DATABASE_ERROR),
            AppError::Redis(_) => ("server_error", error_types::error_codes::CACHE_ERROR),
            AppError::Validation(_) => ("validation_error", "VALIDATION_ERROR"),
            AppError::Authentication(_) => (
                "authentication_error",
                error_types::error_codes::INVALID_CREDENTIALS,
            ),
            AppError::Authorization(_) => ("authorization_error", "AUTHORIZATION_ERROR"),
            AppError::NotFound(_) => ("not_found_error", error_types::error_codes::USER_NOT_FOUND),
            AppError::Conflict(_) => ("conflict_error", error_types::error_codes::VERSION_CONFLICT),
            AppError::RateLimitExceeded => (
                "rate_limit_error",
                error_types::error_codes::RATE_LIMIT_ERROR,
            ),
            AppError::Internal(_) => (
                "server_error",
                error_types::error_codes::INTERNAL_SERVER_ERROR,
            ),
            AppError::BadRequest(_) => ("validation_error", "INVALID_REQUEST"),
            AppError::Token(_) => (
                "authentication_error",
                error_types::error_codes::TOKEN_INVALID,
            ),
            AppError::Email(_) => (
                "server_error",
                error_types::error_codes::INTERNAL_SERVER_ERROR,
            ),
            AppError::Kafka(_) => (
                "server_error",
                error_types::error_codes::SERVICE_UNAVAILABLE,
            ),
            AppError::Io(_) => (
                "server_error",
                error_types::error_codes::INTERNAL_SERVER_ERROR,
            ),
            AppError::Configuration(_) => (
                "server_error",
                error_types::error_codes::INTERNAL_SERVER_ERROR,
            ),
        };

        let message = self.to_string();
        let details = match self {
            AppError::Database(e) => Some(e.to_string()),
            AppError::Redis(e) => Some(e.to_string()),
            AppError::Token(e) => Some(e.to_string()),
            AppError::Kafka(e) => Some(e.to_string()),
            AppError::Io(e) => Some(e.to_string()),
            _ => None,
        };

        let response = ErrorResponse::new(
            &match status_code {
                StatusCode::BAD_REQUEST => "Bad Request",
                StatusCode::UNAUTHORIZED => "Unauthorized",
                StatusCode::FORBIDDEN => "Forbidden",
                StatusCode::NOT_FOUND => "Not Found",
                StatusCode::CONFLICT => "Conflict",
                StatusCode::TOO_MANY_REQUESTS => "Too Many Requests",
                StatusCode::INTERNAL_SERVER_ERROR => "Internal Server Error",
                _ => "Error",
            },
            &message,
            status_code.as_u16(),
            error_type,
            code,
        );

        let response = if let Some(detail) = details {
            response.with_details(detail)
        } else {
            response
        };

        HttpResponse::build(status_code).json(response)
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
