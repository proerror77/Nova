use actix_web::http::StatusCode;
use actix_web::{HttpResponse, ResponseError};
use serde::Serialize;
use thiserror::Error;

pub type Result<T> = std::result::Result<T, AnalyticsError>;

#[derive(Debug, Error)]
pub enum AnalyticsError {
    #[error("Database error: {0}")]
    Database(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Internal error: {0}")]
    Internal(String),

    #[error("Kafka error: {0}")]
    Kafka(String),

    #[error("ClickHouse error: {0}")]
    ClickHouse(String),

    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),
}

// Backwards compatibility alias
pub type AppError = AnalyticsError;

#[derive(Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub code: u16,
}

impl ResponseError for AnalyticsError {
    fn error_response(&self) -> HttpResponse {
        let (code, message) = match self {
            AnalyticsError::NotFound(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            AnalyticsError::Validation(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            _ => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
        };

        HttpResponse::build(code).json(ErrorResponse {
            error: message,
            code: code.as_u16(),
        })
    }

    fn status_code(&self) -> StatusCode {
        match self {
            AnalyticsError::NotFound(_) => StatusCode::NOT_FOUND,
            AnalyticsError::Validation(_) => StatusCode::BAD_REQUEST,
            _ => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

impl From<sqlx::Error> for AnalyticsError {
    fn from(err: sqlx::Error) -> Self {
        AnalyticsError::Database(err.to_string())
    }
}
