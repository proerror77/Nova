/// Phone Authentication Service
///
/// Handles SMS OTP verification for phone-based authentication.
/// Uses Redis for OTP storage and AWS SNS for SMS delivery.
///
/// Security features:
/// - Rate limiting (max 5 requests per phone per hour)
/// - OTP expiration (5 minutes)
/// - One-time verification tokens
/// - Phone number format validation (E.164)
use crate::db;
use crate::error::{IdentityError, Result};
use crate::security::{generate_token_pair, hash_password};
use aws_sdk_sns::Client as SnsClient;
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

/// Max OTP requests per phone per hour
const MAX_OTP_REQUESTS_PER_HOUR: i32 = 5;

/// Redis key prefixes
const REDIS_OTP_PREFIX: &str = "phone_otp:";
const REDIS_RATE_LIMIT_PREFIX: &str = "phone_rate:";
const REDIS_VERIFICATION_TOKEN_PREFIX: &str = "phone_verify:";

/// Phone authentication service
#[derive(Clone)]
pub struct PhoneAuthService {
    db: PgPool,
    redis: SharedConnectionManager,
    sns_client: Option<SnsClient>,
}

/// Result of phone registration
pub struct PhoneRegisterResult {
    pub user_id: Uuid,
    pub username: String,
    pub email: String,
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
    pub is_new_user: bool,
}

/// Result of phone login
pub struct PhoneLoginResult {
    pub user_id: Uuid,
    pub username: String,
    pub email: String,
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

impl PhoneAuthService {
    pub fn new(db: PgPool, redis: SharedConnectionManager, sns_client: Option<SnsClient>) -> Self {
        Self {
            db,
            redis,
            sns_client,
        }
    }

    /// Send OTP code to phone number
    ///
    /// Returns the expiration time in seconds
    pub async fn send_code(&self, phone_number: &str) -> Result<i32> {
        // Validate phone number format (E.164)
        if !Self::is_valid_e164(phone_number) {
            return Err(IdentityError::Validation(
                "Phone number must be in E.164 format (e.g., +14155551234)".to_string(),
            ));
        }

        // Check rate limit
        self.check_rate_limit(phone_number).await?;

        // Generate OTP
        let otp = self.generate_otp();

        // Store OTP in Redis with expiration
        self.store_otp(phone_number, &otp).await?;

        // Increment rate limit counter
        self.increment_rate_limit(phone_number).await?;

        // Send SMS
        self.send_sms(phone_number, &otp).await?;

        info!(
            phone = %Self::mask_phone(phone_number),
            "OTP sent successfully"
        );

        Ok(OTP_EXPIRY_SECS as i32)
    }

    /// Verify OTP code
    ///
    /// Returns a verification token that can be used for registration/login
    pub async fn verify_code(&self, phone_number: &str, code: &str) -> Result<String> {
        // Validate phone number format
        if !Self::is_valid_e164(phone_number) {
            return Err(IdentityError::Validation(
                "Phone number must be in E.164 format".to_string(),
            ));
        }

        // Validate code format
        if code.len() != OTP_LENGTH || !code.chars().all(|c| c.is_ascii_digit()) {
            return Err(IdentityError::Validation(
                "Invalid verification code format".to_string(),
            ));
        }

        // Get stored OTP
        let stored_otp = self.get_otp(phone_number).await?;

        match stored_otp {
            Some(stored) if stored == code => {
                // Delete used OTP
                self.delete_otp(phone_number).await?;

                // Generate verification token
                let token = self.generate_verification_token(phone_number).await?;

                info!(
                    phone = %Self::mask_phone(phone_number),
                    "Phone verified successfully"
                );

                Ok(token)
            }
            Some(_) => {
                warn!(
                    phone = %Self::mask_phone(phone_number),
                    "Invalid OTP code attempt"
                );
                Err(IdentityError::Validation(
                    "Invalid verification code".to_string(),
                ))
            }
            None => {
                warn!(
                    phone = %Self::mask_phone(phone_number),
                    "OTP code expired or not found"
                );
                Err(IdentityError::Validation(
                    "Verification code expired or not found".to_string(),
                ))
            }
        }
    }

    /// Register new user with verified phone number
    pub async fn register(
        &self,
        phone_number: &str,
        verification_token: &str,
        username: &str,
        password: &str,
        display_name: Option<&str>,
    ) -> Result<PhoneRegisterResult> {
        // Validate verification token
        self.validate_verification_token(phone_number, verification_token)
            .await?;

        // Validate username
        if !crate::validators::validate_username(username) {
            return Err(IdentityError::InvalidUsername(
                "Username must be 3-32 characters, alphanumeric with underscores".to_string(),
            ));
        }

        // Check if phone number already registered
        if let Some(existing) = db::users::find_by_phone(&self.db, phone_number).await? {
            return Err(IdentityError::Validation(format!(
                "Phone number already registered to user {}",
                existing.username
            )));
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

        // Create user with phone number
        let user = db::users::create_user_with_phone(
            &self.db,
            phone_number,
            username,
            &password_hash,
            display_name,
        )
        .await?;

        // Generate token pair
        let tokens = generate_token_pair(user.id, &user.email, &user.username)
            .map_err(|e| IdentityError::Internal(e.to_string()))?;

        info!(
            user_id = %user.id,
            username = %user.username,
            phone = %Self::mask_phone(phone_number),
            "User registered with phone"
        );

        Ok(PhoneRegisterResult {
            user_id: user.id,
            username: user.username,
            email: user.email,
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_in: tokens.expires_in,
            is_new_user: true,
        })
    }

    /// Login with verified phone number
    pub async fn login(
        &self,
        phone_number: &str,
        verification_token: &str,
    ) -> Result<PhoneLoginResult> {
        // Validate verification token
        self.validate_verification_token(phone_number, verification_token)
            .await?;

        // Find user by phone number
        let user = db::users::find_by_phone(&self.db, phone_number)
            .await?
            .ok_or_else(|| {
                IdentityError::Validation("No account found with this phone number".to_string())
            })?;

        // Generate token pair
        let tokens = generate_token_pair(user.id, &user.email, &user.username)
            .map_err(|e| IdentityError::Internal(e.to_string()))?;

        // Update last login
        if let Err(err) = db::users::record_successful_login(&self.db, user.id).await {
            warn!(
                user_id = %user.id,
                error = %err,
                "Failed to update last_login_at"
            );
        }

        info!(
            user_id = %user.id,
            phone = %Self::mask_phone(phone_number),
            "User logged in with phone"
        );

        Ok(PhoneLoginResult {
            user_id: user.id,
            username: user.username,
            email: user.email,
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_in: tokens.expires_in,
        })
    }

    // ========== Helper Methods ==========

    /// Validate E.164 phone number format
    fn is_valid_e164(phone: &str) -> bool {
        if !phone.starts_with('+') {
            return false;
        }
        let digits = &phone[1..];
        digits.len() >= 7 && digits.len() <= 15 && digits.chars().all(|c| c.is_ascii_digit())
    }

    /// Mask phone number for logging
    fn mask_phone(phone: &str) -> String {
        if phone.len() <= 4 {
            return "****".to_string();
        }
        let visible = &phone[phone.len() - 4..];
        format!("****{}", visible)
    }

    /// Generate random OTP code
    fn generate_otp(&self) -> String {
        let mut rng = rand::rng();
        (0..OTP_LENGTH)
            .map(|_| rng.random_range(0..10).to_string())
            .collect()
    }

    /// Store OTP in Redis
    async fn store_otp(&self, phone_number: &str, otp: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_OTP_PREFIX, phone_number);
        let mut conn = self.redis.lock().await.clone();

        redis::cmd("SETEX")
            .arg(&key)
            .arg(OTP_EXPIRY_SECS)
            .arg(otp)
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to store OTP in Redis");
                IdentityError::Internal("Failed to store OTP".to_string())
            })?;

        Ok(())
    }

    /// Get OTP from Redis
    async fn get_otp(&self, phone_number: &str) -> Result<Option<String>> {
        let key = format!("{}{}", REDIS_OTP_PREFIX, phone_number);
        let mut conn = self.redis.lock().await.clone();

        let otp: Option<String> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to get OTP from Redis");
                IdentityError::Internal("Failed to retrieve OTP".to_string())
            })?;

        Ok(otp)
    }

    /// Delete OTP from Redis
    async fn delete_otp(&self, phone_number: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_OTP_PREFIX, phone_number);
        let mut conn = self.redis.lock().await.clone();

        redis::cmd("DEL")
            .arg(&key)
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to delete OTP from Redis");
                IdentityError::Internal("Failed to delete OTP".to_string())
            })?;

        Ok(())
    }

    /// Check rate limit for phone number
    async fn check_rate_limit(&self, phone_number: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_RATE_LIMIT_PREFIX, phone_number);
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
                    phone = %Self::mask_phone(phone_number),
                    count = count,
                    "Rate limit exceeded for phone"
                );
                return Err(IdentityError::RateLimited(
                    "Too many verification code requests. Please try again later.".to_string(),
                ));
            }
        }

        Ok(())
    }

    /// Increment rate limit counter
    async fn increment_rate_limit(&self, phone_number: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_RATE_LIMIT_PREFIX, phone_number);
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
    async fn generate_verification_token(&self, phone_number: &str) -> Result<String> {
        let token = Uuid::new_v4().to_string();
        let key = format!("{}{}", REDIS_VERIFICATION_TOKEN_PREFIX, token);
        let mut conn = self.redis.lock().await.clone();

        // Store phone number with verification token
        redis::cmd("SETEX")
            .arg(&key)
            .arg(VERIFICATION_TOKEN_EXPIRY_SECS)
            .arg(phone_number)
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to store verification token");
                IdentityError::Internal("Failed to generate verification token".to_string())
            })?;

        Ok(token)
    }

    /// Validate verification token
    async fn validate_verification_token(&self, phone_number: &str, token: &str) -> Result<()> {
        let key = format!("{}{}", REDIS_VERIFICATION_TOKEN_PREFIX, token);
        let mut conn = self.redis.lock().await.clone();

        let stored_phone: Option<String> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to validate verification token");
                IdentityError::Internal("Token validation failed".to_string())
            })?;

        match stored_phone {
            Some(stored) if stored == phone_number => Ok(()),
            Some(_) => Err(IdentityError::InvalidToken),
            None => Err(IdentityError::Validation(
                "Verification token expired or invalid".to_string(),
            )),
        }
    }

    /// Send SMS via AWS SNS
    async fn send_sms(&self, phone_number: &str, otp: &str) -> Result<()> {
        let message = format!(
            "Your Nova verification code is: {}. This code expires in 5 minutes.",
            otp
        );

        match &self.sns_client {
            Some(sns) => {
                let result = sns
                    .publish()
                    .phone_number(phone_number)
                    .message(&message)
                    .message_attributes(
                        "AWS.SNS.SMS.SMSType",
                        aws_sdk_sns::types::MessageAttributeValue::builder()
                            .data_type("String")
                            .string_value("Transactional")
                            .build()
                            .map_err(|e| {
                                IdentityError::Internal(format!(
                                    "Failed to build SMS attribute: {}",
                                    e
                                ))
                            })?,
                    )
                    .send()
                    .await;

                match result {
                    Ok(output) => {
                        info!(
                            phone = %Self::mask_phone(phone_number),
                            message_id = ?output.message_id(),
                            "SMS sent successfully"
                        );
                        Ok(())
                    }
                    Err(e) => {
                        error!(
                            phone = %Self::mask_phone(phone_number),
                            error = %e,
                            "Failed to send SMS"
                        );
                        Err(IdentityError::Internal(format!(
                            "Failed to send SMS: {}",
                            e
                        )))
                    }
                }
            }
            None => {
                // Development mode: Log OTP instead of sending SMS
                warn!(
                    phone = %Self::mask_phone(phone_number),
                    otp = %otp,
                    "SMS service not configured - OTP logged for development"
                );
                Ok(())
            }
        }
    }
}
