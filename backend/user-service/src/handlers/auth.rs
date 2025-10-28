use actix_web::{web, HttpResponse, Responder};
use chrono::Utc;
use base64::{engine::general_purpose, Engine as _};
use redis::aio::ConnectionManager;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::db::user_repo;
use crate::middleware::UserId;
use crate::security::jwt;
use crate::security::{hash_password, verify_password};
use crate::services::email_verification;
use crate::validators;
use crate::Config;

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

/// Request to enable 2FA (requires password verification)
#[derive(Debug, Deserialize)]
pub struct Enable2FARequest {
    pub password: String,
}

/// Response with TOTP setup information
#[derive(Debug, Serialize)]
pub struct Enable2FAResponse {
    pub temp_session_id: String,
    pub qr_code: String, // SVG format QR code
    pub secret: String,  // Base32 encoded secret for manual entry
    pub backup_codes: Vec<String>,
    pub expires_in: i64, // Session TTL in seconds
}

/// Request to confirm 2FA setup
#[derive(Debug, Deserialize)]
pub struct Confirm2FARequest {
    pub temp_session_id: String,
    pub code: String, // 6-digit TOTP code
}

/// Response confirming 2FA is now enabled
#[derive(Debug, Serialize)]
pub struct Confirm2FAResponse {
    pub message: String,
    pub two_fa_enabled: bool,
}

/// Request to verify 2FA code during login
#[derive(Debug, Deserialize)]
pub struct Verify2FARequest {
    pub session_id: String,
    pub code: String, // 6-digit TOTP code or 8-char backup code
}

/// Response with JWT tokens after successful 2FA verification
#[derive(Debug, Serialize)]
pub struct Verify2FAResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: i64,
}

// Dev-only: verify email without token (APP_ENV != production)
#[derive(Debug, Deserialize)]
pub struct DevVerifyRequest {
    pub user_id: Option<String>,
    pub email: Option<String>,
}

pub async fn dev_verify_email(
    pool: web::Data<PgPool>,
    req: web::Json<DevVerifyRequest>,
) -> impl Responder {
    if std::env::var("APP_ENV").unwrap_or_else(|_| "development".into()) == "production" {
        return HttpResponse::Forbidden().json(ErrorResponse {
            error: "Not allowed in production".into(),
            details: None,
        });
    }

    // Resolve user id
    use uuid::Uuid;
    let uid = if let Some(ref id) = req.user_id {
        match Uuid::parse_str(id) {
            Ok(u) => Some(u),
            Err(_) => None,
        }
    } else if let Some(ref email) = req.email {
        match user_repo::find_by_email(pool.get_ref(), email).await {
            Ok(Some(u)) => Some(u.id),
            _ => None,
        }
    } else {
        None
    };

    let Some(user_id) = uid else {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Provide user_id or email".into(),
            details: None,
        });
    };

    match user_repo::verify_email(pool.get_ref(), user_id).await {
        Ok(_) => HttpResponse::Ok().json(VerifyEmailResponse {
            message: "Email verified (dev)".into(),
            email_verified: true,
        }),
        Err(e) => HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to verify".into(),
            details: Some(e.to_string()),
        }),
    }
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

    // Dev convenience: auto-verify email
    // Trigger when DEV_AUTO_VERIFY_EMAIL=true OR APP_ENV != production
    let dev_auto = std::env::var("DEV_AUTO_VERIFY_EMAIL")
        .unwrap_or_else(|_| "false".into())
        .eq_ignore_ascii_case("true");
    let is_production = std::env::var("APP_ENV")
        .unwrap_or_else(|_| "development".into())
        .eq_ignore_ascii_case("production");
    if dev_auto || !is_production {
        let _ = user_repo::verify_email(pool.get_ref(), user.id).await;
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
pub async fn login(
    pool: web::Data<PgPool>,
    redis: web::Data<ConnectionManager>,
    config: web::Data<Config>,
    req: web::Json<LoginRequest>,
) -> impl Responder {
    // Validate email format
    if !validators::validate_email(&req.email) {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid email".to_string(),
            details: None,
        });
    }

    // Find user by email
    let mut user = match user_repo::find_by_email(pool.get_ref(), &req.email).await {
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

    // Check if email is verified; in development, optionally auto-verify to unblock local flows
    if !user.email_verified {
        let dev_auto = std::env::var("DEV_AUTO_VERIFY_EMAIL")
            .unwrap_or_else(|_| "false".into())
            .eq_ignore_ascii_case("true");
        let is_production = std::env::var("APP_ENV")
            .unwrap_or_else(|_| "development".into())
            .eq_ignore_ascii_case("production");
        if dev_auto || !is_production {
            // Attempt to auto-verify then reload user
            let _ = user_repo::verify_email(pool.get_ref(), user.id).await;
            if let Ok(Some(u2)) = user_repo::find_by_email(pool.get_ref(), &req.email).await {
                user = u2;
            }
        }
        if !user.email_verified {
            return HttpResponse::Forbidden().json(ErrorResponse {
                error: "Email not verified".to_string(),
                details: Some("Please verify your email before logging in".to_string()),
            });
        }
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
        let max_attempts = std::cmp::max(config.rate_limit.max_requests as i32, 1);
        let lock_duration_secs = match i64::try_from(config.rate_limit.window_secs) {
            Ok(value) if value > 0 => value,
            _ => 900, // Fallback to 15 minutes
        };

        // Record failed login attempt
        let _ = user_repo::record_failed_login(
            pool.get_ref(),
            user.id,
            max_attempts,
            lock_duration_secs,
        )
        .await;

        return HttpResponse::Unauthorized().json(ErrorResponse {
            error: "Invalid credentials".to_string(),
            details: None,
        });
    }

    // Check if 2FA is enabled
    if user.totp_enabled {
        // Create temporary 2FA session in Redis
        use crate::services::two_fa;

        let session_id = uuid::Uuid::new_v4().to_string();
        match two_fa::store_temp_session(redis.get_ref(), &session_id, user.id, "2fa_pending", 300)
            .await
        {
            Ok(_) => {
                return HttpResponse::Accepted().json(serde_json::json!({
                    "session_id": session_id,
                    "message": "2FA verification required",
                    "expires_in": 300
                }));
            }
            Err(_) => {
                return HttpResponse::InternalServerError().json(ErrorResponse {
                    error: "Failed to create 2FA session".to_string(),
                    details: None,
                });
            }
        }
    }

    // Generate JWT token pair (only if 2FA is not enabled)
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
    use crate::security::token_revocation;
    match token_revocation::revoke_token(redis.get_ref(), &req.access_token, Some(expires_at)).await
    {
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

/// Handle enabling 2FA setup
/// POST /auth/2fa/enable
pub async fn enable_2fa(
    pool: web::Data<PgPool>,
    redis: web::Data<ConnectionManager>,
    auth_user: UserId,
    req: web::Json<Enable2FARequest>,
) -> impl Responder {
    let user_id = auth_user.0;

    // Get user from database
    let user = match user_repo::find_by_id(pool.get_ref(), user_id).await {
        Ok(Some(user)) => user,
        Ok(None) => {
            return HttpResponse::NotFound().json(ErrorResponse {
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

    // Verify password
    if verify_password(&req.password, &user.password_hash).is_err() {
        return HttpResponse::Unauthorized().json(ErrorResponse {
            error: "Invalid password".to_string(),
            details: None,
        });
    }

    // If 2FA already enabled, reject
    if user.totp_enabled {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "2FA already enabled".to_string(),
            details: Some("Disable 2FA before enabling again".to_string()),
        });
    }

    // Generate 2FA setup information
    use crate::services::two_fa;
    let (secret, uri, backup_codes) = match two_fa::generate_2fa_setup(&user.email).await {
        Ok(setup) => setup,
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to generate 2FA setup".to_string(),
                details: None,
            });
        }
    };

    // Generate QR code from provisioning URI
    use crate::security::TOTPGenerator;
    let qr_code_bytes = match TOTPGenerator::generate_qr_code(&uri) {
        Ok(bytes) => bytes,
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to generate QR code".to_string(),
                details: None,
            });
        }
    };

    // Convert QR code bytes to base64 string for JSON response
    let qr_code = general_purpose::STANDARD.encode(&qr_code_bytes);

    // Create temporary session to hold the setup information
    let temp_session_id = uuid::Uuid::new_v4().to_string();
    let session_key = format!("2fa_setup:{}", temp_session_id);

    // Store setup info in Redis with 10-minute TTL
    use redis::AsyncCommands;
    let setup_data = serde_json::json!({
        "secret": secret.clone(),
        "backup_codes": backup_codes.clone(),
        "user_id": user_id.to_string(),
    })
    .to_string();

    let mut redis_conn = redis.get_ref().clone();
    if let Err(_) = redis_conn
        .set_ex::<_, _, ()>(&session_key, setup_data, 600_u64)
        .await
    {
        return HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to store temporary session".to_string(),
            details: None,
        });
    }

    HttpResponse::Ok().json(Enable2FAResponse {
        temp_session_id,
        qr_code,
        secret,
        backup_codes,
        expires_in: 600,
    })
}

/// Handle confirming 2FA setup
/// POST /auth/2fa/confirm
pub async fn confirm_2fa(
    pool: web::Data<PgPool>,
    redis: web::Data<ConnectionManager>,
    auth_user: UserId,
    req: web::Json<Confirm2FARequest>,
) -> impl Responder {
    let user_id = auth_user.0;

    // Retrieve setup info from Redis
    use redis::AsyncCommands;

    let session_key = format!("2fa_setup:{}", req.temp_session_id);
    let mut redis_conn = redis.get_ref().clone();
    let setup_data: Option<String> = match redis_conn.get(&session_key).await {
        Ok(data) => data,
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to retrieve session".to_string(),
                details: None,
            });
        }
    };

    let setup_json = match setup_data {
        Some(data) => match serde_json::from_str::<serde_json::Value>(&data) {
            Ok(json) => json,
            Err(_) => {
                return HttpResponse::BadRequest().json(ErrorResponse {
                    error: "Invalid session data".to_string(),
                    details: None,
                });
            }
        },
        None => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Session expired or invalid".to_string(),
                details: None,
            });
        }
    };

    // Extract secret and verify TOTP code
    let secret = match setup_json.get("secret").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid session data".to_string(),
                details: None,
            });
        }
    };

    use crate::security::TOTPGenerator;
    let is_valid = match TOTPGenerator::verify_totp(secret, &req.code) {
        Ok(valid) => valid,
        Err(_) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid TOTP code".to_string(),
                details: None,
            });
        }
    };

    if !is_valid {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid TOTP code".to_string(),
            details: Some("The code does not match. Please try again.".to_string()),
        });
    }

    // Enable TOTP in database
    match user_repo::enable_totp(pool.get_ref(), user_id, secret).await {
        Ok(_) => {}
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to enable 2FA".to_string(),
                details: None,
            });
        }
    };

    // Store backup codes
    use crate::services::backup_codes;
    let backup_codes_list: Vec<String> =
        match setup_json.get("backup_codes").and_then(|v| v.as_array()) {
            Some(codes) => codes
                .iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect(),
            None => {
                return HttpResponse::BadRequest().json(ErrorResponse {
                    error: "Invalid session data".to_string(),
                    details: None,
                });
            }
        };

    if let Err(_) =
        backup_codes::store_backup_codes(pool.get_ref(), user_id, &backup_codes_list).await
    {
        return HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to store backup codes".to_string(),
            details: None,
        });
    }

    // Delete temporary session
    let _ = redis_conn.del::<_, usize>(&session_key).await;

    HttpResponse::Ok().json(Confirm2FAResponse {
        message: "2FA has been successfully enabled".to_string(),
        two_fa_enabled: true,
    })
}

/// Handle verifying 2FA code during login
/// POST /auth/2fa/verify
pub async fn verify_2fa(
    pool: web::Data<PgPool>,
    redis: web::Data<ConnectionManager>,
    req: web::Json<Verify2FARequest>,
) -> impl Responder {
    // Verify temporary 2FA session
    use crate::services::two_fa;
    let user_id =
        match two_fa::verify_temp_session(redis.get_ref(), &req.session_id, "2fa_pending").await {
            Ok(id) => id,
            Err(_) => {
                return HttpResponse::BadRequest().json(ErrorResponse {
                    error: "Invalid or expired session".to_string(),
                    details: None,
                });
            }
        };

    // Verify the 2FA code (TOTP or backup code)
    let is_valid = match two_fa::verify_user_code(pool.get_ref(), user_id, &req.code).await {
        Ok(valid) => valid,
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to verify code".to_string(),
                details: None,
            });
        }
    };

    if !is_valid {
        // Record 2FA verification failure
        use crate::metrics::helpers as metrics;
        metrics::record_2fa_failure();

        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid 2FA code".to_string(),
            details: Some("The code does not match. Please try again.".to_string()),
        });
    }

    // Record 2FA verification success
    use crate::metrics::helpers as metrics;
    metrics::record_2fa_success();

    // Get user for token generation
    let user = match user_repo::find_by_id(pool.get_ref(), user_id).await {
        Ok(Some(user)) => user,
        _ => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to retrieve user".to_string(),
                details: None,
            });
        }
    };

    // Generate JWT token pair
    let tokens = match jwt::generate_token_pair(user_id, &user.email, &user.username) {
        Ok(tokens) => tokens,
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to generate tokens".to_string(),
                details: None,
            });
        }
    };

    // Record successful login
    if let Err(_) = user_repo::record_successful_login(pool.get_ref(), user_id).await {
        return HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to record login".to_string(),
            details: None,
        });
    }

    // Delete temporary session
    use redis::AsyncCommands;
    let mut redis_conn = redis.get_ref().clone();
    let _ = redis_conn
        .del::<_, usize>(format!("2fa_pending:{}", req.session_id))
        .await;

    HttpResponse::Ok().json(Verify2FAResponse {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        token_type: tokens.token_type,
        expires_in: tokens.expires_in,
    })
}
