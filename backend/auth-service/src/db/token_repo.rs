use crate::error::Result;
use crate::models::RefreshToken;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn create_refresh_token(
    pool: &PgPool,
    user_id: Uuid,
    token_hash: &str,
    expires_at: DateTime<Utc>,
    ip_address: Option<String>,
    user_agent: Option<String>,
) -> Result<RefreshToken> {
    let token = sqlx::query_as::<_, RefreshToken>(
        r#"
        INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, is_revoked, ip_address, user_agent, created_at)
        VALUES (gen_random_uuid(), $1, $2, $3, false, $4, $5, CURRENT_TIMESTAMP)
        RETURNING *
        "#,
    )
    .bind(user_id)
    .bind(token_hash)
    .bind(expires_at)
    .bind(ip_address)
    .bind(user_agent)
    .fetch_one(pool)
    .await?;

    Ok(token)
}

pub async fn get_refresh_token(pool: &PgPool, token_hash: &str) -> Result<RefreshToken> {
    let token = sqlx::query_as::<_, RefreshToken>(
        r#"
        SELECT * FROM refresh_tokens WHERE token_hash = $1 AND is_revoked = false AND expires_at > CURRENT_TIMESTAMP
        "#,
    )
    .bind(token_hash)
    .fetch_one(pool)
    .await?;

    Ok(token)
}

pub async fn revoke_refresh_token(pool: &PgPool, token_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE refresh_tokens SET is_revoked = true, revoked_at = CURRENT_TIMESTAMP WHERE id = $1
        "#,
    )
    .bind(token_id)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn revoke_user_tokens(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE refresh_tokens SET is_revoked = true, revoked_at = CURRENT_TIMESTAMP WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}
