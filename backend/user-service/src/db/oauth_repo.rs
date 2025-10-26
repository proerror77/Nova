/// OAuth Connection repository - handles all database operations for OAuth connections
use crate::models::OAuthConnection;
use crate::services::oauth::TokenEncryptionService;
use chrono::Utc;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use tracing::{debug, error, warn};
use uuid::Uuid;

/// Hash a token for secure storage (legacy, for backward compatibility)
fn hash_token(token: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    hex::encode(hasher.finalize())
}

/// Get or create encryption service from environment
/// Returns None if OAUTH_TOKEN_ENCRYPTION_KEY is not set (development mode)
fn get_encryption_service() -> Option<TokenEncryptionService> {
    match TokenEncryptionService::from_env() {
        Ok(service) => Some(service),
        Err(e) => {
            debug!("Token encryption disabled: {}", e);
            None
        }
    }
}

/// Create a new OAuth connection with encrypted token storage
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

    // Store both hashed (legacy) and encrypted tokens
    let access_token_hash = hash_token(access_token);
    let refresh_token_hash = refresh_token.map(hash_token);

    // Try to encrypt tokens for new refresh capability
    let (access_token_encrypted, refresh_token_encrypted, tokens_encrypted) =
        match get_encryption_service() {
            Some(service) => {
                let access_enc: Option<Vec<u8>> = service.encrypt(access_token).ok();

                let refresh_enc: Option<Vec<u8>> =
                    refresh_token.and_then(|rt| service.encrypt(rt).ok());

                (access_enc, refresh_enc, true)
            }
            None => (None, None, false),
        };

    let token_expires_at_dt = token_expires_at.map(|ts| {
        chrono::DateTime::from_timestamp(ts, 0)
            .unwrap_or_else(|| chrono::DateTime::from_timestamp(0, 0).unwrap())
    });

    sqlx::query_as::<_, OAuthConnection>(
        r#"
        INSERT INTO oauth_connections (
            id, user_id, provider, provider_user_id, provider_email, display_name,
            access_token_hash, refresh_token_hash, token_expires_at,
            access_token_encrypted, refresh_token_encrypted, tokens_encrypted,
            created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
        RETURNING id, user_id, provider, provider_user_id, provider_email, display_name,
                  access_token_hash, refresh_token_hash, token_expires_at,
                  access_token_encrypted, refresh_token_encrypted, tokens_encrypted,
                  created_at, updated_at
        "#,
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
    .bind(access_token_encrypted)
    .bind(refresh_token_encrypted)
    .bind(tokens_encrypted)
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

/// Update OAuth connection tokens with encryption
pub async fn update_tokens(
    pool: &PgPool,
    connection_id: Uuid,
    access_token: &str,
    refresh_token: Option<&str>,
    token_expires_at: Option<i64>,
) -> Result<OAuthConnection, sqlx::Error> {
    let now = Utc::now();

    // Store both hashed (legacy) and encrypted tokens
    let access_token_hash = hash_token(access_token);
    let refresh_token_hash = refresh_token.map(hash_token);

    // Try to encrypt tokens
    let (access_token_encrypted, refresh_token_encrypted, tokens_encrypted) =
        match get_encryption_service() {
            Some(service) => {
                let access_enc: Option<Vec<u8>> = service.encrypt(access_token).ok();

                let refresh_enc: Option<Vec<u8>> =
                    refresh_token.and_then(|rt| service.encrypt(rt).ok());

                (access_enc, refresh_enc, true)
            }
            None => (None, None, false),
        };

    let token_expires_at_dt = token_expires_at.map(|ts| {
        chrono::DateTime::from_timestamp(ts, 0)
            .unwrap_or_else(|| chrono::DateTime::from_timestamp(0, 0).unwrap())
    });

    sqlx::query_as::<_, OAuthConnection>(
        r#"
        UPDATE oauth_connections
        SET access_token_hash = $1,
            refresh_token_hash = $2,
            token_expires_at = $3,
            access_token_encrypted = $4,
            refresh_token_encrypted = $5,
            tokens_encrypted = $6,
            last_token_refresh_attempt = $7,
            last_token_refresh_status = $8,
            updated_at = $9
        WHERE id = $10
        RETURNING id, user_id, provider, provider_user_id, provider_email, display_name,
                  access_token_hash, refresh_token_hash, token_expires_at,
                  access_token_encrypted, refresh_token_encrypted, tokens_encrypted,
                  created_at, updated_at
        "#,
    )
    .bind(access_token_hash)
    .bind(refresh_token_hash)
    .bind(token_expires_at_dt)
    .bind(access_token_encrypted)
    .bind(refresh_token_encrypted)
    .bind(tokens_encrypted)
    .bind(now)
    .bind("success")
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

/// Find OAuth connections with expiring tokens (within window_secs)
/// Returns connections that have a refresh_token and token_expires_at within the specified time window
pub async fn find_expiring_tokens(
    pool: &PgPool,
    window_secs: i64,
) -> Result<Vec<OAuthConnection>, sqlx::Error> {
    let now = Utc::now();
    let expiry_window = now + chrono::Duration::seconds(window_secs);

    sqlx::query_as::<_, OAuthConnection>(
        r#"
        SELECT id, user_id, provider, provider_user_id, provider_email, display_name, access_token_hash, refresh_token_hash, token_expires_at, created_at, updated_at
        FROM oauth_connections
        WHERE (refresh_token_hash IS NOT NULL OR refresh_token_encrypted IS NOT NULL)
          AND token_expires_at IS NOT NULL
          AND token_expires_at <= $1
          AND token_expires_at > $2
        ORDER BY token_expires_at ASC
        "#
    )
    .bind(expiry_window)
    .bind(now)
    .fetch_all(pool)
    .await
}

/// Get decrypted refresh token for token refresh job
///
/// Returns the refresh token decrypted from encrypted storage if available,
/// otherwise returns an error indicating encrypted storage is not set up.
pub async fn get_decrypted_refresh_token(
    pool: &PgPool,
    connection_id: Uuid,
) -> Result<String, String> {
    // Fetch the encrypted token from database
    let row: Option<(Option<Vec<u8>>,)> = sqlx::query_as::<_, (Option<Vec<u8>>,)>(
        "SELECT refresh_token_encrypted FROM oauth_connections WHERE id = $1",
    )
    .bind(connection_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| format!("Database error: {}", e))?;

    let (encrypted_opt,) = row.ok_or_else(|| "Connection not found".to_string())?;

    let encrypted_bytes = encrypted_opt.ok_or_else(|| {
        "Refresh token not encrypted - automatic refresh not available. \
         Please set OAUTH_TOKEN_ENCRYPTION_KEY environment variable."
            .to_string()
    })?;

    // Decrypt with encryption service
    let service = get_encryption_service().ok_or_else(|| {
        "Token encryption service not configured. \
         Please set OAUTH_TOKEN_ENCRYPTION_KEY environment variable."
            .to_string()
    })?;

    service
        .decrypt(&encrypted_bytes)
        .map_err(|e| format!("Failed to decrypt refresh token: {}", e))
}

/// Get decrypted access token
///
/// Returns the access token decrypted from encrypted storage if available.
pub async fn get_decrypted_access_token(
    pool: &PgPool,
    connection_id: Uuid,
) -> Result<String, String> {
    let row: Option<(Option<Vec<u8>>,)> = sqlx::query_as::<_, (Option<Vec<u8>>,)>(
        "SELECT access_token_encrypted FROM oauth_connections WHERE id = $1",
    )
    .bind(connection_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| format!("Database error: {}", e))?;

    let (encrypted_opt,) = row.ok_or_else(|| "Connection not found".to_string())?;

    let encrypted_bytes = encrypted_opt.ok_or_else(|| "Access token not encrypted".to_string())?;

    let service = get_encryption_service()
        .ok_or_else(|| "Token encryption service not configured".to_string())?;

    service
        .decrypt(&encrypted_bytes)
        .map_err(|e| format!("Failed to decrypt access token: {}", e))
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
