use crate::error::AppError;
use axum::{http::StatusCode, response::IntoResponse};

// TDD: map domain errors to HTTP responses
pub fn map_error(err: &AppError) -> (StatusCode, String) {
    match err {
        AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
        AppError::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized".into()),
        AppError::Forbidden => (StatusCode::FORBIDDEN, "forbidden".into()),
        AppError::NotFound => (StatusCode::NOT_FOUND, "not found".into()),
        AppError::Config(msg) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("config error: {}", msg),
        ),
        AppError::StartServer(msg) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("server error: {}", msg),
        ),
        AppError::Database(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("database error: {}", e),
        ),
        AppError::Encryption(msg) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("encryption error: {}", msg),
        ),
        AppError::Internal => (
            StatusCode::INTERNAL_SERVER_ERROR,
            "internal server error".into(),
        ),
        AppError::AlreadyRecalled => (
            StatusCode::CONFLICT,
            "message has already been recalled".into(),
        ),
        AppError::RecallWindowExpired {
            created_at,
            max_recall_minutes,
        } => (
            StatusCode::FORBIDDEN,
            format!(
                "recall window expired (message created at {}, max recall time: {} minutes)",
                created_at, max_recall_minutes
            ),
        ),
        AppError::EditWindowExpired { max_edit_minutes } => (
            StatusCode::FORBIDDEN,
            format!("edit window expired (max edit time: {} minutes)", max_edit_minutes),
        ),
        AppError::VersionConflict {
            current_version,
            client_version,
            server_content,
        } => (
            StatusCode::CONFLICT,
            format!(
                "version conflict: client version {} does not match server version {} (server content: {})",
                client_version, current_version, server_content
            ),
        ),
    }
}

pub fn into_response(err: AppError) -> impl IntoResponse {
    let (status, msg) = map_error(&err);
    (status, msg)
}
