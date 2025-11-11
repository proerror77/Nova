//! Token blacklist for JWT revocation using Redis
//!
//! Prevents replay attacks by blacklisting revoked tokens until expiration

use anyhow::{Context, Result};
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use tracing::{error, info};

/// Token blacklist manager using Redis
pub struct TokenBlacklist {
    redis: ConnectionManager,
}

impl TokenBlacklist {
    pub fn new(redis: ConnectionManager) -> Self {
        Self { redis }
    }

    /// Add token to blacklist with TTL matching token expiration
    ///
    /// **Key format**: `token:blacklist:{jti}`
    /// **TTL**: Seconds until token expires (no need to store after expiration)
    pub async fn add_to_blacklist(&self, token: &str, jti: &str, ttl_seconds: usize) -> Result<()> {
        let key = format!("token:blacklist:{}", jti);
        let mut conn = self.redis.clone();

        conn.set_ex(&key, token, ttl_seconds)
            .await
            .context("Failed to add token to blacklist in Redis")?;

        info!(jti = %jti, ttl = ttl_seconds, "Token added to blacklist");
        Ok(())
    }

    /// Check if token is blacklisted
    pub async fn is_blacklisted(&self, token: &str) -> Result<bool> {
        // Extract JTI from token (quick parse without full validation)
        let jti = extract_jti_from_token(token)?;
        let key = format!("token:blacklist:{}", jti);

        let mut conn = self.redis.clone();
        let exists: bool = conn
            .exists(&key)
            .await
            .context("Failed to check token blacklist in Redis")?;

        Ok(exists)
    }

    /// Remove token from blacklist (rare - usually expires naturally)
    pub async fn remove_from_blacklist(&self, jti: &str) -> Result<()> {
        let key = format!("token:blacklist:{}", jti);
        let mut conn = self.redis.clone();

        let _: () = conn
            .del(&key)
            .await
            .context("Failed to remove token from blacklist in Redis")?;

        info!(jti = %jti, "Token removed from blacklist");
        Ok(())
    }

    /// Clear all blacklisted tokens (admin operation)
    pub async fn clear_all(&self) -> Result<()> {
        let mut conn = self.redis.clone();
        let keys: Vec<String> = conn
            .keys("token:blacklist:*")
            .await
            .context("Failed to list blacklist keys")?;

        if !keys.is_empty() {
            let _: () = conn
                .del(&keys)
                .await
                .context("Failed to clear blacklist")?;
            info!(count = keys.len(), "Cleared all blacklisted tokens");
        }

        Ok(())
    }
}

/// Extract JTI from JWT token without full validation
///
/// Parses only the payload section to extract jti claim
fn extract_jti_from_token(token: &str) -> Result<String> {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 {
        return Err(anyhow::anyhow!("Invalid JWT format"));
    }

    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    let payload = URL_SAFE_NO_PAD
        .decode(parts[1])
        .context("Failed to decode JWT payload")?;

    let claims: serde_json::Value =
        serde_json::from_slice(&payload).context("Failed to parse JWT claims")?;

    claims
        .get("jti")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| anyhow::anyhow!("Missing jti in token"))
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn setup_test_blacklist() -> Option<TokenBlacklist> {
        match crate::test_utils::get_test_redis_connection().await {
            Ok(manager) => Some(TokenBlacklist::new(manager)),
            Err(e) => {
                eprintln!("Skipping test - Redis not available: {}", e);
                None
            }
        }
    }

    #[tokio::test]
    async fn test_add_and_check_blacklist() {
        let Some(blacklist) = setup_test_blacklist().await else {
            eprintln!("Test skipped: Redis not available");
            return;
        };

        let jti = "test-jti-12345";
        let token = "fake.token.here";

        // Add to blacklist
        blacklist
            .add_to_blacklist(token, jti, 60)
            .await
            .unwrap();

        // Check if blacklisted (using real token with jti)
        // Note: In real usage, token would be parsed to extract jti
        // For testing, we'll check the key directly
        let mut conn = blacklist.redis.clone();
        let exists: bool = conn
            .exists(format!("token:blacklist:{}", jti))
            .await
            .unwrap();
        assert!(exists);
    }

    #[tokio::test]
    async fn test_remove_from_blacklist() {
        let Some(blacklist) = setup_test_blacklist().await else {
            eprintln!("Test skipped: Redis not available");
            return;
        };

        let jti = "test-jti-67890";
        let token = "fake.token.here";

        // Add and then remove
        blacklist
            .add_to_blacklist(token, jti, 60)
            .await
            .unwrap();
        blacklist.remove_from_blacklist(jti).await.unwrap();

        // Check if removed
        let mut conn = blacklist.redis.clone();
        let exists: bool = conn
            .exists(format!("token:blacklist:{}", jti))
            .await
            .unwrap();
        assert!(!exists);
    }

    #[test]
    fn test_extract_jti_from_token() {
        // Valid JWT with jti claim
        let token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwianRpIjoiYWJjZGVmZ2gifQ.signature";
        let jti = extract_jti_from_token(token).unwrap();
        assert_eq!(jti, "abcdefgh");
    }

    #[test]
    fn test_extract_jti_invalid_format() {
        let invalid_token = "not.a.valid.jwt.format";
        assert!(extract_jti_from_token(invalid_token).is_err());
    }
}
