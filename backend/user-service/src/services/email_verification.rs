use anyhow::{anyhow, Result};
use rand::Rng;
/// Email verification service
/// Manages email verification tokens stored in Redis with 1-hour expiration
use redis::aio::ConnectionManager;
use std::fmt::Write as FmtWrite;
use uuid::Uuid;

use crate::utils::redis_timeout::run_with_timeout;

const VERIFICATION_TOKEN_EXPIRY_SECS: u64 = 3600; // 1 hour
const TOKEN_LENGTH: usize = 32;

/// Generate a random verification token
pub fn generate_token() -> String {
    let mut rng = rand::thread_rng();
    let random_bytes: Vec<u8> = (0..TOKEN_LENGTH).map(|_| rng.gen::<u8>()).collect();

    let mut token = String::with_capacity(TOKEN_LENGTH * 2);
    for byte in random_bytes {
        let _ = write!(token, "{:02x}", byte);
    }
    token
}

/// Store verification token in Redis linked to user
pub async fn store_verification_token(
    redis: &ConnectionManager,
    user_id: Uuid,
    email: &str,
) -> Result<String> {
    use redis::AsyncCommands;

    let token = generate_token();
    let key = format!("verify_email:{}:{}", user_id, email);
    let reverse_key = format!("verify_email_token:{}", token);
    let token_value = format!("{}:{}", user_id, email);

    let mut redis_conn = redis.clone();

    // Store forward mapping: user_id:email -> token
    let _: () = run_with_timeout(redis_conn.set_ex(&key, &token, VERIFICATION_TOKEN_EXPIRY_SECS))
        .await
        .map_err(|e| anyhow!("Failed to store verification token: {}", e))?;

    // Store reverse mapping: token -> user_id:email
    let _: () = run_with_timeout(redis_conn.set_ex(
        &reverse_key,
        &token_value,
        VERIFICATION_TOKEN_EXPIRY_SECS,
    ))
    .await
    .map_err(|e| anyhow!("Failed to store reverse verification token: {}", e))?;

    Ok(token)
}

/// Look up user information from a verification token
/// Returns (user_id, email) if token is valid
pub async fn get_user_from_token(
    redis: &ConnectionManager,
    token: &str,
) -> Result<Option<(Uuid, String)>> {
    use redis::AsyncCommands;

    let reverse_key = format!("verify_email_token:{}", token);

    let mut redis_conn = redis.clone();
    let token_value: Option<String> = run_with_timeout(redis_conn.get(&reverse_key))
        .await
        .map_err(|e| anyhow!("Failed to retrieve token mapping: {}", e))?;

    if let Some(token_value) = token_value {
        let parts: Vec<&str> = token_value.split(':').collect();
        if parts.len() == 2 {
            let user_id = Uuid::parse_str(parts[0])
                .map_err(|e| anyhow!("Invalid user ID in token: {}", e))?;
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
    use redis::AsyncCommands;

    let key = format!("verify_email:{}:{}", user_id, email);
    let reverse_key = format!("verify_email_token:{}", token);

    let mut redis_conn = redis.clone();
    let stored_token: Option<String> = run_with_timeout(redis_conn.get(&key))
        .await
        .map_err(|e| anyhow!("Failed to retrieve verification token: {}", e))?;

    if let Some(stored_token) = stored_token {
        if stored_token == token {
            // Delete both token mappings after verification (one-time use)
            let _ = run_with_timeout(redis_conn.del::<_, usize>(&key)).await;
            let _ = run_with_timeout(redis_conn.del::<_, usize>(&reverse_key)).await;
            return Ok(true);
        }
    }

    Ok(false)
}

/// Check if a verification token exists and is still valid
pub async fn token_exists(redis: &ConnectionManager, user_id: Uuid, email: &str) -> Result<bool> {
    use redis::AsyncCommands;

    let key = format!("verify_email:{}:{}", user_id, email);

    let mut redis_conn = redis.clone();
    let exists: bool = run_with_timeout(redis_conn.exists(&key))
        .await
        .map_err(|e| anyhow!("Failed to check token existence: {}", e))?;

    Ok(exists)
}

/// Revoke a verification token (e.g., for security or manual refresh)
pub async fn revoke_token(redis: &ConnectionManager, user_id: Uuid, email: &str) -> Result<()> {
    use redis::AsyncCommands;

    let key = format!("verify_email:{}:{}", user_id, email);

    let mut redis_conn = redis.clone();

    // Get the token first to delete its reverse mapping
    let token: Option<String> = run_with_timeout(redis_conn.get(&key)).await.ok().flatten();

    // Delete forward mapping
    let _: usize = run_with_timeout(redis_conn.del::<_, usize>(&key))
        .await
        .map_err(|e| anyhow!("Failed to revoke verification token: {}", e))?;

    // Delete reverse mapping if token was found
    if let Some(token) = token {
        let reverse_key = format!("verify_email_token:{}", token);
        let _ = run_with_timeout(redis_conn.del::<_, usize>(&reverse_key)).await;
    }

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
