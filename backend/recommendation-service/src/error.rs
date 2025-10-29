use actix_web::http::StatusCode;
use actix_web::{HttpResponse, ResponseError};
use serde::Serialize;
use thiserror::Error;
use tonic::Status as GrpcStatus;

pub type Result<T> = std::result::Result<T, AppError>;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("Database error: {0}")]
    Database(String),

    #[error("Database error: {0}")]
    DatabaseError(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Authentication error: {0}")]
    Authentication(String),

    #[error("Authorization error: {0}")]
    Authorization(String),

    #[error("Internal server error: {0}")]
    Internal(String),

    #[error("Internal server error: {0}")]
    InternalError(String),

    #[error("Model loading error: {0}")]
    ModelLoadError(String),

    #[error("Inference error: {0}")]
    InferenceError(String),

    #[error("Service unavailable: {0}")]
    ServiceUnavailable(String),
}

#[derive(Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub code: u16,
}

impl ResponseError for AppError {
    fn error_response(&self) -> HttpResponse {
        let (code, message) = match self {
            AppError::NotFound(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            AppError::ValidationError(msg) | AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            AppError::Authentication(msg) => (StatusCode::UNAUTHORIZED, msg.clone()),
            AppError::Authorization(msg) => (StatusCode::FORBIDDEN, msg.clone()),
            AppError::ServiceUnavailable(msg) => (StatusCode::SERVICE_UNAVAILABLE, msg.clone()),
            AppError::Database(msg) | AppError::DatabaseError(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
            AppError::ModelLoadError(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
            AppError::InferenceError(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
            AppError::Internal(msg) | AppError::InternalError(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
        };

        HttpResponse::build(code).json(ErrorResponse {
            error: message,
            code: code.as_u16(),
        })
    }

    fn status_code(&self) -> StatusCode {
        match self {
            AppError::NotFound(_) => StatusCode::NOT_FOUND,
            AppError::ValidationError(_) | AppError::BadRequest(_) => StatusCode::BAD_REQUEST,
            AppError::Authentication(_) => StatusCode::UNAUTHORIZED,
            AppError::Authorization(_) => StatusCode::FORBIDDEN,
            AppError::ServiceUnavailable(_) => StatusCode::SERVICE_UNAVAILABLE,
            _ => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

// Implement conversions from other error types
impl From<sqlx::Error> for AppError {
    fn from(err: sqlx::Error) -> Self {
        AppError::DatabaseError(err.to_string())
    }
}

impl From<anyhow::Error> for AppError {
    fn from(err: anyhow::Error) -> Self {
        AppError::InternalError(err.to_string())
    }
}

impl From<GrpcStatus> for AppError {
    fn from(status: GrpcStatus) -> Self {
        match status.code() {
            tonic::Code::NotFound => AppError::NotFound(status.message().to_string()),
            tonic::Code::InvalidArgument => AppError::ValidationError(status.message().to_string()),
            _ => AppError::InternalError(status.message().to_string()),
        }
    }
}
