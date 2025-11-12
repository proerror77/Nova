/// JWT Token Revocation Management
///
/// Handles real-time token blacklisting for logout and password change scenarios.
/// This module provides Redis-based token revocation for immediate invalidation.
///
/// ## Architecture
///
/// - **Redis Layer**: Immediate token invalidation (this module)
/// - **Database Layer**: Persistent revocation records (db::token_revocation)
///
/// ## Use Cases
///
/// - User logout: Revoke specific refresh token
/// - Password change: Revoke all user's tokens
/// - Security incident: Revoke all tokens for affected users
/// - Session termination: Revoke access + refresh tokens
use crate::error::{IdentityError, Result};
use redis_utils::SharedConnectionManager;
use sha2::{Digest, Sha256};

const DEFAULT_TOKEN_TTL_SECS: u64 = 3600; // 1 hour
const MIN_TOKEN_TTL_SECS: u64 = 300; // 5 minutes

/// Revoke a JWT token immediately (for logout or password change)
///
/// ## Arguments
///
/// * `redis` - Shared Redis connection manager
/// * `token` - JWT token string to revoke
/// * `expires_at_secs` - Token expiration timestamp (Unix seconds)
///
/// ## Implementation
///
/// - Hashes token with SHA-256 for storage
/// - Sets Redis key with expiration matching token's remaining TTL
/// - Prevents memory bloat by auto-expiring revoked tokens
///
/// ## Security
///
/// - Token hash prevents token leakage in Redis dumps
/// - TTL prevents unbounded growth of revocation list
pub async fn revoke_token(
    redis: &SharedConnectionManager,
    token: &str,
    expires_at_secs: Option<i64>,
) -> Result<()> {
    let token_hash = hash_token(token);
    let key = format!("nova:revoked:token:{}", token_hash);

    let now_secs = chrono::Utc::now().timestamp();
    let remaining_ttl = match expires_at_secs {
        Some(exp) if exp > now_secs => (exp - now_secs) as u64,
        Some(_) => MIN_TOKEN_TTL_SECS,
        None => DEFAULT_TOKEN_TTL_SECS,
    };

    let mut redis_conn = redis.lock().await.clone();
    redis_utils::with_timeout(async {
        redis::cmd("SET")
            .arg(&key)
            .arg("1")
            .arg("EX")
            .arg(remaining_ttl)
            .query_async::<_, ()>(&mut redis_conn)
            .await
    })
    .await
    .map_err(|e| IdentityError::Redis(e.to_string()))?;

    tracing::info!(
        "Token revoked, blacklist entry will expire in {} seconds",
        remaining_ttl
    );
    Ok(())
}

/// Revoke all tokens for a specific user
///
/// ## Use Cases
///
/// - Password change: Invalidate all sessions
/// - Account compromise: Force re-authentication
/// - Security incident: Revoke all tokens for affected users
///
/// ## Implementation
///
/// - Stores user's revocation timestamp in Redis
/// - All tokens issued before this timestamp are considered invalid
/// - Requires validation logic to check token `iat` vs revocation timestamp
///
/// ## Arguments
///
/// * `redis` - Shared Redis connection manager
/// * `user_id` - UUID of user whose tokens should be revoked
pub async fn revoke_all_user_tokens(
    redis: &SharedConnectionManager,
    user_id: uuid::Uuid,
) -> Result<()> {
    let key = format!("nova:revoked:user:{}:ts", user_id);
    let now_secs = chrono::Utc::now().timestamp();

    let mut redis_conn = redis.lock().await.clone();
    redis_utils::with_timeout(async {
        redis::cmd("SET")
            .arg(&key)
            .arg(now_secs.to_string())
            .arg("EX")
            .arg(7 * 24 * 60 * 60) // 7 days (max refresh token lifetime)
            .query_async::<_, ()>(&mut redis_conn)
            .await
    })
    .await
    .map_err(|e| IdentityError::Redis(e.to_string()))?;

    tracing::warn!("All tokens revoked for user: {}", user_id);
    Ok(())
}

/// Check if a token has been revoked
///
/// ## Arguments
///
/// * `redis` - Shared Redis connection manager
/// * `token` - JWT token string to check
///
/// ## Returns
///
/// `true` if token is in blacklist, `false` otherwise
pub async fn is_token_revoked(redis: &SharedConnectionManager, token: &str) -> Result<bool> {
    let token_hash = hash_token(token);
    let key = format!("nova:revoked:token:{}", token_hash);

    let mut redis_conn = redis.lock().await.clone();
    let exists: bool = redis_utils::with_timeout(async {
        redis::cmd("EXISTS")
            .arg(&key)
            .query_async(&mut redis_conn)
            .await
    })
    .await
    .map_err(|e| IdentityError::Redis(e.to_string()))?;

    Ok(exists)
}

/// Check if a user's tokens have been revoked after a certain timestamp
///
/// ## Usage
///
/// Call this during token validation with the token's `iat` claim.
/// Returns `true` if user revoked all tokens after this token was issued.
///
/// ## Arguments
///
/// * `redis` - Shared Redis connection manager
/// * `user_id` - User's UUID
/// * `token_issued_at_secs` - Token's `iat` claim (Unix timestamp)
///
/// ## Returns
///
/// `true` if token was issued before user's revocation timestamp
pub async fn check_user_token_revocation(
    redis: &SharedConnectionManager,
    user_id: uuid::Uuid,
    token_issued_at_secs: i64,
) -> Result<bool> {
    let key = format!("nova:revoked:user:{}:ts", user_id);

    let mut redis_conn = redis.lock().await.clone();
    let revocation_ts: Option<String> = redis_utils::with_timeout(async {
        redis::cmd("GET")
            .arg(&key)
            .query_async(&mut redis_conn)
            .await
    })
    .await
    .map_err(|e| IdentityError::Redis(e.to_string()))?;

    if let Some(ts_str) = revocation_ts {
        let revocation_secs: i64 = ts_str
            .parse()
            .map_err(|_| IdentityError::Redis("Invalid revocation timestamp".to_string()))?;
        Ok(token_issued_at_secs < revocation_secs)
    } else {
        Ok(false)
    }
}

/// Hash a token using SHA-256
///
/// ## Security
///
/// - Prevents token leakage in Redis dumps or logs
/// - One-way hash ensures original token cannot be recovered
/// - SHA-256 provides sufficient collision resistance
///
/// ## Arguments
///
/// * `token` - JWT token string
///
/// ## Returns
///
/// Hex-encoded SHA-256 hash
pub fn hash_token(token: &str) -> String {
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
        let hash1 = hash_token(token);
        let hash2 = hash_token(token);
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_sha256_hash_uniqueness() {
        let hash1 = hash_token("token1");
        let hash2 = hash_token("token2");
        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_hash_length() {
        let token = "any_token";
        let hash = hash_token(token);
        // SHA-256 produces 64 hex characters
        assert_eq!(hash.len(), 64);
    }
}
