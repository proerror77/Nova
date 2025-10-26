use crate::error::Result;
use crate::models::Session;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn create_session(
    pool: &PgPool,
    user_id: Uuid,
    access_token_hash: &str,
    expires_at: DateTime<Utc>,
    ip_address: Option<String>,
    user_agent: Option<String>,
) -> Result<Session> {
    let session = sqlx::query_as::<_, Session>(
        r#"
        INSERT INTO sessions (id, user_id, access_token_hash, expires_at, ip_address, user_agent, created_at)
        VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, CURRENT_TIMESTAMP)
        RETURNING *
        "#,
    )
    .bind(user_id)
    .bind(access_token_hash)
    .bind(expires_at)
    .bind(ip_address)
    .bind(user_agent)
    .fetch_one(pool)
    .await?;

    Ok(session)
}

pub async fn get_session(pool: &PgPool, session_id: Uuid) -> Result<Session> {
    let session = sqlx::query_as::<_, Session>(
        r#"
        SELECT * FROM sessions WHERE id = $1 AND expires_at > CURRENT_TIMESTAMP
        "#,
    )
    .bind(session_id)
    .fetch_one(pool)
    .await?;

    Ok(session)
}

pub async fn delete_session(pool: &PgPool, session_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        DELETE FROM sessions WHERE id = $1
        "#,
    )
    .bind(session_id)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn delete_user_sessions(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        DELETE FROM sessions WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}
