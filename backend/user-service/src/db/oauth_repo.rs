/// OAuth Connection repository - handles all database operations for OAuth connections
use crate::models::OAuthConnection;
use chrono::Utc;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

/// Hash a token for secure storage
fn hash_token(token: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    hex::encode(hasher.finalize())
}

/// Create a new OAuth connection
pub async fn create_connection(
    pool: &PgPool,
    user_id: Uuid,
    provider: &str,
    provider_user_id: &str,
    provider_email: &str,
    display_name: Option<&str>,
    access_token: &str,
    refresh_token: Option<&str>,
    token_expires_at: Option<i64>,
) -> Result<OAuthConnection, sqlx::Error> {
    let id = Uuid::new_v4();
    let now = Utc::now();

    let access_token_hash = hash_token(access_token);
    let refresh_token_hash = refresh_token.map(hash_token);
    let token_expires_at_dt = token_expires_at.map(|ts| {
        chrono::DateTime::from_timestamp(ts, 0)
            .unwrap_or_else(|| chrono::DateTime::from_timestamp(0, 0).unwrap())
    });

    sqlx::query_as::<_, OAuthConnection>(
        r#"
        INSERT INTO oauth_connections (id, user_id, provider, provider_user_id, provider_email, display_name, access_token_hash, refresh_token_hash, token_expires_at, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        RETURNING id, user_id, provider, provider_user_id, provider_email, display_name, access_token_hash, refresh_token_hash, token_expires_at, created_at, updated_at
        "#
    )
    .bind(id)
    .bind(user_id)
    .bind(provider)
    .bind(provider_user_id)
    .bind(provider_email)
    .bind(display_name)
    .bind(access_token_hash)
    .bind(refresh_token_hash)
    .bind(token_expires_at_dt)
    .bind(now)
    .bind(now)
    .fetch_one(pool)
    .await
}

/// Find OAuth connection by provider and provider user ID
pub async fn find_by_provider(
    pool: &PgPool,
    provider: &str,
    provider_user_id: &str,
) -> Result<Option<OAuthConnection>, sqlx::Error> {
    sqlx::query_as::<_, OAuthConnection>(
        r#"
        SELECT id, user_id, provider, provider_user_id, provider_email, display_name, access_token_hash, refresh_token_hash, token_expires_at, created_at, updated_at
        FROM oauth_connections
        WHERE provider = $1 AND provider_user_id = $2
        "#
    )
    .bind(provider)
    .bind(provider_user_id)
    .fetch_optional(pool)
    .await
}

/// Find all OAuth connections for a user
pub async fn find_by_user(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Vec<OAuthConnection>, sqlx::Error> {
    sqlx::query_as::<_, OAuthConnection>(
        r#"
        SELECT id, user_id, provider, provider_user_id, provider_email, display_name, access_token_hash, refresh_token_hash, token_expires_at, created_at, updated_at
        FROM oauth_connections
        WHERE user_id = $1
        ORDER BY created_at DESC
        "#
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
}

/// Update OAuth connection tokens
pub async fn update_tokens(
    pool: &PgPool,
    connection_id: Uuid,
    access_token: &str,
    refresh_token: Option<&str>,
    token_expires_at: Option<i64>,
) -> Result<OAuthConnection, sqlx::Error> {
    let now = Utc::now();
    let access_token_hash = hash_token(access_token);
    let refresh_token_hash = refresh_token.map(hash_token);
    let token_expires_at_dt = token_expires_at.map(|ts| {
        chrono::DateTime::from_timestamp(ts, 0)
            .unwrap_or_else(|| chrono::DateTime::from_timestamp(0, 0).unwrap())
    });

    sqlx::query_as::<_, OAuthConnection>(
        r#"
        UPDATE oauth_connections
        SET access_token_hash = $1, refresh_token_hash = $2, token_expires_at = $3, updated_at = $4
        WHERE id = $5
        RETURNING id, user_id, provider, provider_user_id, provider_email, display_name, access_token_hash, refresh_token_hash, token_expires_at, created_at, updated_at
        "#
    )
    .bind(access_token_hash)
    .bind(refresh_token_hash)
    .bind(token_expires_at_dt)
    .bind(now)
    .bind(connection_id)
    .fetch_one(pool)
    .await
}

/// Delete an OAuth connection
pub async fn delete_connection(pool: &PgPool, connection_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM oauth_connections WHERE id = $1")
        .bind(connection_id)
        .execute(pool)
        .await?;

    Ok(())
}

/// Check if provider connection exists for user
pub async fn provider_exists_for_user(
    pool: &PgPool,
    user_id: Uuid,
    provider: &str,
) -> Result<bool, sqlx::Error> {
    let result = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(SELECT 1 FROM oauth_connections WHERE user_id = $1 AND provider = $2)
        "#,
    )
    .bind(user_id)
    .bind(provider)
    .fetch_one(pool)
    .await?;

    Ok(result)
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_hash_token() {
        use super::*;
        let token = "test_token_12345";
        let hash1 = hash_token(token);
        let hash2 = hash_token(token);

        // Same token should produce same hash
        assert_eq!(hash1, hash2);

        // Hash should be hex-encoded SHA256
        assert_eq!(hash1.len(), 64); // SHA256 = 32 bytes = 64 hex chars
    }

    #[test]
    fn test_oauth_repository_compile() {
        // Ensures the module compiles correctly
        assert!(true);
    }
}
