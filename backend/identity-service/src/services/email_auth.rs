/// Email Authentication Service
///
/// Handles Email OTP verification for email-based authentication.
/// Uses Redis for OTP storage and SMTP for email delivery.
///
/// Security features:
/// - Rate limiting (max 5 requests per email per hour)
/// - OTP expiration (5 minutes)
/// - One-time verification tokens
/// - Email format validation
use crate::db;
use crate::error::{IdentityError, Result};
use crate::security::{generate_token_pair, hash_password};
use crate::services::email::EmailService;
use rand::Rng;
use redis_utils::SharedConnectionManager;
use sqlx::PgPool;
use tracing::{error, info, warn};
use uuid::Uuid;

/// OTP code length
const OTP_LENGTH: usize = 6;

/// OTP expiration time in seconds (5 minutes)
const OTP_EXPIRY_SECS: i64 = 300;

/// Verification token expiration time in seconds (10 minutes)
const VERIFICATION_TOKEN_EXPIRY_SECS: i64 = 600;

/// Max OTP requests per email per hour
const MAX_OTP_REQUESTS_PER_HOUR: i32 = 5;

/// Redis key prefixes
const REDIS_OTP_PREFIX: &str = "email_otp:";
const REDIS_RATE_LIMIT_PREFIX: &str = "email_rate:";
const REDIS_VERIFICATION_TOKEN_PREFIX: &str = "email_verify:";

/// Email authentication service
#[derive(Clone)]
pub struct EmailAuthService {
    db: PgPool,
    redis: SharedConnectionManager,
    email_service: EmailService,
}

/// Result of email registration
pub struct EmailRegisterResult {
    pub user_id: Uuid,
    pub username: String,
    pub email: String,
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
    pub is_new_user: bool,
}

/// Result of email login
pub struct EmailLoginResult {
    pub user_id: Uuid,
    pub username: String,
    pub email: String,
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

impl EmailAuthService {
    pub fn new(db: PgPool, redis: SharedConnectionManager, email_service: EmailService) -> Self {
        Self {
            db,
            redis,
            email_service,
        }
    }

    /// Send OTP code to email address
    ///
    /// Returns the expiration time in seconds
    pub async fn send_code(&self, email: &str) -> Result<i32> {
        // Validate email format
        if !Self::is_valid_email(email) {
            return Err(IdentityError::Validation(
                "Invalid email address format".to_string(),
            ));
        }

        // Check rate limit
        self.check_rate_limit(email).await?;

        // Generate OTP
        let otp = self.generate_otp();

        // Store OTP in Redis with expiration
        self.store_otp(email, &otp).await?;

        // Increment rate limit counter
        self.increment_rate_limit(email).await?;

        // Send email
        self.send_otp_email(email, &otp).await?;

        info!(
            email = %Self::mask_email(email),
            "Email OTP sent successfully"
        );

        Ok(OTP_EXPIRY_SECS as i32)
    }

    /// Verify OTP code
    ///
    /// Returns a verification token that can be used for registration/login
    pub async fn verify_code(&self, email: &str, code: &str) -> Result<String> {
        // Validate email format
        if !Self::is_valid_email(email) {
            return Err(IdentityError::Validation(
                "Invalid email address format".to_string(),
            ));
        }

        // Validate code format
        if code.len() != OTP_LENGTH || !code.chars().all(|c| c.is_ascii_digit()) {
            return Err(IdentityError::Validation(
                "Invalid verification code format".to_string(),
            ));
        }

        // Get stored OTP
        let stored_otp = self.get_otp(email).await?;

        match stored_otp {
            Some(stored) if stored == code => {
                // Delete used OTP
                self.delete_otp(email).await?;

                // Generate verification token
                let token = self.generate_verification_token(email).await?;

                info!(
                    email = %Self::mask_email(email),
                    "Email verified successfully"
                );

                Ok(token)
            }
            Some(_) => {
                warn!(
                    email = %Self::mask_email(email),
                    "Invalid OTP code attempt"
                );
                Err(IdentityError::Validation(
                    "Invalid verification code".to_string(),
                ))
            }
            None => {
                warn!(
                    email = %Self::mask_email(email),
                    "OTP code expired or not found"
                );
                Err(IdentityError::Validation(
                    "Verification code expired or not found".to_string(),
                ))
            }
        }
    }

    /// Register new user with verified email
    pub async fn register(
        &self,
        email: &str,
        verification_token: &str,
        username: &str,
        password: &str,
        display_name: Option<&str>,
        invite_code: Option<&str>,
    ) -> Result<EmailRegisterResult> {
        // Validate verification token
        self.validate_verification_token(email, verification_token)
            .await?;

        // Validate username
        if !crate::validators::validate_username(username) {
            return Err(IdentityError::InvalidUsername(
                "Username must be 3-32 characters, alphanumeric with underscores".to_string(),
            ));
        }

        // Note: Invite code validation removed for email OTP
        // Email OTP can be used without invite codes
        // If invite code support is needed, uncomment the validation below
        /*
        if let Some(code) = invite_code {
            if !code.is_empty() {
                // Validate invite code logic here
            }
        }
        */

        // Check if email already registered
        if db::users::find_by_email(&self.db, email).await?.is_some() {
            return Err(IdentityError::Validation(
                "Email address already registered".to_string(),
            ));
        }

        // Check if username already taken
        if db::users::find_by_username(&self.db, username)
            .await?
            .is_some()
        {
            return Err(IdentityError::UsernameAlreadyExists);
        }

        // Hash password
        let password_hash = hash_password(password)?;

        // Create user
        let display = display_name.unwrap_or(username);
        let user = db::users::create_user(
            &self.db,
            email,
            username,
            &password_hash,
            Some(display),
        )
        .await?;

        // Generate token pair
        let tokens =
            generate_token_pair(user.id, &user.email, &user.username, Some("primary"), None)
                .map_err(|e| IdentityError::Internal(e.to_string()))?;

        // Delete verification token to prevent reuse
        self.delete_verification_token(verification_token).await?;

        info!(
            user_id = %user.id,
            username = %user.username,
            email = %Self::mask_email(email),
            "User registered with email OTP"
        );

        Ok(EmailRegisterResult {
            user_id: user.id,
            username: user.username,
            email: user.email,
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_in: tokens.expires_in,
            is_new_user: true,
        })
    }

    /// Login with verified email
    pub async fn login(
        &self,
        email: &str,
        verification_token: &str,
    ) -> Result<EmailLoginResult> {
        // Validate verification token
        self.validate_verification_token(email, verification_token)
            .await?;

        // Find user by email
        let user = db::users::find_by_email(&self.db, email)
            .await?
            .ok_or_else(|| {
                IdentityError::Validation("No account found with this email address".to_string())
            })?;

        // Generate token pair
        let tokens =
            generate_token_pair(user.id, &user.email, &user.username, Some("primary"), None)
                .map_err(|e| IdentityError::Internal(e.to_string()))?;

        // Update last login
        if let Err(err) = db::users::record_successful_login(&self.db, user.id).await {
            warn!(
                user_id = %user.id,
                error = %err,
                "Failed to update last_login_at"
            );
        }

        // Delete verification token to prevent reuse
        self.delete_verification_token(verification_token).await?;

        info!(
            user_id = %user.id,
            email = %Self::mask_email(email),
            "User logged in with email OTP"
        );

        Ok(EmailLoginResult {
            user_id: user.id,
            username: user.username,
            email: user.email,
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_in: tokens.expires_in,
        })
    }

    // ========== Helper Methods ==========

    /// Validate email format
    fn is_valid_email(email: &str) -> bool {
        email.contains('@') && email.len() >= 5 && email.len() <= 254
    }

    /// Mask email for logging
    fn mask_email(email: &str) -> String {
        if let Some(at_pos) = email.find('@') {
            let local = &email[..at_pos];
            let domain = &email[at_pos..];
            if local.len() <= 2 {
                format!("**{}", domain)
            } else {
                format!("{}***{}", &local[..1], domain)
            }
        } else {
            "***@***".to_string()
        }
    }

    /// Generate random OTP code
    fn generate_otp(&self) -> String {
        let mut rng = rand::rng();
        (0..OTP_LENGTH)
            .map(|_| rng.random_range(0..10).to_string())
            .collect()
    }

    /// Store OTP in Redis
    async fn store_otp(&self, email: &str, otp: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_OTP_PREFIX, email.to_lowercase());
        let mut conn = self.redis.lock().await.clone();

        redis::cmd("SETEX")
            .arg(&key)
            .arg(OTP_EXPIRY_SECS)
            .arg(otp)
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to store email OTP in Redis");
                IdentityError::Internal("Failed to store OTP".to_string())
            })?;

        Ok(())
    }

    /// Get OTP from Redis
    async fn get_otp(&self, email: &str) -> Result<Option<String>> {
        let key = format!("{}{}", REDIS_OTP_PREFIX, email.to_lowercase());
        let mut conn = self.redis.lock().await.clone();

        let otp: Option<String> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to get email OTP from Redis");
                IdentityError::Internal("Failed to retrieve OTP".to_string())
            })?;

        Ok(otp)
    }

    /// Delete OTP from Redis
    async fn delete_otp(&self, email: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_OTP_PREFIX, email.to_lowercase());
        let mut conn = self.redis.lock().await.clone();

        redis::cmd("DEL")
            .arg(&key)
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to delete email OTP from Redis");
                IdentityError::Internal("Failed to delete OTP".to_string())
            })?;

        Ok(())
    }

    /// Check rate limit for email
    async fn check_rate_limit(&self, email: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_RATE_LIMIT_PREFIX, email.to_lowercase());
        let mut conn = self.redis.lock().await.clone();

        let count: Option<i32> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to check rate limit");
                IdentityError::Internal("Rate limit check failed".to_string())
            })?;

        if let Some(count) = count {
            if count >= MAX_OTP_REQUESTS_PER_HOUR {
                warn!(
                    email = %Self::mask_email(email),
                    count = count,
                    "Rate limit exceeded for email"
                );
                return Err(IdentityError::RateLimited(
                    "Too many verification code requests. Please try again later.".to_string(),
                ));
            }
        }

        Ok(())
    }

    /// Increment rate limit counter
    async fn increment_rate_limit(&self, email: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_RATE_LIMIT_PREFIX, email.to_lowercase());
        let mut conn = self.redis.lock().await.clone();

        // Use INCR with EXPIRE (1 hour)
        redis::cmd("INCR")
            .arg(&key)
            .query_async::<_, i32>(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to increment rate limit");
                IdentityError::Internal("Rate limit update failed".to_string())
            })?;

        // Set expiry if not already set
        let _: std::result::Result<i32, _> = redis::cmd("EXPIRE")
            .arg(&key)
            .arg(3600) // 1 hour
            .query_async(&mut conn)
            .await;

        Ok(())
    }

    /// Generate verification token after OTP verification
    async fn generate_verification_token(&self, email: &str) -> Result<String> {
        let token = Uuid::new_v4().to_string();
        let key = format!("{}{}", REDIS_VERIFICATION_TOKEN_PREFIX, token);
        let mut conn = self.redis.lock().await.clone();

        // Store email with verification token
        redis::cmd("SETEX")
            .arg(&key)
            .arg(VERIFICATION_TOKEN_EXPIRY_SECS)
            .arg(email.to_lowercase())
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to store verification token");
                IdentityError::Internal("Failed to generate verification token".to_string())
            })?;

        Ok(token)
    }

    /// Validate verification token
    async fn validate_verification_token(&self, email: &str, token: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_VERIFICATION_TOKEN_PREFIX, token);
        let mut conn = self.redis.lock().await.clone();

        let stored_email: Option<String> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to validate verification token");
                IdentityError::Internal("Token validation failed".to_string())
            })?;

        match stored_email {
            Some(stored) if stored.eq_ignore_ascii_case(email) => Ok(()),
            Some(_) => Err(IdentityError::InvalidToken),
            None => Err(IdentityError::Validation(
                "Verification token expired or invalid".to_string(),
            )),
        }
    }

    /// Delete verification token to prevent reuse
    async fn delete_verification_token(&self, token: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_VERIFICATION_TOKEN_PREFIX, token);
        let mut conn = self.redis.lock().await.clone();

        let _: std::result::Result<i32, _> = redis::cmd("DEL")
            .arg(&key)
            .query_async(&mut conn)
            .await;

        Ok(())
    }

    /// Send OTP email
    async fn send_otp_email(&self, email: &str, otp: &str) -> Result<()> {
        let subject = "Nova 驗證碼";
        let text_body = format!(
            "您的 Nova 驗證碼是：{}\n\n此驗證碼將在 5 分鐘後過期。\n\n如果這不是您本人的操作，請忽略此郵件。",
            otp
        );

        let html_body = format!(
            r#"<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; padding: 20px; color: #333;">
    <h2>Nova 驗證碼</h2>
    <p>您的驗證碼是：</p>
    <p style="font-size: 32px; font-weight: bold; letter-spacing: 8px; color: #000; margin: 30px 0;">{}</p>
    <p style="color: #666; font-size: 14px;">此驗證碼將在 <strong>5 分鐘</strong>後過期。</p>
    <p style="color: #999; font-size: 12px; margin-top: 30px;">
        如果這不是您本人的操作，請忽略此郵件。
    </p>
</body>
</html>"#,
            otp
        );

        self.email_service
            .send_html_email(email, subject, &html_body, &text_body)
            .await
            .map_err(|e| {
                error!(
                    email = %Self::mask_email(email),
                    error = %e,
                    "Failed to send OTP email"
                );
                IdentityError::Internal(format!("Failed to send OTP email: {}", e))
            })?;

        Ok(())
    }
}
