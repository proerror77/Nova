use axum::{http::StatusCode, response::IntoResponse};
use crate::error::AppError;

// TDD: map domain errors to HTTP responses
pub fn map_error(err: &AppError) -> (StatusCode, String) {
    match err {
        AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
        AppError::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized".into()),
        AppError::Forbidden => (StatusCode::FORBIDDEN, "forbidden".into()),
        AppError::NotFound => (StatusCode::NOT_FOUND, "not found".into()),
        AppError::Config(msg) => (StatusCode::INTERNAL_SERVER_ERROR, format!("config error: {}", msg)),
        AppError::StartServer(msg) => (StatusCode::INTERNAL_SERVER_ERROR, format!("server error: {}", msg)),
        AppError::Database(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("database error: {}", e)),
        AppError::Encryption(msg) => (StatusCode::INTERNAL_SERVER_ERROR, format!("encryption error: {}", msg)),
        AppError::Internal => (StatusCode::INTERNAL_SERVER_ERROR, "internal server error".into()),
    }
}

pub fn into_response(err: AppError) -> impl IntoResponse {
    let (status, msg) = map_error(&err);
    (status, msg)
}
