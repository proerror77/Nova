/// Password reset database operations
use crate::error::{IdentityError, Result};
use chrono::{DateTime, Duration, Utc};
use rand::{distributions::Alphanumeric, Rng};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

/// Default token expiration time in hours
const TOKEN_EXPIRY_HOURS: i64 = 1;

/// Token length (before hashing)
const TOKEN_LENGTH: usize = 32;

/// Result of creating a password reset token
#[derive(Debug)]
pub struct CreateTokenResult {
    /// The raw token (to be sent to user via email)
    pub token: String,
    /// Token expiration time
    pub expires_at: DateTime<Utc>,
}

/// Generate a secure random token
fn generate_token() -> String {
    rand::rng()
        .sample_iter(&Alphanumeric)
        .take(TOKEN_LENGTH)
        .map(char::from)
        .collect()
}

/// Hash a token using SHA-256
fn hash_token(token: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    hex::encode(hasher.finalize())
}

/// Create a new password reset token for a user
///
/// This function:
/// 1. Invalidates any existing unused tokens for the user
/// 2. Creates a new token with expiration
/// 3. Returns the raw token (to be sent via email)
pub async fn create_reset_token(
    pool: &PgPool,
    user_id: Uuid,
    _ip_address: Option<&str>,
) -> Result<CreateTokenResult> {
    // Invalidate existing unused tokens for this user
    invalidate_user_tokens(pool, user_id).await?;

    // Generate new token
    let raw_token = generate_token();
    let token_hash = hash_token(&raw_token);
    let expires_at = Utc::now() + Duration::hours(TOKEN_EXPIRY_HOURS);
    let id = Uuid::new_v4();

    sqlx::query(
        r#"
        INSERT INTO password_resets (id, user_id, token_hash, expires_at)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind(id)
    .bind(user_id)
    .bind(&token_hash)
    .bind(expires_at)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(CreateTokenResult {
        token: raw_token,
        expires_at,
    })
}

/// Validate a password reset token and return the associated user ID
///
/// Returns `Some(user_id)` if the token is valid, `None` if invalid or expired
pub async fn validate_reset_token(pool: &PgPool, token: &str) -> Result<Option<Uuid>> {
    let token_hash = hash_token(token);

    let result = sqlx::query_as::<_, (Uuid,)>(
        r#"
        SELECT user_id FROM password_resets
        WHERE token_hash = $1
          AND is_used = FALSE
          AND expires_at > NOW()
        "#,
    )
    .bind(&token_hash)
    .fetch_optional(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(result.map(|(user_id,)| user_id))
}

/// Mark a password reset token as used
///
/// This should be called after the password has been successfully reset
pub async fn mark_token_used(pool: &PgPool, token: &str) -> Result<bool> {
    let token_hash = hash_token(token);

    let result = sqlx::query(
        r#"
        UPDATE password_resets
        SET is_used = TRUE, used_at = NOW()
        WHERE token_hash = $1
          AND is_used = FALSE
          AND expires_at > NOW()
        "#,
    )
    .bind(&token_hash)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(result.rows_affected() > 0)
}

/// Invalidate all unused tokens for a user
///
/// Used when creating a new token or when user changes password
pub async fn invalidate_user_tokens(pool: &PgPool, user_id: Uuid) -> Result<u64> {
    let result = sqlx::query(
        r#"
        UPDATE password_resets
        SET is_used = TRUE, used_at = NOW()
        WHERE user_id = $1
          AND is_used = FALSE
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(result.rows_affected())
}

/// Check if user has a recent reset request (rate limiting)
///
/// Returns true if user requested a reset within the specified minutes
pub async fn has_recent_request(pool: &PgPool, user_id: Uuid, within_minutes: i64) -> Result<bool> {
    let threshold = Utc::now() - Duration::minutes(within_minutes);

    let count = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM password_resets
        WHERE user_id = $1
          AND created_at > $2
        "#,
    )
    .bind(user_id)
    .bind(threshold)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(count > 0)
}

/// Cleanup expired and used tokens (maintenance operation)
///
/// Removes tokens that are:
/// - Expired for more than 24 hours
/// - Used for more than 24 hours
pub async fn cleanup_old_tokens(pool: &PgPool) -> Result<u64> {
    let threshold = Utc::now() - Duration::hours(24);

    let result = sqlx::query(
        r#"
        DELETE FROM password_resets
        WHERE (expires_at < $1)
           OR (is_used = TRUE AND used_at < $1)
        "#,
    )
    .bind(threshold)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(result.rows_affected())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_token() {
        let token = generate_token();
        assert_eq!(token.len(), TOKEN_LENGTH);
        assert!(token.chars().all(|c| c.is_alphanumeric()));
    }

    #[test]
    fn test_hash_token() {
        let token = "test_token_123";
        let hash1 = hash_token(token);
        let hash2 = hash_token(token);

        // Same input should produce same hash
        assert_eq!(hash1, hash2);

        // Hash should be 64 characters (SHA-256 hex)
        assert_eq!(hash1.len(), 64);

        // Different input should produce different hash
        let hash3 = hash_token("different_token");
        assert_ne!(hash1, hash3);
    }
}
