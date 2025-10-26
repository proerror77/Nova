/// OAuth State Manager - Redis-backed state parameter storage for CSRF protection
///
/// This module implements secure state parameter management for OAuth 2.0
/// as specified in RFC 6749 Section 10.12.
///
/// State parameters are:
/// - Cryptographically random (72 characters of UUID hashes)
/// - Stored in Redis with TTL (10 minutes)
/// - Single-use (deleted after validation)
/// - Provider-specific (validated against claimed provider)
/// - PKCE-aware (stores code_challenge and method if provided)
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

/// OAuth state parameter with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthState {
    pub state_token: String,
    pub provider: String,
    #[serde(default)]
    pub code_challenge: Option<String>,
    #[serde(default)]
    pub code_challenge_method: Option<String>,
    pub created_at: i64, // Unix timestamp
    pub expires_at: i64, // Unix timestamp
}

/// OAuth state manager statistics
#[derive(Debug, Clone, Default)]
pub struct OAuthStateStats {
    pub total_states_created: u64,
    pub total_states_validated: u64,
    pub total_states_consumed: u64,
    pub total_states_expired: u64,
    pub current_active_states: usize,
}

/// Manages OAuth state tokens in Redis
pub struct OAuthStateManager {
    redis_client: Arc<redis::Client>,
    state_ttl_seconds: usize,
    key_prefix: String,
}

impl OAuthStateManager {
    /// Create a new OAuth state manager
    pub fn new(redis_client: redis::Client) -> Self {
        Self {
            redis_client: Arc::new(redis_client),
            state_ttl_seconds: 600, // 10 minutes
            key_prefix: "oauth:state:".to_string(),
        }
    }

    /// Create a new state with optional PKCE parameters
    pub async fn create_state(
        &self,
        provider: &str,
        code_challenge: Option<String>,
        code_challenge_method: Option<String>,
    ) -> Result<OAuthState, redis::RedisError> {
        // Generate cryptographically random 72-character state token
        let token_part1 = Uuid::new_v4().to_string().replace("-", "");
        let token_part2 = Uuid::new_v4().to_string().replace("-", "");
        let state_token = format!("{}{}", token_part1, token_part2);

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let state = OAuthState {
            state_token: state_token.clone(),
            provider: provider.to_string(),
            code_challenge: code_challenge.clone(),
            code_challenge_method: code_challenge_method.clone(),
            created_at: now,
            expires_at: now + self.state_ttl_seconds as i64,
        };

        // Serialize and store in Redis with TTL
        let json = serde_json::to_string(&state).map_err(|e| {
            redis::RedisError::from(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("Failed to serialize OAuth state: {}", e),
            ))
        })?;

        let key = format!("{}{}", self.key_prefix, state_token);

        let mut conn = self.redis_client.get_multiplexed_async_connection().await?;
        conn.set_ex(&key, &json, self.state_ttl_seconds as u64)
            .await?;

        debug!(
            "Created OAuth state for provider={}, expires_in={}s",
            provider, self.state_ttl_seconds
        );

        Ok(state)
    }

    /// Validate and retrieve a state token
    pub async fn validate_state(
        &self,
        state_token: &str,
        expected_provider: Option<&str>,
    ) -> Result<Option<OAuthState>, redis::RedisError> {
        if state_token.is_empty() {
            warn!("Empty state token provided");
            return Ok(None);
        }

        let key = format!("{}{}", self.key_prefix, state_token);

        let mut conn = self.redis_client.get_multiplexed_async_connection().await?;
        let json: Option<String> = conn.get(&key).await?;

        match json {
            Some(json_str) => {
                let state: OAuthState = serde_json::from_str(&json_str).map_err(|e| {
                    redis::RedisError::from(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!("Failed to deserialize OAuth state: {}", e),
                    ))
                })?;

                // Verify provider if specified
                if let Some(provider) = expected_provider {
                    if state.provider != provider {
                        warn!(
                            "State provider mismatch: expected={}, got={}",
                            provider, state.provider
                        );
                        return Ok(None);
                    }
                }

                // Check expiration
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_secs() as i64)
                    .unwrap_or(0);

                if now > state.expires_at {
                    warn!("State token has expired");
                    return Ok(None);
                }

                debug!(
                    "Validated OAuth state for provider={}, age={}s",
                    state.provider,
                    now - state.created_at
                );

                Ok(Some(state))
            }
            None => {
                warn!("State token not found in Redis");
                Ok(None)
            }
        }
    }

    /// Consume (delete) a state token (single-use enforcement)
    pub async fn consume_state(&self, state_token: &str) -> Result<bool, redis::RedisError> {
        let key = format!("{}{}", self.key_prefix, state_token);

        let mut conn = self.redis_client.get_multiplexed_async_connection().await?;
        let deleted: u32 = conn.del(&key).await?;

        if deleted > 0 {
            debug!("Consumed OAuth state token");
            Ok(true)
        } else {
            warn!("State token not found for consumption");
            Ok(false)
        }
    }

    /// Clean up expired state tokens
    /// This is typically run as a background job
    pub async fn cleanup_expired(&self) -> Result<u32, redis::RedisError> {
        // Use Redis SCAN to find all state keys and check expiration
        let mut conn = self.redis_client.get_multiplexed_async_connection().await?;

        let keys: Vec<String> = conn.keys(&format!("{}*", self.key_prefix)).await?;

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let mut expired_count = 0;

        for key in keys {
            let json: Option<String> = conn.get(&key).await?;
            if let Some(json_str) = json {
                if let Ok(state) = serde_json::from_str::<OAuthState>(&json_str) {
                    if now > state.expires_at {
                        let deleted: u32 = conn.del(&key).await?;
                        if deleted > 0 {
                            expired_count += 1;
                        }
                    }
                }
            }
        }

        if expired_count > 0 {
            debug!("Cleaned up {} expired OAuth state tokens", expired_count);
        }

        Ok(expired_count)
    }

    /// Get statistics about current state tokens
    pub async fn get_stats(&self) -> Result<OAuthStateStats, redis::RedisError> {
        let mut conn = self.redis_client.get_multiplexed_async_connection().await?;

        let keys: Vec<String> = conn.keys(&format!("{}*", self.key_prefix)).await?;

        let stats = OAuthStateStats {
            total_states_created: 0,   // Would need separate tracking
            total_states_validated: 0, // Would need separate tracking
            total_states_consumed: 0,  // Would need separate tracking
            total_states_expired: 0,   // Would need separate tracking
            current_active_states: keys.len(),
        };

        Ok(stats)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_oauth_state_creation() {
        let state = OAuthState {
            state_token: "test_token_123".to_string(),
            provider: "google".to_string(),
            code_challenge: Some("challenge_123".to_string()),
            code_challenge_method: Some("S256".to_string()),
            created_at: 1000,
            expires_at: 2000,
        };

        assert_eq!(state.provider, "google");
        assert_eq!(state.code_challenge, Some("challenge_123".to_string()));
    }

    #[test]
    fn test_oauth_state_serialization() {
        let state = OAuthState {
            state_token: "test_token".to_string(),
            provider: "apple".to_string(),
            code_challenge: None,
            code_challenge_method: None,
            created_at: 1000,
            expires_at: 2000,
        };

        let json = serde_json::to_string(&state).unwrap();
        let deserialized: OAuthState = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.state_token, state.state_token);
        assert_eq!(deserialized.provider, state.provider);
    }

    #[test]
    fn test_oauth_state_stats_default() {
        let stats = OAuthStateStats::default();
        assert_eq!(stats.total_states_created, 0);
        assert_eq!(stats.current_active_states, 0);
    }
}
