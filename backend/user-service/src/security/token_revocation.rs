/// JWT Token Revocation Management
///
/// CRITICAL FIX: Implement token revocation to prevent stolen tokens from being used
/// After logout or password change, tokens must be blacklisted immediately.
use redis::aio::ConnectionManager;
use std::fmt;
use tracing::error;

/// JWT Revocation Error Types
#[derive(Debug)]
pub enum RevocationError {
    RedisError(redis::RedisError),
    InvalidToken,
    SerializationError(String),
}

impl fmt::Display for RevocationError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            RevocationError::RedisError(e) => write!(f, "Redis error: {}", e),
            RevocationError::InvalidToken => write!(f, "Invalid token"),
            RevocationError::SerializationError(e) => write!(f, "Serialization error: {}", e),
        }
    }
}

impl From<redis::RedisError> for RevocationError {
    fn from(e: redis::RedisError) -> Self {
        RevocationError::RedisError(e)
    }
}

/// Default token TTL: 1 hour (3600 seconds)
/// Tokens are automatically revoked after this duration
const DEFAULT_TOKEN_TTL_SECS: u64 = 3600;

/// Revoke a JWT token immediately (for logout, password change, etc)
///
/// This adds the token to a blacklist in Redis, preventing it from being used
/// even though it may not be naturally expired yet.
pub async fn revoke_token(
    redis: &ConnectionManager,
    token: &str,
    expires_at_secs: Option<i64>,
) -> Result<(), RevocationError> {
    // Create a hashed version of the token for storage (don't store raw token)
    let token_hash = sha256_hash(token);
    let key = format!("nova:revoked:token:{}", token_hash);

    // Calculate remaining TTL based on expiration time
    let now_secs = chrono::Utc::now().timestamp();
    let remaining_ttl = if let Some(exp) = expires_at_secs {
        // Calculate remaining time until expiration
        let remaining = (exp - now_secs) as u64;
        // Cap at max TTL of 1 hour (if token expires after 1 hour, wait 1 hour)
        if remaining > DEFAULT_TOKEN_TTL_SECS {
            DEFAULT_TOKEN_TTL_SECS
        } else if remaining > 0 {
            remaining
        } else {
            // Token already expired, but still blacklist for a short time in case of clock skew
            300 // 5 minutes
        }
    } else {
        DEFAULT_TOKEN_TTL_SECS
    };

    let mut redis = redis.clone();
    redis::cmd("SET")
        .arg(&key)
        .arg("1") // Just store a marker value
        .arg("EX")
        .arg(remaining_ttl)
        .query_async::<_, ()>(&mut redis)
        .await?;

    tracing::info!(
        "Token revoked, blacklist entry will expire in {} seconds",
        remaining_ttl
    );
    Ok(())
}

/// Revoke all tokens for a specific user
/// Useful for account lockdown after compromise
pub async fn revoke_all_user_tokens(
    redis: &ConnectionManager,
    user_id: uuid::Uuid,
) -> Result<(), RevocationError> {
    // Create a user token revocation marker
    // Any token issued before this timestamp is invalid
    let key = format!("nova:revoked:user:{}:ts", user_id);
    let now_secs = chrono::Utc::now().timestamp();

    let mut redis = redis.clone();
    redis::cmd("SET")
        .arg(&key)
        .arg(now_secs.to_string())
        // Keep this for 7 days (after which old tokens will be naturally expired anyway)
        .arg("EX")
        .arg(7 * 24 * 60 * 60)
        .query_async::<_, ()>(&mut redis)
        .await?;

    tracing::warn!("All tokens revoked for user: {}", user_id);
    Ok(())
}

/// Check if a token has been revoked
///
/// Returns true if token is revoked, false if it's still valid
pub async fn is_token_revoked(
    redis: &ConnectionManager,
    token: &str,
) -> Result<bool, RevocationError> {
    let token_hash = sha256_hash(token);
    let key = format!("nova:revoked:token:{}", token_hash);

    let mut redis = redis.clone();
    let exists: bool = redis::cmd("EXISTS")
        .arg(&key)
        .query_async::<_, bool>(&mut redis)
        .await?;

    Ok(exists)
}

/// Check if a user's tokens have been revoked after a certain timestamp
///
/// This is used when verifying JWT claims - if the token's issued_at is before
/// the revocation timestamp, the token is considered revoked
pub async fn check_user_token_revocation(
    redis: &ConnectionManager,
    user_id: uuid::Uuid,
    token_issued_at_secs: i64,
) -> Result<bool, RevocationError> {
    let key = format!("nova:revoked:user:{}:ts", user_id);

    let mut redis = redis.clone();
    let revocation_ts: Option<String> = redis::cmd("GET")
        .arg(&key)
        .query_async::<_, Option<String>>(&mut redis)
        .await?;

    if let Some(ts_str) = revocation_ts {
        match ts_str.parse::<i64>() {
            Ok(revocation_secs) => {
                // If token was issued before the revocation, it's revoked
                let is_revoked = token_issued_at_secs < revocation_secs;
                return Ok(is_revoked);
            }
            Err(e) => {
                error!(
                    "Failed to parse revocation timestamp for user {}: {}",
                    user_id, e
                );
                return Err(RevocationError::SerializationError(e.to_string()));
            }
        }
    }

    Ok(false)
}

/// Hash a token using SHA-256
/// We don't store raw tokens in Redis for security
fn sha256_hash(token: &str) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sha256_hash_consistency() {
        let token = "test_token_12345";
        let hash1 = sha256_hash(token);
        let hash2 = sha256_hash(token);
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_sha256_hash_uniqueness() {
        let hash1 = sha256_hash("token1");
        let hash2 = sha256_hash("token2");
        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_token_ttl_constants() {
        assert_eq!(DEFAULT_TOKEN_TTL_SECS, 3600); // 1 hour
    }
}
