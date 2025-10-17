use actix_web::{web, HttpResponse, Responder};
use chrono::Utc;
use redis::aio::ConnectionManager;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::db::user_repo;
use crate::security::jwt;
use crate::security::{hash_password, verify_password};
use crate::services::email_verification;
use crate::validators;

#[derive(Debug, Deserialize, Serialize)]
pub struct RegisterRequest {
    pub email: String,
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize)]
pub struct RegisterResponse {
    pub id: String,
    pub email: String,
    pub username: String,
    pub message: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: i64,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub details: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct VerifyEmailRequest {
    pub token: String,
}

#[derive(Debug, Serialize)]
pub struct VerifyEmailResponse {
    pub message: String,
    pub email_verified: bool,
}

#[derive(Debug, Deserialize)]
pub struct LogoutRequest {
    pub access_token: String,
}

#[derive(Debug, Serialize)]
pub struct LogoutResponse {
    pub message: String,
}

#[derive(Debug, Deserialize)]
pub struct RefreshTokenRequest {
    pub refresh_token: String,
}

#[derive(Debug, Serialize)]
pub struct RefreshTokenResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: i64,
}

/// Handle user registration
/// POST /auth/register
pub async fn register(
    pool: web::Data<PgPool>,
    redis: web::Data<ConnectionManager>,
    req: web::Json<RegisterRequest>,
) -> impl Responder {
    // Validate email format
    if !validators::validate_email(&req.email) {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid email format".to_string(),
            details: Some("Email must be a valid RFC 5322 format".to_string()),
        });
    }

    // Validate username
    if !validators::validate_username(&req.username) {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid username".to_string(),
            details: Some("Username must be 3-32 characters, alphanumeric with - or _".to_string()),
        });
    }

    // Validate password strength
    if !validators::validate_password(&req.password) {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Password too weak".to_string(),
            details: Some(
                "Password must be 8+ chars with uppercase, lowercase, number, and special char"
                    .to_string(),
            ),
        });
    }

    // Check if email already exists
    match user_repo::email_exists(pool.get_ref(), &req.email).await {
        Ok(true) => {
            return HttpResponse::Conflict().json(ErrorResponse {
                error: "Email already registered".to_string(),
                details: Some("This email is already in use".to_string()),
            });
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            });
        }
        Ok(false) => {}
    }

    // Check if username already exists
    match user_repo::username_exists(pool.get_ref(), &req.username).await {
        Ok(true) => {
            return HttpResponse::Conflict().json(ErrorResponse {
                error: "Username already taken".to_string(),
                details: Some("This username is already in use".to_string()),
            });
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            });
        }
        Ok(false) => {}
    }

    // Hash password with Argon2
    let password_hash = match hash_password(&req.password) {
        Ok(hash) => hash,
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Password hashing failed".to_string(),
                details: None,
            });
        }
    };

    // Create user in database
    let user =
        match user_repo::create_user(pool.get_ref(), &req.email, &req.username, &password_hash)
            .await
        {
            Ok(user) => user,
            Err(_) => {
                return HttpResponse::InternalServerError().json(ErrorResponse {
                    error: "Failed to create user".to_string(),
                    details: None,
                });
            }
        };

    // Generate verification token in Redis
    match email_verification::store_verification_token(redis.get_ref(), user.id, &user.email).await
    {
        Ok(_token) => {
            // TODO: Send verification email via EMAIL_SERVICE
            // In production: email_service::send_verification_email(&user.email, &token).await
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to generate verification token".to_string(),
                details: None,
            });
        }
    }

    HttpResponse::Created().json(RegisterResponse {
        id: user.id.to_string(),
        email: user.email,
        username: user.username,
        message: "Registration successful. Check your email for verification link.".to_string(),
    })
}

/// Handle user login
/// POST /auth/login
pub async fn login(pool: web::Data<PgPool>, req: web::Json<LoginRequest>) -> impl Responder {
    // Validate email format
    if !validators::validate_email(&req.email) {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid email".to_string(),
            details: None,
        });
    }

    // Find user by email
    let user = match user_repo::find_by_email(pool.get_ref(), &req.email).await {
        Ok(Some(user)) => user,
        Ok(None) => {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Invalid credentials".to_string(),
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

    // Check if email is verified
    if !user.email_verified {
        return HttpResponse::Forbidden().json(ErrorResponse {
            error: "Email not verified".to_string(),
            details: Some("Please verify your email before logging in".to_string()),
        });
    }

    // Check if account is locked
    if let Some(locked_until) = user.locked_until {
        if locked_until > Utc::now() {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Account temporarily locked".to_string(),
                details: Some("Too many failed login attempts".to_string()),
            });
        }
    }

    // Verify password
    if verify_password(&req.password, &user.password_hash).is_err() {
        // Record failed login attempt
        let _ = user_repo::record_failed_login(
            pool.get_ref(),
            user.id,
            user.failed_login_attempts,
            900, // 15 minute lockout
        )
        .await;

        return HttpResponse::Unauthorized().json(ErrorResponse {
            error: "Invalid credentials".to_string(),
            details: None,
        });
    }

    // Generate JWT token pair
    let tokens = match jwt::generate_token_pair(user.id, &user.email, &user.username) {
        Ok(tokens) => tokens,
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to generate tokens".to_string(),
                details: None,
            });
        }
    };

    // Record successful login
    if let Err(_) = user_repo::record_successful_login(pool.get_ref(), user.id).await {
        return HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to record login".to_string(),
            details: None,
        });
    }

    HttpResponse::Ok().json(AuthResponse {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        token_type: tokens.token_type,
        expires_in: tokens.expires_in,
    })
}

/// Handle email verification
/// POST /auth/verify-email
pub async fn verify_email(
    pool: web::Data<PgPool>,
    redis: web::Data<ConnectionManager>,
    req: web::Json<VerifyEmailRequest>,
) -> impl Responder {
    // Validate token format
    if req.token.is_empty() {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Token required".to_string(),
            details: None,
        });
    }

    if req.token.len() > 1000 {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Token too long".to_string(),
            details: None,
        });
    }

    // Check if token contains only hex characters
    if !req.token.chars().all(|c| c.is_ascii_hexdigit()) {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid token format".to_string(),
            details: Some("Token must be hexadecimal".to_string()),
        });
    }

    // Look up user from token in Redis
    let (user_id, email) =
        match email_verification::get_user_from_token(redis.get_ref(), &req.token).await {
            Ok(Some(user_info)) => user_info,
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

    // Verify token against stored value and mark as used
    match email_verification::verify_token(redis.get_ref(), user_id, &email, &req.token).await {
        Ok(true) => {
            // Token is valid, now mark the user's email as verified
            match user_repo::verify_email(pool.get_ref(), user_id).await {
                Ok(_) => {
                    return HttpResponse::Ok().json(VerifyEmailResponse {
                        message: "Email verified successfully".to_string(),
                        email_verified: true,
                    });
                }
                Err(_) => {
                    return HttpResponse::InternalServerError().json(ErrorResponse {
                        error: "Failed to verify email".to_string(),
                        details: None,
                    });
                }
            }
        }
        Ok(false) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid token".to_string(),
                details: Some("Token does not match or has already been used".to_string()),
            });
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Token verification error".to_string(),
                details: None,
            });
        }
    }
}

/// Handle user logout
/// POST /auth/logout
pub async fn logout(
    redis: web::Data<ConnectionManager>,
    req: web::Json<LogoutRequest>,
) -> impl Responder {
    if req.access_token.is_empty() {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Token required".to_string(),
            details: None,
        });
    }

    // Validate token format and extract expiration
    let expires_at = match jwt::validate_token(&req.access_token) {
        Ok(token_data) => token_data.claims.exp,
        Err(_) => {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Invalid token".to_string(),
                details: None,
            });
        }
    };

    // Add token to Redis blacklist
    use crate::services::token_revocation;
    match token_revocation::revoke_token(redis.get_ref(), &req.access_token, expires_at).await {
        Ok(_) => {
            return HttpResponse::Ok().json(LogoutResponse {
                message: "Logged out successfully".to_string(),
            });
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to revoke token".to_string(),
                details: None,
            });
        }
    }
}

/// Handle token refresh
/// POST /auth/refresh-token
pub async fn refresh_token(
    redis: web::Data<ConnectionManager>,
    req: web::Json<RefreshTokenRequest>,
) -> impl Responder {
    // Validate token presence
    if req.refresh_token.is_empty() {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Refresh token required".to_string(),
            details: None,
        });
    }

    // Validate refresh token format and signature
    let token_data = match jwt::validate_token(&req.refresh_token) {
        Ok(data) => data,
        Err(_) => {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Invalid refresh token".to_string(),
                details: None,
            });
        }
    };

    // Verify token type is "refresh"
    if token_data.claims.token_type != "refresh" {
        return HttpResponse::Unauthorized().json(ErrorResponse {
            error: "Invalid token type".to_string(),
            details: Some("Token must be a refresh token".to_string()),
        });
    }

    // Check if refresh token has been revoked
    use crate::services::token_revocation;
    match token_revocation::is_token_revoked(redis.get_ref(), &req.refresh_token).await {
        Ok(true) => {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Refresh token has been revoked".to_string(),
                details: None,
            });
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Token verification failed".to_string(),
                details: None,
            });
        }
        Ok(false) => {}
    }

    // Extract user information from token
    let user_id = match uuid::Uuid::parse_str(&token_data.claims.sub) {
        Ok(id) => id,
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Invalid user ID in token".to_string(),
                details: None,
            });
        }
    };

    // Generate new token pair
    let tokens = match jwt::generate_token_pair(
        user_id,
        &token_data.claims.email,
        &token_data.claims.username,
    ) {
        Ok(tokens) => tokens,
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to generate new tokens".to_string(),
                details: None,
            });
        }
    };

    HttpResponse::Ok().json(RefreshTokenResponse {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        token_type: tokens.token_type,
        expires_in: tokens.expires_in,
    })
}
