use crate::db;
use crate::error::{AuthError, Result};
use crate::models::{AuthResponse, JwtClaims, TokenRefreshResponse};
use chrono::Utc;
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::PgPool;
use uuid::Uuid;

pub struct AuthService {
    db: PgPool,
    jwt_secret: String,
}

impl AuthService {
    pub fn new(db: PgPool, jwt_secret: String) -> Self {
        Self { db, jwt_secret }
    }

    pub async fn register(
        &self,
        email: &str,
        username: &str,
        password: &str,
    ) -> Result<()> {
        // Hash password
        let password_hash = bcrypt::hash(password, 12)
            .map_err(|_| AuthError::Internal("Failed to hash password".to_string()))?;

        // Create user
        let _user = db::user_repo::create_user(&self.db, email, username, &password_hash).await?;

        tracing::info!("User registered: {}", email);
        Ok(())
    }

    pub async fn login(&self, email: &str, password: &str) -> Result<AuthResponse> {
        // Get user
        let user = db::user_repo::get_user_by_email(&self.db, email).await?;

        // Check if account is locked
        if let Some(locked_until) = user.locked_until {
            if Utc::now() < locked_until {
                return Err(AuthError::Internal("Account is locked".to_string()));
            }
        }

        // Verify password
        let valid = bcrypt::verify(password, &user.password_hash)
            .map_err(|_| AuthError::InvalidCredentials)?;

        if !valid {
            db::user_repo::increment_failed_attempts(&self.db, user.id).await?;
            return Err(AuthError::InvalidCredentials);
        }

        // Reset failed attempts
        db::user_repo::reset_failed_attempts(&self.db, user.id).await?;

        // Update last login
        db::user_repo::update_last_login(&self.db, user.id).await?;

        // Generate tokens
        let access_token = self.generate_access_token(&user.id, &user.email)?;
        let refresh_token = self.generate_refresh_token(&user.id)?;

        // Save refresh token
        let token_hash = sha256(&refresh_token);
        let expires_at = Utc::now() + chrono::Duration::days(7);
        db::token_repo::create_refresh_token(
            &self.db,
            user.id,
            &token_hash,
            expires_at,
            None,
            None,
        )
        .await?;

        tracing::info!("User logged in: {}", email);

        Ok(AuthResponse {
            user_id: user.id.to_string(),
            email: user.email,
            access_token,
            refresh_token,
            expires_in: 900, // 15 minutes
        })
    }

    pub async fn verify_email(&self, user_id: Uuid, token: &str) -> Result<()> {
        let token_hash = sha256(token);

        // Verify token
        let verification = db::email_verification_repo::get_email_verification(&self.db, &token_hash)
            .await?;

        if verification.user_id != user_id {
            return Err(AuthError::VerificationFailed);
        }

        // Mark email as verified
        db::user_repo::verify_user_email(&self.db, user_id).await?;
        db::email_verification_repo::mark_email_verified(&self.db, verification.id).await?;

        tracing::info!("Email verified for user: {}", user_id);
        Ok(())
    }

    pub async fn refresh_token(&self, refresh_token: &str) -> Result<TokenRefreshResponse> {
        let token_hash = sha256(refresh_token);

        // Get refresh token
        let token = db::token_repo::get_refresh_token(&self.db, &token_hash).await?;

        // Get user
        let user = db::user_repo::get_user_by_id(&self.db, token.user_id).await?;

        // Generate new access token
        let access_token = self.generate_access_token(&user.id, &user.email)?;
        let new_refresh_token = self.generate_refresh_token(&user.id)?;

        // Save new refresh token
        let new_token_hash = sha256(&new_refresh_token);
        let expires_at = Utc::now() + chrono::Duration::days(7);
        db::token_repo::create_refresh_token(
            &self.db,
            user.id,
            &new_token_hash,
            expires_at,
            None,
            None,
        )
        .await?;

        // Revoke old token
        db::token_repo::revoke_refresh_token(&self.db, token.id).await?;

        tracing::info!("Token refreshed for user: {}", user.id);

        Ok(TokenRefreshResponse {
            access_token,
            refresh_token: new_refresh_token,
            expires_in: 900,
        })
    }

    pub async fn logout(&self, user_id: Uuid) -> Result<()> {
        db::token_repo::revoke_user_tokens(&self.db, user_id).await?;
        tracing::info!("User logged out: {}", user_id);
        Ok(())
    }

    fn generate_access_token(&self, user_id: &Uuid, email: &str) -> Result<String> {
        let now = Utc::now();
        let claims = JwtClaims {
            sub: user_id.to_string(),
            email: email.to_string(),
            iat: now.timestamp(),
            exp: (now + chrono::Duration::minutes(15)).timestamp(),
            jti: Uuid::new_v4().to_string(),
        };

        let token = encode(
            &Header::default(),
            &claims,
            &EncodingKey::from_secret(self.jwt_secret.as_bytes()),
        )
        .map_err(|_| AuthError::Internal("Failed to generate token".to_string()))?;

        Ok(token)
    }

    fn generate_refresh_token(&self, _user_id: &Uuid) -> Result<String> {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        let bytes: Vec<u8> = (0..32).map(|_| rng.gen()).collect();
        Ok(hex::encode(bytes))
    }
}

fn sha256(input: &str) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    input.hash(&mut hasher);
    format!("{:x}", hasher.finish())
}
