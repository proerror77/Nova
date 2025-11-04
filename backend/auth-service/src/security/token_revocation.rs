use crate::error::{AuthError, AuthResult};
/// JWT Token Revocation Management
/// Handles token blacklisting for logout and password change scenarios
use redis::aio::ConnectionManager;
use sha2::{Digest, Sha256};

const DEFAULT_TOKEN_TTL_SECS: u64 = 3600; // 1 hour

/// Revoke a JWT token immediately (for logout or password change)
pub async fn revoke_token(
    redis: &ConnectionManager,
    token: &str,
    expires_at_secs: Option<i64>,
) -> AuthResult<()> {
    let token_hash = sha256_hash(token);
    let key = format!("nova:revoked:token:{}", token_hash);

    let now_secs = chrono::Utc::now().timestamp();
    let remaining_ttl = if let Some(exp) = expires_at_secs {
        let remaining = (exp - now_secs) as u64;
        if remaining > DEFAULT_TOKEN_TTL_SECS {
            DEFAULT_TOKEN_TTL_SECS
        } else if remaining > 0 {
            remaining
        } else {
            300 // 5 minutes for already-expired tokens
        }
    } else {
        DEFAULT_TOKEN_TTL_SECS
    };

    let mut redis = redis.clone();
    redis::cmd("SET")
        .arg(&key)
        .arg("1")
        .arg("EX")
        .arg(remaining_ttl)
        .query_async::<_, ()>(&mut redis)
        .await
        .map_err(|e| AuthError::Redis(e.to_string()))?;

    tracing::info!(
        "Token revoked, blacklist entry will expire in {} seconds",
        remaining_ttl
    );
    Ok(())
}

/// Revoke all tokens for a specific user
pub async fn revoke_all_user_tokens(
    redis: &ConnectionManager,
    user_id: uuid::Uuid,
) -> AuthResult<()> {
    let key = format!("nova:revoked:user:{}:ts", user_id);
    let now_secs = chrono::Utc::now().timestamp();

    let mut redis = redis.clone();
    redis::cmd("SET")
        .arg(&key)
        .arg(now_secs.to_string())
        .arg("EX")
        .arg(7 * 24 * 60 * 60) // 7 days
        .query_async::<_, ()>(&mut redis)
        .await
        .map_err(|e| AuthError::Redis(e.to_string()))?;

    tracing::warn!("All tokens revoked for user: {}", user_id);
    Ok(())
}

/// Check if a token has been revoked
pub async fn is_token_revoked(redis: &ConnectionManager, token: &str) -> AuthResult<bool> {
    let token_hash = sha256_hash(token);
    let key = format!("nova:revoked:token:{}", token_hash);

    let mut redis = redis.clone();
    let exists: bool = redis::cmd("EXISTS")
        .arg(&key)
        .query_async(&mut redis)
        .await
        .map_err(|e| AuthError::Redis(e.to_string()))?;

    Ok(exists)
}

/// Check if a user's tokens have been revoked after a certain timestamp
pub async fn check_user_token_revocation(
    redis: &ConnectionManager,
    user_id: uuid::Uuid,
    token_issued_at_secs: i64,
) -> AuthResult<bool> {
    let key = format!("nova:revoked:user:{}:ts", user_id);

    let mut redis = redis.clone();
    let revocation_ts: Option<String> = redis::cmd("GET")
        .arg(&key)
        .query_async(&mut redis)
        .await
        .map_err(|e| AuthError::Redis(e.to_string()))?;

    if let Some(ts_str) = revocation_ts {
        let revocation_secs: i64 = ts_str
            .parse()
            .map_err(|_| AuthError::Redis("Invalid revocation timestamp".to_string()))?;
        Ok(token_issued_at_secs < revocation_secs)
    } else {
        Ok(false)
    }
}

/// Hash a token using SHA-256
fn sha256_hash(token: &str) -> String {
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
}
