use thiserror::Error;
use axum::response::{IntoResponse, Response};
use crate::middleware::error_handling;

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        error_handling::into_response(self).into_response()
    }
}

pub type AppResult<T> = Result<T, AppError>;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("configuration error: {0}")]
    Config(String),
    #[error("server start failure: {0}")]
    StartServer(String),
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("unauthorized: {0}")]
    Unauthorized(String),
    #[error("forbidden: {0}")]
    Forbidden(String),
    #[error("not found: {0}")]
    NotFound(String),
}
