use anyhow::Result;
/// Email verification service
/// Manages email verification tokens stored in Redis with 1-hour expiration
use redis::aio::ConnectionManager;
use uuid::Uuid;
use crate::security::generate_token;
use crate::redis::{operations::*, keys::EmailVerificationKey};

const VERIFICATION_TOKEN_EXPIRY_SECS: u64 = 3600; // 1 hour

/// Store verification token in Redis linked to user
pub async fn store_verification_token(
    redis: &ConnectionManager,
    user_id: Uuid,
    email: &str,
) -> Result<String> {
    let token = generate_token();
    let token_value = format!("{}:{}", user_id, email);

    // Store forward mapping: user_id:email -> token
    redis_set_ex(
        redis,
        &EmailVerificationKey::forward(user_id, email),
        &token,
        VERIFICATION_TOKEN_EXPIRY_SECS,
    )
    .await?;

    // Store reverse mapping: token -> user_id:email
    redis_set_ex(
        redis,
        &EmailVerificationKey::reverse(&token),
        &token_value,
        VERIFICATION_TOKEN_EXPIRY_SECS,
    )
    .await?;

    Ok(token)
}

/// Look up user information from a verification token
/// Returns (user_id, email) if token is valid
pub async fn get_user_from_token(
    redis: &ConnectionManager,
    token: &str,
) -> Result<Option<(Uuid, String)>> {
    let token_value = redis_get(redis, &EmailVerificationKey::reverse(token)).await?;

    if let Some(token_value) = token_value {
        let parts: Vec<&str> = token_value.split(':').collect();
        if parts.len() == 2 {
            let user_id = Uuid::parse_str(parts[0])
                .map_err(|e| anyhow::anyhow!("Invalid user ID in token: {}", e))?;
            let email = parts[1].to_string();
            return Ok(Some((user_id, email)));
        }
    }

    Ok(None)
}

/// Verify that a token is valid and belongs to the user
pub async fn verify_token(
    redis: &ConnectionManager,
    user_id: Uuid,
    email: &str,
    token: &str,
) -> Result<bool> {
    let forward_key = EmailVerificationKey::forward(user_id, email);
    let reverse_key = EmailVerificationKey::reverse(token);

    let stored_token = redis_get(redis, &forward_key).await?;

    if let Some(stored_token) = stored_token {
        if stored_token == token {
            // Delete both token mappings after verification (one-time use)
            let _ = redis_delete(redis, &forward_key).await;
            let _ = redis_delete(redis, &reverse_key).await;
            return Ok(true);
        }
    }

    Ok(false)
}

/// Check if a verification token exists and is still valid
pub async fn token_exists(redis: &ConnectionManager, user_id: Uuid, email: &str) -> Result<bool> {
    redis_exists(redis, &EmailVerificationKey::forward(user_id, email)).await
}

/// Revoke a verification token (e.g., for security or manual refresh)
pub async fn revoke_token(redis: &ConnectionManager, user_id: Uuid, email: &str) -> Result<()> {
    let forward_key = EmailVerificationKey::forward(user_id, email);

    // Get the token first to delete its reverse mapping
    if let Ok(Some(token)) = redis_get(redis, &forward_key).await {
        let _ = redis_delete(redis, &EmailVerificationKey::reverse(&token)).await;
    }

    // Delete forward mapping
    redis_delete(redis, &forward_key).await?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_token_creates_valid_length() {
        let token = generate_token();
        assert_eq!(token.len(), TOKEN_LENGTH * 2); // Each byte = 2 hex chars
    }

    #[test]
    fn test_generate_token_uniqueness() {
        let token1 = generate_token();
        let token2 = generate_token();
        assert_ne!(token1, token2);
    }

    #[test]
    fn test_generate_token_is_random() {
        let tokens: Vec<String> = (0..10).map(|_| generate_token()).collect();
        let unique_tokens: std::collections::HashSet<_> = tokens.iter().collect();
        assert_eq!(unique_tokens.len(), tokens.len());
    }

    #[test]
    fn test_token_format_is_hex() {
        let token = generate_token();
        for c in token.chars() {
            assert!(
                c.is_ascii_hexdigit(),
                "Token contains non-hex character: {}",
                c
            );
        }
    }
}
