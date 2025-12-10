use crate::middleware::error_handling;
use actix_web::{HttpResponse, ResponseError};
use thiserror::Error;

impl ResponseError for AppError {
    fn error_response(&self) -> HttpResponse {
        error_handling::into_response(self.clone())
    }
}

pub type AppResult<T> = Result<T, AppError>;

/// Distinguishes between retryable and permanent errors
#[derive(Debug, Clone, Copy)]
pub enum ErrorKind {
    Retryable,
    Permanent,
}

#[derive(Debug, Error, Clone)]
pub enum AppError {
    #[error("configuration error: {0}")]
    Config(String),

    #[error("server start failure: {0}")]
    StartServer(String),

    #[error("bad request: {0}")]
    BadRequest(String),

    #[error("unauthorized")]
    Unauthorized,

    #[error("forbidden")]
    Forbidden,

    #[error("not found")]
    NotFound,

    #[error("database error: {0}")]
    Database(String),

    #[error("encryption error: {0}")]
    Encryption(String),

    #[error("grpc client error: {0}")]
    GrpcClient(String),

    #[error("internal server error")]
    Internal,

    #[error("service unavailable: {0}")]
    ServiceUnavailable(String),

    #[error("message already recalled")]
    AlreadyRecalled,

    #[error("recall window expired (created_at: {created_at}, max_recall_minutes: {max_recall_minutes})")]
    RecallWindowExpired {
        created_at: chrono::DateTime<chrono::Utc>,
        max_recall_minutes: i64,
    },

    #[error("edit window expired (max_edit_minutes: {max_edit_minutes})")]
    EditWindowExpired { max_edit_minutes: i64 },

    #[error("version conflict: client version {client_version} != server version {current_version}, server content: {server_content}")]
    VersionConflict {
        current_version: i32,
        client_version: i32,
        server_content: String,
    },
}

impl From<tokio_postgres::Error> for AppError {
    fn from(e: tokio_postgres::Error) -> Self {
        AppError::Database(e.to_string())
    }
}

impl From<deadpool_postgres::PoolError> for AppError {
    fn from(e: deadpool_postgres::PoolError) -> Self {
        AppError::Database(e.to_string())
    }
}

// NOTE: No need to implement From<AppError> for actix_web::Error
// because actix-web provides a blanket impl for all ResponseError types:
// impl<T: ResponseError + 'static> From<T> for actix_web::Error

impl AppError {
    /// Returns whether this error is retryable (e.g., database connection timeout)
    pub fn is_retryable(&self) -> bool {
        match self {
            AppError::Database(msg) => {
                msg.contains("PoolTimedOut") || msg.contains("PoolClosed") || msg.contains("Io")
            }
            AppError::Internal => true,
            _ => false,
        }
    }

    /// Returns HTTP status code
    pub fn status_code(&self) -> u16 {
        match self {
            AppError::BadRequest(_) => 400,
            AppError::Unauthorized => 401,
            AppError::Forbidden => 403,
            AppError::NotFound => 404,
            AppError::AlreadyRecalled => 410,        // 410 Gone
            AppError::VersionConflict { .. } => 409, // 409 Conflict
            AppError::RecallWindowExpired { .. } | AppError::EditWindowExpired { .. } => 403,
            AppError::ServiceUnavailable(_) => 503, // 503 Service Unavailable
            AppError::Database(_) | AppError::GrpcClient(_) | AppError::Internal => 500,
            _ => 500,
        }
    }
}
