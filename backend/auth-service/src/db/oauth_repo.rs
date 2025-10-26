use crate::error::Result;
use crate::models::OAuthConnection;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn create_oauth_connection(
    pool: &PgPool,
    user_id: Uuid,
    provider: &str,
    provider_user_id: &str,
    provider_email: Option<String>,
    display_name: Option<String>,
    access_token_hash: &str,
    refresh_token_hash: Option<String>,
    token_expires_at: Option<DateTime<Utc>>,
) -> Result<OAuthConnection> {
    let connection = sqlx::query_as::<_, OAuthConnection>(
        r#"
        INSERT INTO oauth_connections (id, user_id, provider, provider_user_id, provider_email, display_name, access_token_hash, refresh_token_hash, token_expires_at, created_at, updated_at)
        VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        RETURNING *
        "#,
    )
    .bind(user_id)
    .bind(provider)
    .bind(provider_user_id)
    .bind(provider_email)
    .bind(display_name)
    .bind(access_token_hash)
    .bind(refresh_token_hash)
    .bind(token_expires_at)
    .fetch_one(pool)
    .await?;

    Ok(connection)
}

pub async fn get_oauth_connection(
    pool: &PgPool,
    provider: &str,
    provider_user_id: &str,
) -> Result<OAuthConnection> {
    let connection = sqlx::query_as::<_, OAuthConnection>(
        r#"
        SELECT * FROM oauth_connections WHERE provider = $1 AND provider_user_id = $2
        "#,
    )
    .bind(provider)
    .bind(provider_user_id)
    .fetch_one(pool)
    .await?;

    Ok(connection)
}

pub async fn get_user_oauth_connections(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Vec<OAuthConnection>> {
    let connections = sqlx::query_as::<_, OAuthConnection>(
        r#"
        SELECT * FROM oauth_connections WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(connections)
}

pub async fn update_oauth_tokens(
    pool: &PgPool,
    connection_id: Uuid,
    access_token_hash: &str,
    refresh_token_hash: Option<String>,
    token_expires_at: Option<DateTime<Utc>>,
) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE oauth_connections SET access_token_hash = $1, refresh_token_hash = $2, token_expires_at = $3, updated_at = CURRENT_TIMESTAMP WHERE id = $4
        "#,
    )
    .bind(access_token_hash)
    .bind(refresh_token_hash)
    .bind(token_expires_at)
    .bind(connection_id)
    .execute(pool)
    .await?;

    Ok(())
}
