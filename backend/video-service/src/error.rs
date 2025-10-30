use actix_web::http::StatusCode;
use actix_web::{HttpResponse, ResponseError};
use serde::Serialize;
use std::io;
use thiserror::Error;
use tonic::Status as GrpcStatus;

pub type Result<T> = std::result::Result<T, AppError>;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("Database error: {0}")]
    DatabaseError(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Internal server error: {0}")]
    InternalError(String),

    #[error("Internal error: {0}")]
    Internal(String),

    #[error("IO error: {0}")]
    IoError(String),

    #[error("FFmpeg error: {0}")]
    FFmpegError(String),
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
            AppError::ValidationError(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            _ => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
        };

        HttpResponse::build(code).json(ErrorResponse {
            error: message,
            code: code.as_u16(),
        })
    }

    fn status_code(&self) -> StatusCode {
        match self {
            AppError::NotFound(_) => StatusCode::NOT_FOUND,
            AppError::ValidationError(_) => StatusCode::BAD_REQUEST,
            _ => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

impl From<sqlx::Error> for AppError {
    fn from(err: sqlx::Error) -> Self {
        AppError::DatabaseError(err.to_string())
    }
}

impl From<io::Error> for AppError {
    fn from(err: io::Error) -> Self {
        AppError::IoError(err.to_string())
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
