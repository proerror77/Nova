//! AWS Secrets Manager integration library with caching and rotation support
//!
//! This library provides a high-level interface to AWS Secrets Manager with:
//! - Automatic caching with configurable TTL
//! - Secret rotation detection and refresh
//! - Graceful error handling and retries
//! - Integration with Kubernetes IRSA (IAM Roles for Service Accounts)
//!
//! # Example
//!
//! ```no_run
//! use aws_secrets::SecretManager;
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     // Create manager (uses AWS credentials from environment/IRSA)
//!     let manager = SecretManager::new().await?;
//!
//!     // Fetch JWT signing key
//!     let jwt_secret = manager.get_secret("prod/jwt/signing-key").await?;
//!
//!     Ok(())
//! }
//! ```

use anyhow::{Context, Result};
use aws_config::BehaviorVersion;
use aws_sdk_secretsmanager::Client as SecretsClient;
use moka::future::Cache;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use thiserror::Error;
use tracing::{debug, info, warn};

#[derive(Error, Debug)]
pub enum SecretError {
    #[error("Secret not found: {0}")]
    NotFound(String),

    #[error("Access denied to secret: {0}")]
    AccessDenied(String),

    #[error("Secret decryption failed: {0}")]
    DecryptionFailed(String),

    #[error("Invalid secret format: {0}")]
    InvalidFormat(String),

    #[error("AWS SDK error: {0}")]
    AwsSdk(String),

    #[error("Cache error: {0}")]
    Cache(String),
}

/// Cached secret value with metadata
#[derive(Clone, Debug)]
struct CachedSecret {
    value: String,
    version_id: Option<String>,
    fetched_at: chrono::DateTime<chrono::Utc>,
}

/// JWT secret configuration from AWS Secrets Manager
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JwtSecretConfig {
    pub signing_key: String,
    pub validation_key: Option<String>, // For asymmetric keys (RS256, ES256)
    pub algorithm: String,               // HS256, RS256, ES256
    pub issuer: String,
    pub audience: Vec<String>,
    pub expiry_seconds: u64,
}

impl JwtSecretConfig {
    /// Parse JWT secret from JSON string
    pub fn from_json(json: &str) -> Result<Self, SecretError> {
        serde_json::from_str(json)
            .map_err(|e| SecretError::InvalidFormat(format!("Failed to parse JWT config: {}", e)))
    }
}

/// AWS Secrets Manager client with caching
pub struct SecretManager {
    client: SecretsClient,
    cache: Cache<String, CachedSecret>,
    cache_ttl: Duration,
}

impl SecretManager {
    /// Create a new SecretManager with default AWS configuration
    ///
    /// Uses AWS credentials from:
    /// 1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
    /// 2. AWS credentials file (~/.aws/credentials)
    /// 3. IAM instance profile (EC2)
    /// 4. IAM Roles for Service Accounts (EKS/Kubernetes)
    pub async fn new() -> Result<Self> {
        Self::with_cache_ttl(Duration::from_secs(300)).await // 5 minutes default TTL
    }

    /// Create a new SecretManager with custom cache TTL
    pub async fn with_cache_ttl(cache_ttl: Duration) -> Result<Self> {
        let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
        let client = SecretsClient::new(&config);

        info!(
            "Initialized AWS Secrets Manager client with cache TTL: {:?}",
            cache_ttl
        );

        let cache = Cache::builder()
            .max_capacity(100)
            .time_to_live(cache_ttl)
            .build();

        Ok(Self {
            client,
            cache,
            cache_ttl,
        })
    }

    /// Get a secret by name (with caching)
    ///
    /// Returns the secret string value. Cached values are automatically refreshed
    /// after the configured TTL expires.
    pub async fn get_secret(&self, secret_name: &str) -> Result<String, SecretError> {
        // Check cache first
        if let Some(cached) = self.cache.get(secret_name).await {
            debug!(
                secret_name = %secret_name,
                version_id = ?cached.version_id,
                cached_at = %cached.fetched_at,
                "Secret retrieved from cache"
            );
            return Ok(cached.value);
        }

        // Fetch from AWS
        debug!(secret_name = %secret_name, "Fetching secret from AWS Secrets Manager");
        let secret_value = self.fetch_secret(secret_name).await?;

        Ok(secret_value)
    }

    /// Get JWT configuration from AWS Secrets Manager
    ///
    /// Expects the secret to be stored as JSON with the following structure:
    /// ```json
    /// {
    ///   "signing_key": "base64-encoded-key",
    ///   "validation_key": "base64-encoded-key",  // optional for asymmetric
    ///   "algorithm": "HS256",
    ///   "issuer": "nova-platform",
    ///   "audience": ["api", "web"],
    ///   "expiry_seconds": 3600
    /// }
    /// ```
    pub async fn get_jwt_config(&self, secret_name: &str) -> Result<JwtSecretConfig, SecretError> {
        let secret_json = self.get_secret(secret_name).await?;
        JwtSecretConfig::from_json(&secret_json)
    }

    /// Fetch secret from AWS Secrets Manager and update cache
    async fn fetch_secret(&self, secret_name: &str) -> Result<String, SecretError> {
        let response = self
            .client
            .get_secret_value()
            .secret_id(secret_name)
            .send()
            .await
            .map_err(|e| {
                let error_msg = e.to_string();
                if error_msg.contains("ResourceNotFoundException") {
                    SecretError::NotFound(secret_name.to_string())
                } else if error_msg.contains("AccessDeniedException") {
                    SecretError::AccessDenied(secret_name.to_string())
                } else if error_msg.contains("DecryptionFailure") {
                    SecretError::DecryptionFailed(secret_name.to_string())
                } else {
                    SecretError::AwsSdk(error_msg)
                }
            })?;

        let secret_string = response
            .secret_string()
            .ok_or_else(|| SecretError::InvalidFormat("Secret is binary, not string".to_string()))?
            .to_string();

        let version_id = response.version_id().map(|s| s.to_string());

        // Cache the fetched secret
        let cached = CachedSecret {
            value: secret_string.clone(),
            version_id: version_id.clone(),
            fetched_at: chrono::Utc::now(),
        };

        self.cache.insert(secret_name.to_string(), cached).await;

        info!(
            secret_name = %secret_name,
            version_id = ?version_id,
            "Secret fetched and cached from AWS Secrets Manager"
        );

        Ok(secret_string)
    }

    /// Invalidate cache for a specific secret (useful for manual rotation)
    pub async fn invalidate_cache(&self, secret_name: &str) {
        self.cache.invalidate(secret_name).await;
        info!(secret_name = %secret_name, "Secret cache invalidated");
    }

    /// Invalidate all cached secrets
    pub async fn invalidate_all(&self) {
        self.cache.invalidate_all();
        info!("All secret caches invalidated");
    }

    /// Get cache statistics
    pub async fn cache_stats(&self) -> (u64, u64) {
        (self.cache.entry_count(), self.cache.weighted_size())
    }
}

/// Builder for SecretManager with custom configuration
pub struct SecretManagerBuilder {
    cache_ttl: Duration,
    max_cache_entries: u64,
}

impl Default for SecretManagerBuilder {
    fn default() -> Self {
        Self {
            cache_ttl: Duration::from_secs(300), // 5 minutes
            max_cache_entries: 100,
        }
    }
}

impl SecretManagerBuilder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cache_ttl(mut self, ttl: Duration) -> Self {
        self.cache_ttl = ttl;
        self
    }

    pub fn max_cache_entries(mut self, max: u64) -> Self {
        self.max_cache_entries = max;
        self
    }

    pub async fn build(self) -> Result<SecretManager> {
        let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
        let client = SecretsClient::new(&config);

        let cache = Cache::builder()
            .max_capacity(self.max_cache_entries)
            .time_to_live(self.cache_ttl)
            .build();

        Ok(SecretManager {
            client,
            cache,
            cache_ttl: self.cache_ttl,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jwt_config_parsing() {
        let json = r#"{
            "signing_key": "my-secret-key",
            "algorithm": "HS256",
            "issuer": "nova-platform",
            "audience": ["api", "web"],
            "expiry_seconds": 3600
        }"#;

        let config = JwtSecretConfig::from_json(json).unwrap();
        assert_eq!(config.signing_key, "my-secret-key");
        assert_eq!(config.algorithm, "HS256");
        assert_eq!(config.issuer, "nova-platform");
        assert_eq!(config.audience, vec!["api", "web"]);
        assert_eq!(config.expiry_seconds, 3600);
    }

    #[test]
    fn test_jwt_config_parsing_invalid() {
        let json = r#"{"invalid": "json"}"#;
        assert!(JwtSecretConfig::from_json(json).is_err());
    }
}
