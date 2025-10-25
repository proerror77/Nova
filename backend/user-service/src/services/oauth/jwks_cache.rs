/// JWKS (JSON Web Key Set) Caching Service
///
/// Caches public keys from OAuth providers (Google, Apple) to optimize
/// ID token validation. This avoids repeated HTTP calls to provider endpoints.
///
/// Keys are cached with a TTL (typically 24 hours) and automatically
/// refreshed when expired.

use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, error, warn};

/// JWKS Key Structure (subset of RFC 7517)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JWKSKey {
    pub kty: String, // Key type (e.g., "RSA")
    pub use_: Option<String>, // Key usage (e.g., "sig")
    pub alg: Option<String>, // Algorithm
    pub kid: String, // Key ID
    pub n: Option<String>, // RSA modulus (public component)
    pub e: Option<String>, // RSA exponent (public component)
    pub x5c: Option<Vec<String>>, // X.509 certificate chain
    pub x5t: Option<String>, // X.509 certificate SHA-1 thumbprint
    pub x5t_s256: Option<String>, // X.509 certificate SHA-256 thumbprint
}

/// Complete JWKS response from provider
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JWKS {
    pub keys: Vec<JWKSKey>,
}

/// JWKS Cache Entry with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
struct JWKSCacheEntry {
    jwks: JWKS,
    cached_at: i64, // Unix timestamp
    expires_at: i64, // Unix timestamp
}

/// JWKS Cache Manager
pub struct JWKSCache {
    redis_client: Arc<redis::Client>,
    cache_ttl_seconds: usize,
    provider_cache_prefix: String,
}

impl JWKSCache {
    /// Create a new JWKS cache manager
    pub fn new(redis_client: redis::Client) -> Self {
        Self {
            redis_client: Arc::new(redis_client),
            cache_ttl_seconds: 86400, // 24 hours default
            provider_cache_prefix: "oauth:jwks:".to_string(),
        }
    }

    /// Get cached JWKS for a provider
    pub async fn get_cached_jwks(&self, provider: &str) -> Result<Option<JWKS>, String> {
        let key = format!("{}{}", self.provider_cache_prefix, provider);

        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| format!("Redis connection error: {}", e))?;

        let cached_json: Option<String> = conn
            .get(&key)
            .await
            .map_err(|e| format!("Redis GET error: {}", e))?;

        match cached_json {
            Some(json) => {
                let entry: JWKSCacheEntry = serde_json::from_str(&json)
                    .map_err(|e| format!("Failed to deserialize JWKS cache: {}", e))?;

                // Check if cache has expired
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_secs() as i64)
                    .unwrap_or(0);

                if now > entry.expires_at {
                    debug!("JWKS cache expired for provider: {}", provider);
                    // Delete expired entry
                    let _: () = conn
                        .del(&key)
                        .await
                        .map_err(|e| format!("Failed to delete expired cache: {}", e))?;
                    return Ok(None);
                }

                debug!("Using cached JWKS for provider: {}", provider);
                Ok(Some(entry.jwks))
            }
            None => {
                debug!("No cached JWKS found for provider: {}", provider);
                Ok(None)
            }
        }
    }

    /// Cache JWKS for a provider
    pub async fn cache_jwks(&self, provider: &str, jwks: &JWKS) -> Result<(), String> {
        let key = format!("{}{}", self.provider_cache_prefix, provider);

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let cache_entry = JWKSCacheEntry {
            jwks: jwks.clone(),
            cached_at: now,
            expires_at: now + self.cache_ttl_seconds as i64,
        };

        let json = serde_json::to_string(&cache_entry)
            .map_err(|e| format!("Failed to serialize JWKS cache: {}", e))?;

        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| format!("Redis connection error: {}", e))?;

        conn.set_ex(&key, &json, self.cache_ttl_seconds as u64)
            .await
            .map_err(|e| format!("Failed to cache JWKS: {}", e))?;

        debug!("Cached JWKS for provider: {} (TTL: {}s)", provider, self.cache_ttl_seconds);
        Ok(())
    }

    /// Get JWKS from provider with caching
    pub async fn get_jwks(
        &self,
        provider: &str,
        fetch_fn: impl std::future::Future<Output = Result<JWKS, String>>,
    ) -> Result<JWKS, String> {
        // Try to get from cache first
        if let Ok(Some(cached)) = self.get_cached_jwks(provider).await {
            return Ok(cached);
        }

        // Fetch from provider if not cached
        debug!("Fetching JWKS for provider: {} from remote source", provider);
        let jwks = fetch_fn.await?;

        // Cache the result
        if let Err(e) = self.cache_jwks(provider, &jwks).await {
            warn!("Failed to cache JWKS for {}: {}", provider, e);
            // Continue anyway - missing cache is not fatal
        }

        Ok(jwks)
    }

    /// Clear cache for a provider
    pub async fn clear_cache(&self, provider: &str) -> Result<(), String> {
        let key = format!("{}{}", self.provider_cache_prefix, provider);

        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| format!("Redis connection error: {}", e))?;

        conn.del(&key)
            .await
            .map_err(|e| format!("Failed to clear JWKS cache: {}", e))?;

        debug!("Cleared JWKS cache for provider: {}", provider);
        Ok(())
    }

    /// Clear all JWKS caches
    pub async fn clear_all_caches(&self) -> Result<u32, String> {
        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| format!("Redis connection error: {}", e))?;

        let pattern = format!("{}*", self.provider_cache_prefix);
        let keys: Vec<String> = conn
            .keys(&pattern)
            .await
            .map_err(|e| format!("Failed to find cache keys: {}", e))?;

        let count = keys.len() as u32;

        if count > 0 {
            let _: () = conn
                .del(keys)
                .await
                .map_err(|e| format!("Failed to delete caches: {}", e))?;

            debug!("Cleared {} JWKS cache entries", count);
        }

        Ok(count)
    }

    /// Get cache statistics
    pub async fn get_cache_stats(&self) -> Result<JWKSCacheStats, String> {
        let mut conn = self.redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| format!("Redis connection error: {}", e))?;

        let pattern = format!("{}*", self.provider_cache_prefix);
        let keys: Vec<String> = conn
            .keys(&pattern)
            .await
            .map_err(|e| format!("Failed to find cache keys: {}", e))?;

        let mut cached_providers = vec![];
        let mut expired_entries = 0;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        for key in keys {
            let json: Option<String> = conn
                .get(&key)
                .await
                .unwrap_or(None);

            if let Some(json_str) = json {
                if let Ok(entry) = serde_json::from_str::<JWKSCacheEntry>(&json_str) {
                    let provider = key.strip_prefix(&self.provider_cache_prefix)
                        .unwrap_or("unknown")
                        .to_string();

                    if now > entry.expires_at {
                        expired_entries += 1;
                    } else {
                        cached_providers.push(provider);
                    }
                }
            }
        }

        let cached_count = cached_providers.len();

        Ok(JWKSCacheStats {
            cached_providers,
            expired_entries,
            total_cached: (cached_count + expired_entries as usize) as u32,
            cache_ttl_seconds: self.cache_ttl_seconds,
        })
    }
}

/// JWKS Cache Statistics
#[derive(Debug, Clone)]
pub struct JWKSCacheStats {
    pub cached_providers: Vec<String>,
    pub expired_entries: u32,
    pub total_cached: u32,
    pub cache_ttl_seconds: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jwks_key_structure() {
        let key = JWKSKey {
            kty: "RSA".to_string(),
            use_: Some("sig".to_string()),
            alg: Some("RS256".to_string()),
            kid: "key-id-123".to_string(),
            n: Some("modulus".to_string()),
            e: Some("exponent".to_string()),
            x5c: None,
            x5t: None,
            x5t_s256: None,
        };

        assert_eq!(key.kty, "RSA");
        assert_eq!(key.kid, "key-id-123");
        assert!(key.use_.is_some());
    }

    #[test]
    fn test_jwks_serialization() {
        let jwks = JWKS {
            keys: vec![
                JWKSKey {
                    kty: "RSA".to_string(),
                    use_: Some("sig".to_string()),
                    alg: Some("RS256".to_string()),
                    kid: "key1".to_string(),
                    n: Some("n_value".to_string()),
                    e: Some("e_value".to_string()),
                    x5c: None,
                    x5t: None,
                    x5t_s256: None,
                },
            ],
        };

        let json = serde_json::to_string(&jwks).unwrap();
        let deserialized: JWKS = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.keys.len(), 1);
        assert_eq!(deserialized.keys[0].kid, "key1");
    }

    #[test]
    fn test_cache_entry_structure() {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let entry = JWKSCacheEntry {
            jwks: JWKS { keys: vec![] },
            cached_at: now,
            expires_at: now + 86400,
        };

        assert!(entry.expires_at > entry.cached_at);
    }
}
