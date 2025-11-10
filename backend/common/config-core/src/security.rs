//! Security configuration

use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use validator::Validate;

/// Security configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct SecurityConfig {
    /// JWT configuration
    pub jwt: JwtConfig,

    /// Rate limiting configuration
    #[serde(default)]
    pub rate_limiting: RateLimitingConfig,

    /// CORS configuration (shared with HTTP)
    #[serde(default)]
    pub cors: CorsSecurityConfig,

    /// Encryption configuration
    #[serde(default)]
    pub encryption: EncryptionConfig,

    /// API key configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub api_keys: Option<ApiKeyConfig>,

    /// OAuth2 configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub oauth2: Option<OAuth2Config>,

    /// Content security policy
    #[serde(skip_serializing_if = "Option::is_none")]
    pub csp: Option<ContentSecurityPolicy>,
}

impl SecurityConfig {
    /// Validate that security settings are appropriate for environment
    pub fn validate_for_production(&self) -> Result<(), String> {
        // JWT must use RS256 in production
        if !matches!(self.jwt.algorithm, JwtAlgorithm::RS256) {
            return Err("Production must use RS256 for JWT".to_string());
        }

        // Private key must be set
        if self.jwt.private_key.expose_secret().is_empty() {
            return Err("JWT private key is required in production".to_string());
        }

        // Rate limiting should be enabled
        if !self.rate_limiting.enabled {
            return Err("Rate limiting must be enabled in production".to_string());
        }

        Ok(())
    }
}

/// JWT configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct JwtConfig {
    /// JWT algorithm (RS256 required for production)
    #[serde(default = "default_jwt_algorithm")]
    pub algorithm: JwtAlgorithm,

    /// Public key (PEM format) for RS256
    #[serde(default)]
    pub public_key: SecretString,

    /// Private key (PEM format) for RS256
    #[serde(default)]
    pub private_key: SecretString,

    /// JWT secret for HS256 (DEPRECATED - dev only)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub secret: Option<SecretString>,

    /// Token expiry in seconds
    #[validate(range(min = 60, max = 86400))] // 1 min - 24 hours
    #[serde(default = "default_token_expiry")]
    pub expiry_secs: u64,

    /// Refresh token expiry in seconds
    #[validate(range(min = 3600, max = 2592000))] // 1 hour - 30 days
    #[serde(default = "default_refresh_expiry")]
    pub refresh_expiry_secs: u64,

    /// Issuer
    #[validate(length(min = 1))]
    #[serde(default = "default_issuer")]
    pub issuer: String,

    /// Audience
    #[validate(length(min = 1))]
    #[serde(default = "default_audience")]
    pub audience: String,

    /// Leeway for time validation in seconds
    #[serde(default = "default_leeway")]
    pub leeway_secs: u64,
}

fn default_jwt_algorithm() -> JwtAlgorithm {
    JwtAlgorithm::RS256
}

fn default_token_expiry() -> u64 {
    3600 // 1 hour
}

fn default_refresh_expiry() -> u64 {
    604800 // 7 days
}

fn default_issuer() -> String {
    "nova-auth".to_string()
}

fn default_audience() -> String {
    "nova-api".to_string()
}

fn default_leeway() -> u64 {
    60 // 1 minute
}

impl JwtConfig {
    /// Get token expiry as Duration
    pub fn token_expiry(&self) -> Duration {
        Duration::from_secs(self.expiry_secs)
    }

    /// Get refresh token expiry as Duration
    pub fn refresh_expiry(&self) -> Duration {
        Duration::from_secs(self.refresh_expiry_secs)
    }

    /// Get leeway as Duration
    pub fn leeway(&self) -> Duration {
        Duration::from_secs(self.leeway_secs)
    }
}

/// JWT algorithm
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
pub enum JwtAlgorithm {
    /// HMAC SHA-256 (DEPRECATED - dev only)
    HS256,
    /// RSA SHA-256 (REQUIRED for production)
    RS256,
    /// ECDSA SHA-256
    ES256,
}

/// Rate limiting configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct RateLimitingConfig {
    /// Enable rate limiting
    #[serde(default = "default_rate_limiting_enabled")]
    pub enabled: bool,

    /// Global rate limit (requests per second)
    #[validate(range(min = 1, max = 100000))]
    #[serde(default = "default_global_limit")]
    pub global_limit: u32,

    /// Per-IP rate limit (requests per second)
    #[validate(range(min = 1, max = 10000))]
    #[serde(default = "default_per_ip_limit")]
    pub per_ip_limit: u32,

    /// Per-user rate limit (requests per second)
    #[validate(range(min = 1, max = 10000))]
    #[serde(default = "default_per_user_limit")]
    pub per_user_limit: u32,

    /// Burst size multiplier
    #[validate(range(min = 1, max = 100))]
    #[serde(default = "default_burst_multiplier")]
    pub burst_multiplier: u32,

    /// Window size in seconds
    #[validate(range(min = 1, max = 3600))]
    #[serde(default = "default_window_secs")]
    pub window_secs: u64,

    /// Whitelist IPs (no rate limiting)
    #[serde(default)]
    pub whitelist_ips: Vec<String>,
}

fn default_rate_limiting_enabled() -> bool {
    true
}

fn default_global_limit() -> u32 {
    10000
}

fn default_per_ip_limit() -> u32 {
    100
}

fn default_per_user_limit() -> u32 {
    1000
}

fn default_burst_multiplier() -> u32 {
    10
}

fn default_window_secs() -> u64 {
    60
}

impl Default for RateLimitingConfig {
    fn default() -> Self {
        Self {
            enabled: default_rate_limiting_enabled(),
            global_limit: default_global_limit(),
            per_ip_limit: default_per_ip_limit(),
            per_user_limit: default_per_user_limit(),
            burst_multiplier: default_burst_multiplier(),
            window_secs: default_window_secs(),
            whitelist_ips: Vec::new(),
        }
    }
}

/// CORS security configuration
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct CorsSecurityConfig {
    /// Allowed origins
    #[serde(default)]
    pub allowed_origins: Vec<String>,

    /// Allow credentials
    #[serde(default)]
    pub allow_credentials: bool,

    /// Max age in seconds
    #[serde(default = "default_cors_max_age")]
    pub max_age_secs: u64,
}

fn default_cors_max_age() -> u64 {
    3600
}

/// Encryption configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct EncryptionConfig {
    /// Encryption key for data at rest (base64 encoded)
    #[serde(skip_serializing)]
    pub data_encryption_key: Option<SecretString>,

    /// Key derivation iterations
    #[serde(default = "default_kdf_iterations")]
    pub kdf_iterations: u32,

    /// Encryption algorithm
    #[serde(default)]
    pub algorithm: EncryptionAlgorithm,
}

fn default_kdf_iterations() -> u32 {
    100000
}

impl Default for EncryptionConfig {
    fn default() -> Self {
        Self {
            data_encryption_key: None,
            kdf_iterations: default_kdf_iterations(),
            algorithm: EncryptionAlgorithm::default(),
        }
    }
}

/// Encryption algorithm
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum EncryptionAlgorithm {
    /// AES-256-GCM
    #[default]
    Aes256Gcm,
    /// ChaCha20-Poly1305
    ChaCha20Poly1305,
}

/// API key configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ApiKeyConfig {
    /// Enable API key authentication
    #[serde(default = "default_api_key_enabled")]
    pub enabled: bool,

    /// API key header name
    #[serde(default = "default_api_key_header")]
    pub header_name: String,

    /// API keys (hashed)
    #[serde(default)]
    pub keys: Vec<ApiKey>,
}

fn default_api_key_enabled() -> bool {
    false
}

fn default_api_key_header() -> String {
    "X-API-Key".to_string()
}

/// API key entry
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ApiKey {
    /// Key ID
    pub id: String,

    /// Key hash (bcrypt/argon2)
    #[serde(skip_serializing)]
    pub hash: SecretString,

    /// Key name/description
    pub name: String,

    /// Allowed scopes
    #[serde(default)]
    pub scopes: Vec<String>,

    /// Rate limit override
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rate_limit: Option<u32>,
}

/// OAuth2 configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct OAuth2Config {
    /// OAuth2 providers
    pub providers: Vec<OAuth2Provider>,

    /// Redirect URL base
    pub redirect_url_base: String,

    /// State token expiry in seconds
    #[serde(default = "default_state_expiry")]
    pub state_expiry_secs: u64,
}

fn default_state_expiry() -> u64 {
    600 // 10 minutes
}

/// OAuth2 provider
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct OAuth2Provider {
    /// Provider name
    pub name: String,

    /// Client ID
    pub client_id: String,

    /// Client secret
    #[serde(skip_serializing)]
    pub client_secret: SecretString,

    /// Authorization URL
    pub auth_url: String,

    /// Token URL
    pub token_url: String,

    /// User info URL
    pub user_info_url: String,

    /// Scopes
    #[serde(default)]
    pub scopes: Vec<String>,
}

/// Content Security Policy
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ContentSecurityPolicy {
    /// Default source
    #[serde(default = "default_csp_default")]
    pub default_src: Vec<String>,

    /// Script source
    #[serde(default)]
    pub script_src: Vec<String>,

    /// Style source
    #[serde(default)]
    pub style_src: Vec<String>,

    /// Image source
    #[serde(default)]
    pub img_src: Vec<String>,

    /// Connect source (for fetch/XHR)
    #[serde(default)]
    pub connect_src: Vec<String>,

    /// Report URI
    #[serde(skip_serializing_if = "Option::is_none")]
    pub report_uri: Option<String>,
}

fn default_csp_default() -> Vec<String> {
    vec!["'self'".to_string()]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jwt_config() {
        let config = JwtConfig {
            algorithm: JwtAlgorithm::RS256,
            public_key: SecretString::from("public_key"),
            private_key: SecretString::from("private_key"),
            secret: None,
            expiry_secs: 3600,
            refresh_expiry_secs: 604800,
            issuer: "test".to_string(),
            audience: "api".to_string(),
            leeway_secs: 60,
        };

        assert_eq!(config.token_expiry(), Duration::from_secs(3600));
        assert!(matches!(config.algorithm, JwtAlgorithm::RS256));
    }

    #[test]
    fn test_production_validation() {
        let mut config = SecurityConfig {
            jwt: JwtConfig {
                algorithm: JwtAlgorithm::HS256, // Wrong for production
                public_key: SecretString::from(""),
                private_key: SecretString::from(""),
                secret: Some(SecretString::from("secret")),
                expiry_secs: 3600,
                refresh_expiry_secs: 604800,
                issuer: "test".to_string(),
                audience: "api".to_string(),
                leeway_secs: 60,
            },
            rate_limiting: RateLimitingConfig::default(),
            cors: CorsSecurityConfig::default(),
            encryption: EncryptionConfig::default(),
            api_keys: None,
            oauth2: None,
            csp: None,
        };

        assert!(config.validate_for_production().is_err());

        // Fix for production
        config.jwt.algorithm = JwtAlgorithm::RS256;
        config.jwt.private_key = SecretString::from("private_key_pem");
        config.jwt.public_key = SecretString::from("public_key_pem");

        assert!(config.validate_for_production().is_ok());
    }
}