use crate::error::AppError;
use actix_web::HttpResponse;
use error_types::ErrorResponse;

// Map domain errors to HTTP responses
pub fn map_error(err: &AppError) -> (u16, ErrorResponse) {
    let status = err.status_code();
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
            400 => "Bad Request",
            401 => "Unauthorized",
            403 => "Forbidden",
            404 => "Not Found",
            409 => "Conflict",
            410 => "Gone",
            500 => "Internal Server Error",
            _ => "Error",
        },
        &message,
        status,
        error_type,
        code,
    );

    (status, response)
}

pub fn into_response(err: AppError) -> HttpResponse {
    let (status, response) = map_error(&err);
    HttpResponse::build(actix_web::http::StatusCode::from_u16(status).unwrap()).json(response)
}
