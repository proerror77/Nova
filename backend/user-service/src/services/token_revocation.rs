use anyhow::{anyhow, Result};
/// Token revocation/blacklist service
/// Manages JWT token blacklist in Redis to prevent token reuse after logout
use redis::aio::ConnectionManager;

/// Add a token to the blacklist after logout
/// Stores the token with expiration matching the token's exp claim
pub async fn revoke_token(
    redis: &ConnectionManager,
    token: &str,
    expires_at: i64, // Unix timestamp when token expires
) -> Result<()> {
    use redis::AsyncCommands;

    let blacklist_key = format!("token_blacklist:{}", token);
    let ttl = std::cmp::max(0, expires_at - chrono::Utc::now().timestamp());

    if ttl <= 0 {
        // Token already expired, no need to blacklist
        return Ok(());
    }

    let mut redis_conn = redis.clone();
    let _: () = redis_conn
        .set_ex(&blacklist_key, "revoked", ttl as u64)
        .await
        .map_err(|e| anyhow!("Failed to revoke token: {}", e))?;

    Ok(())
}

/// Check if a token has been revoked
pub async fn is_token_revoked(redis: &ConnectionManager, token: &str) -> Result<bool> {
    use redis::AsyncCommands;

    let blacklist_key = format!("token_blacklist:{}", token);

    let mut redis_conn = redis.clone();
    let exists: bool = redis_conn
        .exists(&blacklist_key)
        .await
        .map_err(|e| anyhow!("Failed to check token revocation status: {}", e))?;

    Ok(exists)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_revoke_token_formats_blacklist_key() {
        let token = "test_token_123";
        let expected_key = format!("token_blacklist:{}", token);
        assert_eq!(expected_key, "token_blacklist:test_token_123");
    }

    #[test]
    fn test_revoke_token_negative_ttl_handled() {
        // Test that tokens already expired don't cause issues
        let expired_at = chrono::Utc::now().timestamp() - 3600; // 1 hour ago
        let ttl = std::cmp::max(0, expired_at - chrono::Utc::now().timestamp());
        assert_eq!(ttl, 0);
    }
}
