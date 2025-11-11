/// OAuth database operations
use crate::error::AuthResult;
use crate::models::OAuthConnection;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

/// Find OAuth connection by provider and provider user ID
pub async fn find_by_provider(
    pool: &PgPool,
    provider: &str,
    provider_user_id: &str,
) -> AuthResult<Option<OAuthConnection>> {
    let connection = sqlx::query_as::<_, OAuthConnection>(
        "SELECT * FROM oauth_connections WHERE provider = $1 AND provider_user_id = $2",
    )
    .bind(provider)
    .bind(provider_user_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(connection)
}

/// Find all OAuth connections for a user
pub async fn find_by_user_id(pool: &PgPool, user_id: Uuid) -> AuthResult<Vec<OAuthConnection>> {
    let connections = sqlx::query_as::<_, OAuthConnection>(
        "SELECT * FROM oauth_connections WHERE user_id = $1 ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(connections)
}

/// Create OAuth connection
pub async fn create_connection(
    pool: &PgPool,
    user_id: Uuid,
    provider: &str,
    provider_user_id: &str,
    email: Option<&str>,
    name: Option<&str>,
    picture_url: Option<&str>,
    access_token_encrypted: Option<&str>,
    refresh_token_encrypted: Option<&str>,
    token_type: Option<&str>,
    expires_at: Option<DateTime<Utc>>,
    scopes: Option<&str>,
) -> AuthResult<OAuthConnection> {
    let connection = sqlx::query_as::<_, OAuthConnection>(
        r#"
        INSERT INTO oauth_connections
        (id, user_id, provider, provider_user_id, email, name, picture_url,
         access_token_encrypted, refresh_token_encrypted, token_type, expires_at, scopes, created_at, updated_at)
        VALUES (uuid_generate_v4(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        RETURNING *
        "#
    )
    .bind(user_id)
    .bind(provider)
    .bind(provider_user_id)
    .bind(email)
    .bind(name)
    .bind(picture_url)
    .bind(access_token_encrypted)
    .bind(refresh_token_encrypted)
    .bind(token_type)
    .bind(expires_at)
    .bind(scopes)
    .fetch_one(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(connection)
}

/// Update OAuth tokens for a connection
pub async fn update_tokens(
    pool: &PgPool,
    connection_id: Uuid,
    access_token_encrypted: &str,
    refresh_token_encrypted: Option<&str>,
    token_type: Option<&str>,
    expires_at: Option<DateTime<Utc>>,
) -> AuthResult<()> {
    sqlx::query(
        r#"
        UPDATE oauth_connections
        SET access_token_encrypted = $1,
            refresh_token_encrypted = COALESCE($2, refresh_token_encrypted),
            token_type = COALESCE($3, token_type),
            expires_at = COALESCE($4, expires_at),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = $5
        "#,
    )
    .bind(access_token_encrypted)
    .bind(refresh_token_encrypted)
    .bind(token_type)
    .bind(expires_at)
    .bind(connection_id)
    .execute(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(())
}

/// Delete OAuth connection
pub async fn delete_connection(pool: &PgPool, connection_id: Uuid) -> AuthResult<()> {
    sqlx::query("DELETE FROM oauth_connections WHERE id = $1")
        .bind(connection_id)
        .execute(pool)
        .await
        .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(())
}

/// Check if user has OAuth connection for provider
pub async fn has_provider_connection(
    pool: &PgPool,
    user_id: Uuid,
    provider: &str,
) -> AuthResult<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM oauth_connections WHERE user_id = $1 AND provider = $2)",
    )
    .bind(user_id)
    .bind(provider)
    .fetch_one(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(exists)
}
