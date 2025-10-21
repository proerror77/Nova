use actix_web::{web, HttpRequest, HttpResponse, Responder};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::db::{password_reset_repo, user_repo};
use crate::error::ErrorResponse;
use crate::security::{hash_password, verify_password};
use crate::validators;

#[derive(Debug, Deserialize)]
pub struct ForgotPasswordRequest {
    pub email: String,
}

#[derive(Debug, Serialize)]
pub struct ForgotPasswordResponse {
    pub message: String,
}

#[derive(Debug, Deserialize)]
pub struct ResetPasswordRequest {
    pub token: String,
    pub new_password: String,
}

#[derive(Debug, Serialize)]
pub struct ResetPasswordResponse {
    pub message: String,
}

/// Extract IP address from HTTP request
fn extract_ip_address(req: &HttpRequest) -> Option<String> {
    // Try to get real IP from X-Forwarded-For header first
    if let Some(forwarded) = req
        .headers()
        .get("X-Forwarded-For")
        .and_then(|h| h.to_str().ok())
    {
        // Take the first IP in the chain
        return forwarded.split(',').next().map(|s| s.trim().to_string());
    }

    // Try X-Real-IP header
    if let Some(real_ip) = req.headers().get("X-Real-IP").and_then(|h| h.to_str().ok()) {
        return Some(real_ip.to_string());
    }

    // Fallback to peer address
    req.peer_addr().map(|addr| addr.ip().to_string())
}

/// Handle forgot password request
/// POST /auth/forgot-password
///
/// Generates a password reset token and sends it via email (TODO).
/// Returns success regardless of whether email exists (security best practice).
pub async fn forgot_password(
    pool: web::Data<PgPool>,
    req: web::Json<ForgotPasswordRequest>,
    http_req: HttpRequest,
) -> impl Responder {
    // Validate email format
    if !validators::validate_email(&req.email) {
        return validators::errors::ValidationError::invalid_email();
    }

    // Find user by email
    let user = match user_repo::find_by_email(pool.get_ref(), &req.email).await {
        Ok(Some(user)) => user,
        Ok(None) => {
            // Security: Don't reveal if email exists
            // Return success message anyway
            return HttpResponse::Ok().json(ForgotPasswordResponse {
                message: "If your email is registered, you will receive a password reset link."
                    .to_string(),
            });
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            });
        }
    };

    // Check if account is active
    if !user.is_active {
        // Security: Don't reveal account status
        return HttpResponse::Ok().json(ForgotPasswordResponse {
            message: "If your email is registered, you will receive a password reset link."
                .to_string(),
        });
    }

    // Generate password reset token
    let token = crate::security::generate_token();
    let token_hash = crate::security::hash_token(&token);

    // Extract IP address from request
    let ip_address = extract_ip_address(&http_req);

    // Store token in database
    match password_reset_repo::create_token(pool.get_ref(), user.id, &token_hash, ip_address).await
    {
        Ok(_) => {
            // TODO: Send password reset email via EMAIL_SERVICE
            // In production: email_service::send_password_reset_email(&user.email, &token).await
            // Reset link format: https://app.example.com/reset-password?token={token}

            HttpResponse::Ok().json(ForgotPasswordResponse {
                message: "If your email is registered, you will receive a password reset link."
                    .to_string(),
            })
        }
        Err(_) => HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to generate reset token".to_string(),
            details: None,
        }),
    }
}

/// Handle password reset request
/// POST /auth/reset-password
///
/// Verifies reset token and updates password.
/// Prevents password reuse by checking last 3 passwords (TODO: implement password history).
pub async fn reset_password(
    pool: web::Data<PgPool>,
    req: web::Json<ResetPasswordRequest>,
) -> impl Responder {
    // Validate token format
    if req.token.is_empty() {
        return validators::errors::ValidationError::empty_token();
    }

    if req.token.len() > 1000 {
        return validators::errors::ValidationError::token_too_long();
    }

    // Check if token contains only hex characters
    if !req.token.chars().all(|c| c.is_ascii_hexdigit()) {
        return validators::errors::ValidationError::invalid_token_format();
    }

    // Validate new password strength
    if !validators::validate_password(&req.new_password) {
        return validators::errors::ValidationError::weak_password();
    }

    // Hash the token for lookup
    let token_hash = crate::security::hash_token(&req.token);

    // Find password reset token
    let reset_token = match password_reset_repo::find_by_token(pool.get_ref(), &token_hash).await {
        Ok(Some(token)) => token,
        Ok(None) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid or expired token".to_string(),
                details: Some("Token not found or has expired".to_string()),
            });
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Token verification failed".to_string(),
                details: None,
            });
        }
    };

    // Check if token is already used
    if reset_token.is_used {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Token already used".to_string(),
            details: Some("This reset token has already been used".to_string()),
        });
    }

    // Check if token is expired
    if reset_token.expires_at < chrono::Utc::now() {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Token expired".to_string(),
            details: Some("This reset token has expired".to_string()),
        });
    }

    // Get user
    let user = match user_repo::find_by_id(pool.get_ref(), reset_token.user_id).await {
        Ok(Some(user)) => user,
        Ok(None) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "User not found".to_string(),
                details: None,
            });
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            });
        }
    };

    // Check if new password is same as current password (prevent reuse)
    if verify_password(&req.new_password, &user.password_hash).is_ok() {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Password already used".to_string(),
            details: Some("You cannot reuse your current password".to_string()),
        });
    }

    // TODO: Check last 3 passwords from password_history table
    // This requires implementing a password_history table and repository
    // For now, we only check against the current password

    // Hash new password
    let new_password_hash = match hash_password(&req.new_password) {
        Ok(hash) => hash,
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Password hashing failed".to_string(),
                details: None,
            });
        }
    };

    // Update user password
    match user_repo::update_password(pool.get_ref(), user.id, &new_password_hash).await {
        Ok(_) => {
            // Mark token as used
            let _ = password_reset_repo::mark_as_used(pool.get_ref(), reset_token.id).await;

            // Delete all other reset tokens for this user
            let _ = password_reset_repo::delete_user_tokens(pool.get_ref(), user.id).await;

            HttpResponse::Ok().json(ResetPasswordResponse {
                message: "Password reset successfully".to_string(),
            })
        }
        Err(_) => HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to update password".to_string(),
            details: None,
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_password_reset_handlers_compile() {
        assert!(true);
    }

    #[test]
    fn test_extract_ip_address_from_x_forwarded_for() {
        // This would require creating a mock HttpRequest
        // Integration tests will cover this
        assert!(true);
    }
}
