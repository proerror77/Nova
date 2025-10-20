use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Responder};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::db::{oauth_repo, user_repo};
use crate::middleware::jwt_auth::UserId;
use crate::security::jwt;
use crate::services::oauth::{OAuthProvider, OAuthProviderFactory};

// ============================================
// Request/Response Types
// ============================================

#[derive(Debug, Deserialize)]
pub struct OAuthAuthorizeRequest {
    pub provider: String,
    pub code: String,
    pub state: String,
    #[serde(default = "default_redirect_uri")]
    pub redirect_uri: String,
}

fn default_redirect_uri() -> String {
    std::env::var("OAUTH_REDIRECT_URI")
        .unwrap_or_else(|_| "http://localhost:3000/auth/callback".to_string())
}

#[derive(Debug, Serialize)]
pub struct OAuthAuthorizeResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: i64,
    pub user_id: String,
    pub email: String,
}

#[derive(Debug, Deserialize)]
pub struct OAuthLinkRequest {
    pub provider: String,
    pub code: String,
    pub state: String,
    #[serde(default = "default_redirect_uri")]
    pub redirect_uri: String,
}

#[derive(Debug, Serialize)]
pub struct OAuthLinkResponse {
    pub message: String,
    pub provider: String,
    pub linked: bool,
}

#[derive(Debug, Serialize)]
pub struct OAuthUnlinkResponse {
    pub message: String,
    pub provider: String,
    pub unlinked: bool,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub details: Option<String>,
}

// ============================================
// Handler: POST /auth/oauth/authorize
// ============================================

/// Handle OAuth provider callback and authorize user
/// Creates new user if first OAuth login, or returns existing user
pub async fn authorize(
    pool: web::Data<PgPool>,
    req: web::Json<OAuthAuthorizeRequest>,
) -> impl Responder {
    // 1. Create OAuth provider instance
    let provider: Box<dyn OAuthProvider> = match OAuthProviderFactory::create(&req.provider) {
        Ok(p) => p,
        Err(e) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid OAuth provider".to_string(),
                details: Some(e.to_string()),
            });
        }
    };

    // 2. Verify state parameter (CSRF protection)
    if let Err(e) = provider.verify_state(&req.state) {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid state parameter".to_string(),
            details: Some(e.to_string()),
        });
    }

    // 3. Exchange authorization code for tokens and user info
    let oauth_user_info = match provider.exchange_code(&req.code, &req.redirect_uri).await {
        Ok(info) => info,
        Err(e) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Failed to exchange authorization code".to_string(),
                details: Some(e.to_string()),
            });
        }
    };

    // 4. Check if OAuth connection already exists
    let existing_connection = match oauth_repo::find_by_provider(
        pool.get_ref(),
        &oauth_user_info.provider,
        &oauth_user_info.provider_user_id,
    )
    .await
    {
        Ok(conn) => conn,
        Err(e) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: Some(e.to_string()),
            });
        }
    };

    let user_id = if let Some(connection) = existing_connection {
        // 5a. Existing OAuth connection - update tokens
        if let Err(e) = oauth_repo::update_tokens(
            pool.get_ref(),
            connection.id,
            &oauth_user_info.access_token,
            oauth_user_info.refresh_token.as_deref(),
            oauth_user_info.token_expires_at,
        )
        .await
        {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to update OAuth tokens".to_string(),
                details: Some(e.to_string()),
            });
        }

        connection.user_id
    } else {
        // 5b. New OAuth connection - check if user exists by email
        let user = match user_repo::find_by_email(pool.get_ref(), &oauth_user_info.email).await {
            Ok(Some(u)) => u,
            Ok(None) => {
                // Create new user (OAuth users don't have password)
                let generated_username = generate_username_from_email(&oauth_user_info.email);
                let empty_password_hash = ""; // OAuth users have no password

                match user_repo::create_user(
                    pool.get_ref(),
                    &oauth_user_info.email,
                    &generated_username,
                    empty_password_hash,
                )
                .await
                {
                    Ok(u) => u,
                    Err(e) => {
                        return HttpResponse::InternalServerError().json(ErrorResponse {
                            error: "Failed to create user".to_string(),
                            details: Some(e.to_string()),
                        });
                    }
                }
            }
            Err(e) => {
                return HttpResponse::InternalServerError().json(ErrorResponse {
                    error: "Database error".to_string(),
                    details: Some(e.to_string()),
                });
            }
        };

        // 6. Create OAuth connection
        if let Err(e) = oauth_repo::create_connection(
            pool.get_ref(),
            user.id,
            &oauth_user_info.provider,
            &oauth_user_info.provider_user_id,
            &oauth_user_info.email,
            oauth_user_info.display_name.as_deref(),
            &oauth_user_info.access_token,
            oauth_user_info.refresh_token.as_deref(),
            oauth_user_info.token_expires_at,
        )
        .await
        {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to create OAuth connection".to_string(),
                details: Some(e.to_string()),
            });
        }

        user.id
    };

    // 7. Load user to generate JWT
    let user = match user_repo::find_by_id(pool.get_ref(), user_id).await {
        Ok(Some(u)) => u,
        Ok(None) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "User not found after OAuth processing".to_string(),
                details: None,
            });
        }
        Err(e) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: Some(e.to_string()),
            });
        }
    };

    // 8. Generate JWT token pair
    let tokens = match jwt::generate_token_pair(user.id, &user.email, &user.username) {
        Ok(t) => t,
        Err(e) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to generate tokens".to_string(),
                details: Some(e.to_string()),
            });
        }
    };

    // 9. Record successful login
    if let Err(e) = user_repo::record_successful_login(pool.get_ref(), user.id).await {
        // Non-critical error, log but continue
        eprintln!("Failed to record login: {}", e);
    }

    HttpResponse::Ok().json(OAuthAuthorizeResponse {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        token_type: tokens.token_type,
        expires_in: tokens.expires_in,
        user_id: user.id.to_string(),
        email: user.email,
    })
}

// ============================================
// Handler: POST /auth/oauth/link
// ============================================

/// Link a new OAuth provider to an existing authenticated user
pub async fn link_provider(
    pool: web::Data<PgPool>,
    http_req: HttpRequest,
    req: web::Json<OAuthLinkRequest>,
) -> impl Responder {
    // Extract user_id from request extensions (injected by JWT middleware)
    let current_user_id = match http_req.extensions().get::<UserId>() {
        Some(user_id) => user_id.0,
        None => {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Authentication required".to_string(),
                details: None,
            });
        }
    };

    // 1. Create OAuth provider instance
    let provider: Box<dyn OAuthProvider> = match OAuthProviderFactory::create(&req.provider) {
        Ok(p) => p,
        Err(e) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid OAuth provider".to_string(),
                details: Some(e.to_string()),
            });
        }
    };

    // 2. Verify state parameter
    if let Err(e) = provider.verify_state(&req.state) {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid state parameter".to_string(),
            details: Some(e.to_string()),
        });
    }

    // 3. Exchange authorization code for tokens
    let oauth_user_info = match provider.exchange_code(&req.code, &req.redirect_uri).await {
        Ok(info) => info,
        Err(e) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Failed to exchange authorization code".to_string(),
                details: Some(e.to_string()),
            });
        }
    };

    // 4. Check if this provider is already linked to current user
    if let Ok(true) = oauth_repo::provider_exists_for_user(
        pool.get_ref(),
        current_user_id,
        &oauth_user_info.provider,
    )
    .await
    {
        return HttpResponse::Conflict().json(ErrorResponse {
            error: "Provider already linked".to_string(),
            details: Some(format!(
                "This {} account is already linked to your user",
                oauth_user_info.provider
            )),
        });
    }

    // 5. Check if this provider account is linked to another user
    if let Ok(Some(existing_connection)) = oauth_repo::find_by_provider(
        pool.get_ref(),
        &oauth_user_info.provider,
        &oauth_user_info.provider_user_id,
    )
    .await
    {
        if existing_connection.user_id != current_user_id {
            return HttpResponse::Conflict().json(ErrorResponse {
                error: "Provider account already in use".to_string(),
                details: Some("This OAuth account is already linked to another user".to_string()),
            });
        }
    }

    // 6. Create new OAuth connection
    if let Err(e) = oauth_repo::create_connection(
        pool.get_ref(),
        current_user_id,
        &oauth_user_info.provider,
        &oauth_user_info.provider_user_id,
        &oauth_user_info.email,
        oauth_user_info.display_name.as_deref(),
        &oauth_user_info.access_token,
        oauth_user_info.refresh_token.as_deref(),
        oauth_user_info.token_expires_at,
    )
    .await
    {
        return HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to link provider".to_string(),
            details: Some(e.to_string()),
        });
    }

    HttpResponse::Ok().json(OAuthLinkResponse {
        message: format!("{} account linked successfully", oauth_user_info.provider),
        provider: oauth_user_info.provider,
        linked: true,
    })
}

// ============================================
// Handler: DELETE /auth/oauth/link/:provider
// ============================================

/// Unlink an OAuth provider from authenticated user
/// Prevents unlinking if it's the only authentication method
pub async fn unlink_provider(
    pool: web::Data<PgPool>,
    http_req: HttpRequest,
    provider: web::Path<String>,
) -> impl Responder {
    // Extract user_id from request extensions (injected by JWT middleware)
    let current_user_id = match http_req.extensions().get::<UserId>() {
        Some(user_id) => user_id.0,
        None => {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Authentication required".to_string(),
                details: None,
            });
        }
    };
    let provider_name = provider.into_inner();

    // 1. Check if user has password authentication
    let user = match user_repo::find_by_id(pool.get_ref(), current_user_id).await {
        Ok(Some(u)) => u,
        Ok(None) => {
            return HttpResponse::NotFound().json(ErrorResponse {
                error: "User not found".to_string(),
                details: None,
            });
        }
        Err(e) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: Some(e.to_string()),
            });
        }
    };

    let has_password = !user.password_hash.is_empty();

    // 2. Get all OAuth connections for user
    let connections = match oauth_repo::find_by_user(pool.get_ref(), current_user_id).await {
        Ok(conns) => conns,
        Err(e) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: Some(e.to_string()),
            });
        }
    };

    // 3. Prevent unlinking if it's the only authentication method
    if !has_password && connections.len() == 1 {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Cannot unlink last authentication method".to_string(),
            details: Some(
                "Set a password first before unlinking your last OAuth provider".to_string(),
            ),
        });
    }

    // 4. Find the specific connection to unlink
    let connection_to_delete = connections.iter().find(|c| c.provider == provider_name);

    let connection_id = match connection_to_delete {
        Some(conn) => conn.id,
        None => {
            return HttpResponse::NotFound().json(ErrorResponse {
                error: "Provider not linked".to_string(),
                details: Some(format!("{} is not linked to your account", provider_name)),
            });
        }
    };

    // 5. Delete the connection
    if let Err(e) = oauth_repo::delete_connection(pool.get_ref(), connection_id).await {
        return HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to unlink provider".to_string(),
            details: Some(e.to_string()),
        });
    }

    HttpResponse::Ok().json(OAuthUnlinkResponse {
        message: format!("{} unlinked successfully", provider_name),
        provider: provider_name,
        unlinked: true,
    })
}

// ============================================
// Helper Functions
// ============================================

/// Generate a username from email (before @)
/// Ensures uniqueness by appending random suffix if needed
fn generate_username_from_email(email: &str) -> String {
    let username_part = email.split('@').next().unwrap_or("user");
    let random_suffix = uuid::Uuid::new_v4()
        .to_string()
        .split('-')
        .next()
        .unwrap()
        .to_string();
    format!("{}_{}", username_part, random_suffix)
}

// ============================================
// Tests
// ============================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_username_from_email() {
        let username = generate_username_from_email("john.doe@example.com");
        assert!(username.starts_with("john.doe_"));
        assert!(username.len() > "john.doe_".len());
    }

    #[test]
    fn test_generate_username_from_invalid_email() {
        let username = generate_username_from_email("invalid");
        assert!(username.starts_with("invalid_"));
    }

    #[test]
    fn test_default_redirect_uri() {
        let uri = default_redirect_uri();
        assert!(!uri.is_empty());
        assert!(uri.starts_with("http"));
    }

    #[test]
    fn test_oauth_authorize_request_deserialization() {
        let json = r#"{
            "provider": "google",
            "code": "auth_code_123",
            "state": "state_token_456"
        }"#;

        let req: Result<OAuthAuthorizeRequest, _> = serde_json::from_str(json);
        assert!(req.is_ok());

        let req = req.unwrap();
        assert_eq!(req.provider, "google");
        assert_eq!(req.code, "auth_code_123");
        assert_eq!(req.state, "state_token_456");
        assert!(!req.redirect_uri.is_empty()); // Should use default
    }

    #[test]
    fn test_oauth_link_request_with_custom_redirect() {
        let json = r#"{
            "provider": "apple",
            "code": "code_xyz",
            "state": "state_abc",
            "redirect_uri": "https://example.com/callback"
        }"#;

        let req: Result<OAuthLinkRequest, _> = serde_json::from_str(json);
        assert!(req.is_ok());

        let req = req.unwrap();
        assert_eq!(req.redirect_uri, "https://example.com/callback");
    }
}
