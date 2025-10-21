/// Unified validation error messages and response builders
use actix_web::HttpResponse;
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub details: Option<String>,
}

/// Centralized validation error definitions
pub mod messages {
    pub const INVALID_EMAIL: (&str, &str) = (
        "Invalid email format",
        "Email must be a valid RFC 5322 format",
    );

    pub const INVALID_USERNAME: (&str, &str) = (
        "Invalid username",
        "Username must be 3-32 characters, alphanumeric with - or _",
    );

    pub const WEAK_PASSWORD: (&str, &str) = (
        "Password too weak",
        "Password must be 8+ chars with uppercase, lowercase, number, and special char",
    );

    pub const EMPTY_TOKEN: (&str, &str) = ("Token required", "");

    pub const TOKEN_TOO_LONG: (&str, &str) = ("Token too long", "");

    pub const INVALID_TOKEN_FORMAT: (&str, &str) =
        ("Invalid token format", "Token must be hexadecimal");
}

/// Builder for validation error responses
pub struct ValidationError;

impl ValidationError {
    /// Create a BadRequest response for validation errors
    pub fn bad_request(error: &str, details: &str) -> HttpResponse {
        let response = ErrorResponse {
            error: error.to_string(),
            details: if details.is_empty() {
                None
            } else {
                Some(details.to_string())
            },
        };
        HttpResponse::BadRequest().json(response)
    }

    /// Create standard responses for common validation failures
    pub fn invalid_email() -> HttpResponse {
        Self::bad_request(messages::INVALID_EMAIL.0, messages::INVALID_EMAIL.1)
    }

    pub fn invalid_username() -> HttpResponse {
        Self::bad_request(messages::INVALID_USERNAME.0, messages::INVALID_USERNAME.1)
    }

    pub fn weak_password() -> HttpResponse {
        Self::bad_request(messages::WEAK_PASSWORD.0, messages::WEAK_PASSWORD.1)
    }

    pub fn empty_token() -> HttpResponse {
        Self::bad_request(messages::EMPTY_TOKEN.0, messages::EMPTY_TOKEN.1)
    }

    pub fn token_too_long() -> HttpResponse {
        Self::bad_request(messages::TOKEN_TOO_LONG.0, messages::TOKEN_TOO_LONG.1)
    }

    pub fn invalid_token_format() -> HttpResponse {
        Self::bad_request(
            messages::INVALID_TOKEN_FORMAT.0,
            messages::INVALID_TOKEN_FORMAT.1,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_invalid_email_message() {
        let response = ValidationError::invalid_email();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[test]
    fn test_weak_password_message() {
        let response = ValidationError::weak_password();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[test]
    fn test_error_response_with_details() {
        let resp = ErrorResponse {
            error: "Test error".to_string(),
            details: Some("Test details".to_string()),
        };
        assert_eq!(resp.error, "Test error");
        assert_eq!(resp.details, Some("Test details".to_string()));
    }

    #[test]
    fn test_error_response_without_details() {
        let resp = ErrorResponse {
            error: "Test error".to_string(),
            details: None,
        };
        assert_eq!(resp.error, "Test error");
        assert_eq!(resp.details, None);
    }
}
