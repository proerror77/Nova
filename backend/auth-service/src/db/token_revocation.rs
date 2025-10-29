/// Token revocation database operations
use crate::error::AuthResult;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

/// Record a revoked token in the blacklist
pub async fn revoke_token(
    pool: &PgPool,
    token_hash: &str,
    jti: &str,
    revocation_reason: &str,
    expires_at: DateTime<Utc>,
) -> AuthResult<()> {
    let now = Utc::now();
    let revocation_id = Uuid::new_v4();

    sqlx::query(
        r#"
        INSERT INTO token_revocations (id, token_hash, jti, revocation_reason, expires_at, created_at)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (token_hash) DO UPDATE SET
            revocation_reason = $4,
            expires_at = $5,
            created_at = $6
        "#,
    )
    .bind(revocation_id)
    .bind(token_hash)
    .bind(jti)
    .bind(revocation_reason)
    .bind(expires_at)
    .bind(now)
    .execute(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(())
}

/// Check if a token is revoked
pub async fn is_token_revoked(pool: &PgPool, token_hash: &str) -> AuthResult<bool> {
    let result = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM token_revocations
        WHERE token_hash = $1 AND expires_at > NOW()
        "#,
    )
    .bind(token_hash)
    .fetch_one(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(result > 0)
}

/// Check if a token (by JTI) is revoked
pub async fn is_jti_revoked(pool: &PgPool, jti: &str) -> AuthResult<bool> {
    let result = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM token_revocations
        WHERE jti = $1 AND expires_at > NOW()
        "#,
    )
    .bind(jti)
    .fetch_one(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(result > 0)
}

/// Delete expired revocation records (maintenance operation)
pub async fn cleanup_expired_revocations(pool: &PgPool) -> AuthResult<u64> {
    let result = sqlx::query(
        r#"
        DELETE FROM token_revocations
        WHERE expires_at < NOW()
        "#,
    )
    .execute(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(result.rows_affected())
}

/// Get the count of active revocation records
pub async fn count_active_revocations(pool: &PgPool) -> AuthResult<i64> {
    let count = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM token_revocations
        WHERE expires_at > NOW()
        "#,
    )
    .fetch_one(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(count)
}
