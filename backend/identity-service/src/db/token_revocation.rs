/// Token revocation database operations
use crate::error::{IdentityError, Result};
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

/// Record a revoked token in the blacklist (persistent store)
#[allow(clippy::too_many_arguments)]
pub async fn revoke_token(
    pool: &PgPool,
    user_id: Uuid,
    token_hash: &str,
    token_type: &str,
    jti: Option<&str>,
    reason: Option<&str>,
    expires_at: DateTime<Utc>,
) -> Result<()> {
    let now = Utc::now();
    let revocation_id = Uuid::new_v4();

    sqlx::query(
        r#"
        INSERT INTO token_revocation (id, user_id, token_hash, token_type, jti, reason, expires_at, revoked_at, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)
        ON CONFLICT (token_hash) DO UPDATE SET
            token_type = EXCLUDED.token_type,
            jti = EXCLUDED.jti,
            reason = EXCLUDED.reason,
            expires_at = EXCLUDED.expires_at,
            revoked_at = EXCLUDED.revoked_at
        "#,
    )
    .bind(revocation_id)
    .bind(user_id)
    .bind(token_hash)
    .bind(token_type)
    .bind(jti)
    .bind(reason)
    .bind(expires_at)
    .bind(now)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(())
}

/// Check if a token is revoked
pub async fn is_token_revoked(pool: &PgPool, token_hash: &str) -> Result<bool> {
    let result = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM token_revocation
        WHERE token_hash = $1 AND expires_at > NOW()
        "#,
    )
    .bind(token_hash)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(result > 0)
}

/// Check if a token (by JTI) is revoked
pub async fn is_jti_revoked(pool: &PgPool, jti: &str) -> Result<bool> {
    let result = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM token_revocation
        WHERE jti = $1 AND expires_at > NOW()
        "#,
    )
    .bind(jti)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(result > 0)
}

/// Delete expired revocation records (maintenance operation)
pub async fn cleanup_expired_revocations(pool: &PgPool) -> Result<u64> {
    let result = sqlx::query(
        r#"
        DELETE FROM token_revocation
        WHERE expires_at < NOW()
        "#,
    )
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(result.rows_affected())
}

/// Get the count of active revocation records
pub async fn count_active_revocations(pool: &PgPool) -> Result<i64> {
    let count = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM token_revocation
        WHERE expires_at > NOW()
        "#,
    )
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(count)
}
