use axum::{http::StatusCode, response::IntoResponse};
use crate::error::AppError;

// TDD: map domain errors to HTTP responses
pub fn map_error(err: &AppError) -> (StatusCode, String) {
    match err {
        AppError::Config(_) => (StatusCode::INTERNAL_SERVER_ERROR, "config error".into()),
        AppError::StartServer(_) => (StatusCode::INTERNAL_SERVER_ERROR, "server error".into()),
    }
}

pub fn into_response(err: AppError) -> impl IntoResponse {
    let (status, msg) = map_error(&err);
    (status, msg)
}

