/// Password reset token repository - handles database operations for password reset tokens
use crate::models::PasswordReset;
use chrono::{Duration, Utc};
use sqlx::PgPool;
use uuid::Uuid;

const TOKEN_EXPIRY_HOURS: i64 = 1;

/// Create a new password reset token
pub async fn create_token(
    pool: &PgPool,
    user_id: Uuid,
    token_hash: &str,
    ip_address: Option<String>,
) -> Result<PasswordReset, sqlx::Error> {
    let id = Uuid::new_v4();
    let now = Utc::now();
    let expires_at = now + Duration::hours(TOKEN_EXPIRY_HOURS);

    sqlx::query_as::<_, PasswordReset>(
        r#"
        INSERT INTO password_resets (id, user_id, token_hash, expires_at, is_used, ip_address, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, user_id, token_hash, expires_at, is_used, used_at, ip_address, created_at
        "#
    )
    .bind(id)
    .bind(user_id)
    .bind(token_hash)
    .bind(expires_at)
    .bind(false)
    .bind(ip_address)
    .bind(now)
    .fetch_one(pool)
    .await
}

/// Find a password reset token by token hash
pub async fn find_by_token(
    pool: &PgPool,
    token_hash: &str,
) -> Result<Option<PasswordReset>, sqlx::Error> {
    sqlx::query_as::<_, PasswordReset>(
        r#"
        SELECT id, user_id, token_hash, expires_at, is_used, used_at, ip_address, created_at
        FROM password_resets
        WHERE token_hash = $1
        "#,
    )
    .bind(token_hash)
    .fetch_optional(pool)
    .await
}

/// Mark a password reset token as used
pub async fn mark_as_used(pool: &PgPool, token_id: Uuid) -> Result<PasswordReset, sqlx::Error> {
    let now = Utc::now();

    sqlx::query_as::<_, PasswordReset>(
        r#"
        UPDATE password_resets
        SET is_used = true, used_at = $1
        WHERE id = $2
        RETURNING id, user_id, token_hash, expires_at, is_used, used_at, ip_address, created_at
        "#,
    )
    .bind(now)
    .bind(token_id)
    .fetch_one(pool)
    .await
}

/// Delete all unused password reset tokens for a specific user
/// This is useful when a password reset is successful
pub async fn delete_user_tokens(pool: &PgPool, user_id: Uuid) -> Result<u64, sqlx::Error> {
    let result = sqlx::query(
        r#"
        DELETE FROM password_resets
        WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(result.rows_affected())
}

/// Clean up expired password reset tokens
/// Should be called periodically (e.g., via cron job or background task)
pub async fn cleanup_expired_tokens(pool: &PgPool) -> Result<u64, sqlx::Error> {
    let now = Utc::now();

    let result = sqlx::query(
        r#"
        DELETE FROM password_resets
        WHERE expires_at < $1 OR is_used = true
        "#,
    )
    .bind(now)
    .execute(pool)
    .await?;

    Ok(result.rows_affected())
}

/// Check if a token is valid (exists, not used, not expired)
pub async fn is_token_valid(pool: &PgPool, token_hash: &str) -> Result<bool, sqlx::Error> {
    let now = Utc::now();

    let count: i64 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*) FROM password_resets
        WHERE token_hash = $1 AND is_used = false AND expires_at > $2
        "#,
    )
    .bind(token_hash)
    .bind(now)
    .fetch_one(pool)
    .await?;

    Ok(count > 0)
}

#[cfg(test)]
mod tests {
    // Database tests require a test database setup
    #[test]
    fn test_password_reset_repo_compile() {
        assert!(true);
    }
}
