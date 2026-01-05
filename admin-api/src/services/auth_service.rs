// Auth service - will be wired into API handlers for real authentication
#![allow(dead_code)]

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use chrono::{Duration, Utc};
use jsonwebtoken::{encode, EncodingKey, Header};
use redis::AsyncCommands;

use crate::config::Config;
use crate::db::Database;
use crate::error::{AppError, Result};
use crate::middleware::Claims;
use crate::models::Admin;

pub struct AuthService {
    db: Database,
    config: Config,
}

impl AuthService {
    pub fn new(db: Database, config: Config) -> Self {
        Self { db, config }
    }

    pub async fn authenticate(&self, email: &str, password: &str) -> Result<(Admin, String, String)> {
        // Query admin by email
        let admin: Admin = sqlx::query_as(
            "SELECT * FROM admins WHERE email = $1 AND is_active = true"
        )
        .bind(email)
        .fetch_optional(&self.db.pg)
        .await?
        .ok_or(AppError::Unauthorized)?;

        // Verify password
        self.verify_password(password, &admin.password_hash)?;

        // Generate tokens
        let access_token = self.generate_access_token(&admin)?;
        let refresh_token = self.generate_refresh_token(&admin)?;

        // Update last login time
        sqlx::query("UPDATE admins SET last_login_at = NOW() WHERE id = $1")
            .bind(admin.id)
            .execute(&self.db.pg)
            .await?;

        Ok((admin, access_token, refresh_token))
    }

    pub fn hash_password(&self, password: &str) -> Result<String> {
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();

        Ok(argon2
            .hash_password(password.as_bytes(), &salt)
            .map_err(|e| AppError::Internal(anyhow::anyhow!("Password hashing failed: {}", e)))?
            .to_string())
    }

    pub fn verify_password(&self, password: &str, hash: &str) -> Result<()> {
        let parsed_hash = PasswordHash::new(hash)
            .map_err(|e| AppError::Internal(anyhow::anyhow!("Invalid password hash: {}", e)))?;

        Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .map_err(|_| AppError::Unauthorized)
    }

    pub fn generate_access_token(&self, admin: &Admin) -> Result<String> {
        let now = Utc::now();
        let exp = now + Duration::hours(self.config.jwt.expiry_hours as i64);

        let claims = Claims {
            sub: admin.id.to_string(),
            email: admin.email.clone(),
            role: admin.role(),
            iat: now.timestamp() as usize,
            exp: exp.timestamp() as usize,
        };

        encode(
            &Header::default(),
            &claims,
            &EncodingKey::from_secret(self.config.jwt.secret.as_bytes()),
        )
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Token generation failed: {}", e)))
    }

    pub fn generate_refresh_token(&self, admin: &Admin) -> Result<String> {
        let now = Utc::now();
        let exp = now + Duration::days(30);

        let claims = Claims {
            sub: admin.id.to_string(),
            email: admin.email.clone(),
            role: admin.role(),
            iat: now.timestamp() as usize,
            exp: exp.timestamp() as usize,
        };

        encode(
            &Header::default(),
            &claims,
            &EncodingKey::from_secret(self.config.jwt.secret.as_bytes()),
        )
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Token generation failed: {}", e)))
    }

    pub async fn invalidate_token(&self, token: &str) -> Result<()> {
        let mut conn = self.db.get_redis_conn().await
            .map_err(|e| AppError::Internal(anyhow::anyhow!("Redis connection failed: {}", e)))?;

        // Add token to blacklist with TTL (30 days)
        let key = format!("token_blacklist:{}", token);
        conn.set_ex::<_, _, ()>(&key, "1", 86400 * 30)
            .await
            .map_err(|e| AppError::Internal(anyhow::anyhow!("Token invalidation failed: {}", e)))?;

        Ok(())
    }
}
