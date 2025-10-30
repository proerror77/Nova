use crate::error::AppError;
use axum::{http::StatusCode, response::IntoResponse, Json};
use error_types::ErrorResponse;

// TDD: map domain errors to HTTP responses
pub fn map_error(err: &AppError) -> (StatusCode, ErrorResponse) {
    let status =
        StatusCode::from_u16(err.status_code()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    let (error_type, code) = match err {
        AppError::BadRequest(_) => ("validation_error", "INVALID_REQUEST"),
        AppError::Unauthorized => (
            "authentication_error",
            error_types::error_codes::INVALID_CREDENTIALS,
        ),
        AppError::Forbidden => ("authorization_error", "AUTHORIZATION_ERROR"),
        AppError::NotFound => (
            "not_found_error",
            error_types::error_codes::MESSAGE_NOT_FOUND,
        ),
        AppError::Config(_) => (
            "server_error",
            error_types::error_codes::INTERNAL_SERVER_ERROR,
        ),
        AppError::StartServer(_) => (
            "server_error",
            error_types::error_codes::INTERNAL_SERVER_ERROR,
        ),
        AppError::Database(_) => ("server_error", error_types::error_codes::DATABASE_ERROR),
        AppError::Encryption(_) => ("server_error", "ENCRYPTION_ERROR"),
        AppError::Internal => (
            "server_error",
            error_types::error_codes::INTERNAL_SERVER_ERROR,
        ),
        AppError::AlreadyRecalled => (
            "conflict_error",
            error_types::error_codes::MESSAGE_ALREADY_RECALLED,
        ),
        AppError::RecallWindowExpired { .. } => (
            "authorization_error",
            error_types::error_codes::RECALL_WINDOW_EXPIRED,
        ),
        AppError::EditWindowExpired { .. } => (
            "authorization_error",
            error_types::error_codes::EDIT_WINDOW_EXPIRED,
        ),
        AppError::VersionConflict { .. } => {
            ("conflict_error", error_types::error_codes::VERSION_CONFLICT)
        }
    };

    let message = err.to_string();
    let response = ErrorResponse::new(
        &match status {
            StatusCode::BAD_REQUEST => "Bad Request",
            StatusCode::UNAUTHORIZED => "Unauthorized",
            StatusCode::FORBIDDEN => "Forbidden",
            StatusCode::NOT_FOUND => "Not Found",
            StatusCode::CONFLICT => "Conflict",
            StatusCode::GONE => "Gone",
            StatusCode::INTERNAL_SERVER_ERROR => "Internal Server Error",
            _ => "Error",
        },
        &message,
        status.as_u16(),
        error_type,
        code,
    );

    (status, response)
}

pub fn into_response(err: AppError) -> impl IntoResponse {
    let (status, response) = map_error(&err);
    (status, Json(response))
}
