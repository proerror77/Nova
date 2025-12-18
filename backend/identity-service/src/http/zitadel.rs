/// Zitadel Actions HTTP endpoints
///
/// Provides user claims data for Zitadel Actions to enrich OIDC tokens.
/// This enables Zitadel to use Nova's user IDs and profile data as the
/// source of truth while acting as the OIDC provider.
use crate::db;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{IntoResponse, Json},
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{error, info};
use uuid::Uuid;

use super::HttpServerState;

/// User claims response for Zitadel Actions
///
/// This structure contains all the claims that should be included
/// in the OIDC ID token and UserInfo endpoint.
#[derive(Debug, Serialize, Deserialize)]
pub struct UserClaimsResponse {
    /// Nova user ID (UUID with dashes) - used as OIDC 'sub' claim
    pub sub: String,

    /// Username - used as 'preferred_username' claim
    pub preferred_username: String,

    /// Display name - used as 'name' claim
    pub name: Option<String>,

    /// Email address - used as 'email' claim
    pub email: String,

    /// Email verification status - used as 'email_verified' claim
    pub email_verified: bool,

    /// Avatar/profile picture URL - used as 'picture' claim
    pub picture: Option<String>,

    /// User's given name (first name)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub given_name: Option<String>,

    /// User's family name (last name)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub family_name: Option<String>,

    /// User profile bio
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bio: Option<String>,

    /// User location
    #[serde(skip_serializing_if = "Option::is_none")]
    pub locale: Option<String>,

    /// Phone number (if available)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub phone_number: Option<String>,

    /// Phone verification status
    #[serde(skip_serializing_if = "Option::is_none")]
    pub phone_number_verified: Option<bool>,

    /// Account creation timestamp (Unix timestamp)
    pub created_at: i64,

    /// Last profile update timestamp (Unix timestamp)
    pub updated_at: i64,
}

/// Error response
#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: String,
    message: String,
}

impl IntoResponse for ErrorResponse {
    fn into_response(self) -> axum::response::Response {
        (StatusCode::INTERNAL_SERVER_ERROR, Json(self)).into_response()
    }
}

/// GET /internal/zitadel/user-claims/:user_id
///
/// Fetch user claims for Zitadel OIDC token enrichment.
///
/// This endpoint is called by Zitadel Actions during token issuance to fetch
/// Nova user data and inject it into the OIDC claims.
///
/// Authentication: Requires X-Internal-API-Key header (validated by middleware)
///
/// Path Parameters:
/// - user_id: Nova user UUID (with or without dashes)
///
/// Response:
/// - 200 OK: Returns UserClaimsResponse
/// - 404 Not Found: User not found
/// - 500 Internal Server Error: Database or parsing error
pub async fn get_user_claims(
    State(state): State<Arc<HttpServerState>>,
    Path(user_id_str): Path<String>,
) -> impl IntoResponse {
    // Parse user ID (handle both formats: with and without dashes)
    let user_id = match Uuid::parse_str(&user_id_str) {
        Ok(id) => id,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: "invalid_user_id".to_string(),
                    message: format!("Invalid user ID format: {}", user_id_str),
                }),
            )
                .into_response();
        }
    };

    // Fetch user from database
    let user = match db::users::find_by_id(&state.db, user_id).await {
        Ok(Some(user)) => user,
        Ok(None) => {
            info!(user_id = %user_id, "User not found for Zitadel claims fetch");
            return (
                StatusCode::NOT_FOUND,
                Json(ErrorResponse {
                    error: "user_not_found".to_string(),
                    message: format!("User not found: {}", user_id),
                }),
            )
                .into_response();
        }
        Err(e) => {
            error!(user_id = %user_id, error = %e, "Database error fetching user for Zitadel claims");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "database_error".to_string(),
                    message: "Failed to fetch user data".to_string(),
                }),
            )
                .into_response();
        }
    };

    // Build claims response
    let claims = UserClaimsResponse {
        sub: user.id.to_string(), // UUID with dashes
        preferred_username: user.username.clone(),
        name: user.display_name.clone().or(Some(user.username.clone())),
        email: user.email.clone(),
        email_verified: user.email_verified,
        picture: user.avatar_url.clone(),
        given_name: user.first_name.clone(),
        family_name: user.last_name.clone(),
        bio: user.bio.clone(),
        locale: user.location.clone(),
        phone_number: user.phone_number.clone(),
        phone_number_verified: if user.phone_number.is_some() {
            Some(user.phone_verified)
        } else {
            None
        },
        created_at: user.created_at.timestamp(),
        updated_at: user.updated_at.timestamp(),
    };

    info!(
        user_id = %user.id,
        username = %user.username,
        email = %user.email,
        "Successfully fetched user claims for Zitadel"
    );

    (StatusCode::OK, Json(claims)).into_response()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_user_claims_serialization() {
        let claims = UserClaimsResponse {
            sub: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            preferred_username: "testuser".to_string(),
            name: Some("Test User".to_string()),
            email: "test@nova.app".to_string(),
            email_verified: true,
            picture: Some("https://cdn.nova.app/avatars/test.jpg".to_string()),
            given_name: Some("Test".to_string()),
            family_name: Some("User".to_string()),
            bio: None,
            locale: None,
            phone_number: None,
            phone_number_verified: None,
            created_at: 1704067200,
            updated_at: 1704067200,
        };

        let json = serde_json::to_string(&claims).unwrap();
        assert!(json.contains("sub"));
        assert!(json.contains("preferred_username"));
        assert!(json.contains("email_verified"));
    }
}
