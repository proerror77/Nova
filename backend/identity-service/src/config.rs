//! Configuration management for Identity Service
//!
//! Loads settings from:
//! 1. AWS Secrets Manager (production)
//! 2. Environment variables (development fallback)
//! 3. .env file (local development)
//!
//! # Example
//!
//! ```no_run
//! use identity_service::config::Settings;
//!
//! #[tokio::main]
//! async fn main() -> anyhow::Result<()> {
//!     let settings = Settings::load().await?;
//!     println!("JWT issuer: {}", settings.jwt.issuer);
//!     Ok(())
//! }
//! ```

use anyhow::{Context, Result};
use aws_secrets::SecretManager;
use serde::{Deserialize, Serialize};
use std::env;
use tracing::{info, warn};

/// Application settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub database: DatabaseSettings,
    pub redis: RedisSettings,
    pub kafka: KafkaSettings,
    pub jwt: JwtSettings,
    pub server: ServerSettings,
    pub email: EmailSettings,
    pub oauth: OAuthSettings,
    pub passkey: PasskeySettings,
    pub zitadel: ZitadelSettings,
}

impl Settings {
    /// Load settings from AWS Secrets Manager or environment variables
    ///
    /// Priority:
    /// 1. AWS Secrets Manager (if AWS_SECRETS_JWT_NAME is set)
    /// 2. Environment variables (fallback)
    /// 3. .env file (local development)
    pub async fn load() -> Result<Self> {
        // Load .env file in development
        if cfg!(debug_assertions) {
            dotenvy::dotenv().ok();
            info!("Loaded .env file for development");
        }

        let jwt = JwtSettings::load().await?;

        Ok(Settings {
            database: DatabaseSettings::from_env()?,
            redis: RedisSettings::from_env()?,
            kafka: KafkaSettings::from_env()?,
            jwt,
            server: ServerSettings::from_env()?,
            email: EmailSettings::from_env()?,
            oauth: OAuthSettings::from_env()?,
            passkey: PasskeySettings::from_env()?,
            zitadel: ZitadelSettings::from_env(),
        })
    }
}

/// Database connection settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseSettings {
    pub url: String,
    pub max_connections: u32,
    pub min_connections: u32,
    pub connection_timeout: u64,
    pub idle_timeout: u64,
    pub acquire_timeout: u64,
}

impl DatabaseSettings {
    fn from_env() -> Result<Self> {
        Ok(Self {
            url: env::var("DATABASE_URL").context("DATABASE_URL must be set")?,
            max_connections: env::var("DATABASE_MAX_CONNECTIONS")
                .unwrap_or_else(|_| "50".to_string())
                .parse()
                .context("Invalid DATABASE_MAX_CONNECTIONS")?,
            min_connections: env::var("DATABASE_MIN_CONNECTIONS")
                .unwrap_or_else(|_| "5".to_string())
                .parse()
                .context("Invalid DATABASE_MIN_CONNECTIONS")?,
            connection_timeout: env::var("DATABASE_CONNECTION_TIMEOUT")
                .unwrap_or_else(|_| "5".to_string())
                .parse()
                .context("Invalid DATABASE_CONNECTION_TIMEOUT")?,
            idle_timeout: env::var("DATABASE_IDLE_TIMEOUT")
                .unwrap_or_else(|_| "300".to_string())
                .parse()
                .context("Invalid DATABASE_IDLE_TIMEOUT")?,
            acquire_timeout: env::var("DATABASE_ACQUIRE_TIMEOUT")
                .unwrap_or_else(|_| "10".to_string())
                .parse()
                .context("Invalid DATABASE_ACQUIRE_TIMEOUT")?,
        })
    }
}

/// Redis cache settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RedisSettings {
    pub url: String,
    pub pool_size: u32,
    pub connection_timeout: u64,
    pub response_timeout: u64,
}

impl RedisSettings {
    fn from_env() -> Result<Self> {
        Ok(Self {
            url: env::var("REDIS_URL").context("REDIS_URL must be set")?,
            pool_size: env::var("REDIS_POOL_SIZE")
                .unwrap_or_else(|_| "10".to_string())
                .parse()
                .context("Invalid REDIS_POOL_SIZE")?,
            connection_timeout: env::var("REDIS_CONNECTION_TIMEOUT")
                .unwrap_or_else(|_| "5".to_string())
                .parse()
                .context("Invalid REDIS_CONNECTION_TIMEOUT")?,
            response_timeout: env::var("REDIS_RESPONSE_TIMEOUT")
                .unwrap_or_else(|_| "5".to_string())
                .parse()
                .context("Invalid REDIS_RESPONSE_TIMEOUT")?,
        })
    }
}

/// Kafka event streaming settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaSettings {
    pub brokers: Vec<String>,
    pub topic_prefix: String,
    pub producer_timeout: u64,
}

impl KafkaSettings {
    fn from_env() -> Result<Self> {
        let brokers_str = env::var("KAFKA_BROKERS").context("KAFKA_BROKERS must be set")?;
        let brokers = brokers_str
            .split(',')
            .map(|s| s.trim().to_string())
            .collect();

        Ok(Self {
            brokers,
            topic_prefix: env::var("KAFKA_TOPIC_PREFIX").unwrap_or_else(|_| "identity".to_string()),
            producer_timeout: env::var("KAFKA_PRODUCER_TIMEOUT")
                .unwrap_or_else(|_| "5".to_string())
                .parse()
                .context("Invalid KAFKA_PRODUCER_TIMEOUT")?,
        })
    }
}

/// JWT authentication settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JwtSettings {
    pub signing_key: String,
    pub validation_key: Option<String>,
    pub algorithm: String,
    pub issuer: String,
    pub audience: Vec<String>,
    pub expiry_seconds: u64,
}

impl JwtSettings {
    /// Load JWT settings from AWS Secrets Manager or environment variables
    ///
    /// Priority:
    /// 1. AWS Secrets Manager (if AWS_SECRETS_JWT_NAME is set)
    /// 2. Environment variable JWT_SECRET (development mode)
    /// 3. Error if neither is available
    async fn load() -> Result<Self> {
        // Try AWS Secrets Manager first
        if let Ok(secret_name) = env::var("AWS_SECRETS_JWT_NAME") {
            info!(
                secret_name = %secret_name,
                "Loading JWT configuration from AWS Secrets Manager"
            );

            match Self::from_aws_secrets(&secret_name).await {
                Ok(config) => {
                    info!("Successfully loaded JWT config from AWS Secrets Manager");
                    return Ok(config);
                }
                Err(e) => {
                    warn!(
                        error = %e,
                        "Failed to load JWT config from AWS Secrets Manager, falling back to environment variables"
                    );
                }
            }
        }

        // Fallback to environment variables
        info!("Loading JWT configuration from environment variables (development mode)");
        Self::from_env()
    }

    /// Load JWT configuration from AWS Secrets Manager
    async fn from_aws_secrets(secret_name: &str) -> Result<Self> {
        let manager = SecretManager::new()
            .await
            .context("Failed to initialize AWS Secrets Manager client")?;

        let aws_config = manager
            .get_jwt_config(secret_name)
            .await
            .context("Failed to fetch JWT config from AWS Secrets Manager")?;

        Ok(Self {
            signing_key: aws_config.signing_key,
            validation_key: aws_config.validation_key,
            algorithm: aws_config.algorithm,
            issuer: aws_config.issuer,
            audience: aws_config.audience,
            expiry_seconds: aws_config.expiry_seconds,
        })
    }

    /// Load JWT configuration from environment variables
    fn from_env() -> Result<Self> {
        // Prefer PEM-based RSA keys when available (production-like configuration).
        // This matches the staging/production secret layout where JWT_PRIVATE_KEY / JWT_PUBLIC_KEY
        // contain full PEM-encoded keys for RS256.
        if let Ok(private_pem) = env::var("JWT_PRIVATE_KEY") {
            let public_pem = env::var("JWT_PUBLIC_KEY").ok();

            let issuer = env::var("JWT_ISSUER").unwrap_or_else(|_| "nova-platform".to_string());
            let audience_str = env::var("JWT_AUDIENCE").unwrap_or_else(|_| "api,web".to_string());
            let audience = audience_str
                .split(',')
                .map(|s| s.trim().to_string())
                .collect();

            let expiry_seconds = env::var("JWT_EXPIRY_SECONDS")
                .unwrap_or_else(|_| "3600".to_string())
                .parse()
                .context("Invalid JWT_EXPIRY_SECONDS")?;

            return Ok(Self {
                signing_key: private_pem,
                validation_key: public_pem,
                algorithm: "RS256".to_string(),
                issuer,
                audience,
                expiry_seconds,
            });
        }

        // Fallback: symmetric secret (development only)
        let signing_key = env::var("JWT_SECRET").context(
            "JWT_SECRET must be set when AWS_SECRETS_JWT_NAME is not available and no PEM keys are configured",
        )?;

        let algorithm = env::var("JWT_ALGORITHM").unwrap_or_else(|_| "HS256".to_string());

        let issuer = env::var("JWT_ISSUER").unwrap_or_else(|_| "nova-platform".to_string());

        let audience_str = env::var("JWT_AUDIENCE").unwrap_or_else(|_| "api,web".to_string());
        let audience = audience_str
            .split(',')
            .map(|s| s.trim().to_string())
            .collect();

        let expiry_seconds = env::var("JWT_EXPIRY_SECONDS")
            .unwrap_or_else(|_| "3600".to_string())
            .parse()
            .context("Invalid JWT_EXPIRY_SECONDS")?;

        // Validation key is optional (only for asymmetric algorithms)
        let validation_key = env::var("JWT_VALIDATION_KEY").ok();

        Ok(Self {
            signing_key,
            validation_key,
            algorithm,
            issuer,
            audience,
            expiry_seconds,
        })
    }
}

/// Server configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerSettings {
    pub host: String,
    pub port: u16,
    pub health_port: u16,
    pub metrics_port: u16,
}

impl ServerSettings {
    fn from_env() -> Result<Self> {
        Ok(Self {
            host: env::var("SERVER_HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
            port: env::var("SERVER_PORT")
                .unwrap_or_else(|_| "50051".to_string())
                .parse()
                .context("Invalid SERVER_PORT")?,
            health_port: env::var("SERVER_HEALTH_PORT")
                .unwrap_or_else(|_| "8080".to_string())
                .parse()
                .context("Invalid SERVER_HEALTH_PORT")?,
            metrics_port: env::var("SERVER_METRICS_PORT")
                .unwrap_or_else(|_| "9090".to_string())
                .parse()
                .context("Invalid SERVER_METRICS_PORT")?,
        })
    }
}

/// Email service configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmailSettings {
    pub smtp_host: String,
    pub smtp_port: u16,
    pub smtp_username: Option<String>,
    pub smtp_password: Option<String>,
    pub smtp_from: String,
    pub use_starttls: bool,
    pub verification_base_url: Option<String>,
    pub password_reset_base_url: Option<String>,
}

impl EmailSettings {
    fn from_env() -> Result<Self> {
        Ok(Self {
            smtp_host: env::var("SMTP_HOST").unwrap_or_else(|_| "localhost".to_string()),
            smtp_port: env::var("SMTP_PORT")
                .unwrap_or_else(|_| "1025".to_string())
                .parse()
                .context("Invalid SMTP_PORT")?,
            smtp_username: env::var("SMTP_USERNAME").ok(),
            smtp_password: env::var("SMTP_PASSWORD").ok(),
            smtp_from: env::var("SMTP_FROM").unwrap_or_else(|_| "noreply@nova.dev".to_string()),
            use_starttls: env::var("SMTP_USE_STARTTLS")
                .unwrap_or_else(|_| "false".to_string())
                .parse()
                .unwrap_or(false),
            verification_base_url: env::var("EMAIL_VERIFICATION_BASE_URL").ok(),
            password_reset_base_url: env::var("EMAIL_PASSWORD_RESET_BASE_URL").ok(),
        })
    }
}

/// OAuth provider configuration (Google and Apple)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthSettings {
    // Google OAuth 2.0
    pub google_client_id: Option<String>,
    pub google_client_secret: Option<String>,
    pub google_redirect_uri: Option<String>,
    // Apple Sign In
    pub apple_team_id: Option<String>,
    pub apple_client_id: Option<String>,
    pub apple_key_id: Option<String>,
    pub apple_private_key: Option<String>,
    pub apple_redirect_uri: Option<String>,
    pub default_scope: String,
}

impl OAuthSettings {
    fn from_env() -> Result<Self> {
        Ok(Self {
            // Google
            google_client_id: env::var("OAUTH_GOOGLE_CLIENT_ID").ok(),
            google_client_secret: env::var("OAUTH_GOOGLE_CLIENT_SECRET").ok(),
            google_redirect_uri: env::var("OAUTH_GOOGLE_REDIRECT_URI").ok(),
            // Apple
            apple_team_id: env::var("OAUTH_APPLE_TEAM_ID").ok(),
            apple_client_id: env::var("OAUTH_APPLE_CLIENT_ID").ok(),
            apple_key_id: env::var("OAUTH_APPLE_KEY_ID").ok(),
            apple_private_key: env::var("OAUTH_APPLE_PRIVATE_KEY").ok(),
            apple_redirect_uri: env::var("OAUTH_APPLE_REDIRECT_URI").ok(),
            default_scope: env::var("OAUTH_DEFAULT_SCOPE")
                .unwrap_or_else(|_| "email profile".to_string()),
        })
    }
}

/// Passkey (WebAuthn/FIDO2) configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PasskeySettings {
    /// Relying Party ID (domain name, e.g., "icered.com")
    pub rp_id: String,
    /// Relying Party name displayed to users
    pub rp_name: String,
    /// Origin URL for WebAuthn validation (e.g., "https://icered.com")
    pub origin: String,
    /// Challenge TTL in seconds (default: 300 = 5 minutes)
    pub challenge_ttl_secs: u64,
}

impl PasskeySettings {
    fn from_env() -> Result<Self> {
        Ok(Self {
            rp_id: env::var("PASSKEY_RP_ID")
                .unwrap_or_else(|_| "icered.com".to_string()),
            rp_name: env::var("PASSKEY_RP_NAME")
                .unwrap_or_else(|_| "ICERED".to_string()),
            origin: env::var("PASSKEY_ORIGIN")
                .unwrap_or_else(|_| "https://icered.com".to_string()),
            challenge_ttl_secs: env::var("PASSKEY_CHALLENGE_TTL_SECS")
                .unwrap_or_else(|_| "300".to_string())
                .parse()
                .context("Invalid PASSKEY_CHALLENGE_TTL_SECS")?,
        })
    }
}

/// Zitadel user sync configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZitadelSettings {
    /// Zitadel API URL (e.g., "https://zitadel.example.com")
    pub api_url: Option<String>,
    /// Service user token for API access
    pub service_token: Option<String>,
    /// Organization ID in Zitadel
    pub org_id: Option<String>,
}

impl ZitadelSettings {
    fn from_env() -> Self {
        Self {
            api_url: env::var("ZITADEL_API_URL").ok(),
            service_token: env::var("ZITADEL_SERVICE_TOKEN").ok(),
            org_id: env::var("ZITADEL_ORG_ID").ok(),
        }
    }

    /// Check if Zitadel integration is configured
    pub fn is_configured(&self) -> bool {
        self.api_url.is_some() && self.service_token.is_some() && self.org_id.is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jwt_settings_from_env() {
        // Set test environment variables
        env::set_var("JWT_SECRET", "test-secret-key");
        env::set_var("JWT_ALGORITHM", "HS256");
        env::set_var("JWT_ISSUER", "test-issuer");
        env::set_var("JWT_AUDIENCE", "api,web,mobile");
        env::set_var("JWT_EXPIRY_SECONDS", "7200");

        let settings = JwtSettings::from_env().unwrap();

        assert_eq!(settings.signing_key, "test-secret-key");
        assert_eq!(settings.algorithm, "HS256");
        assert_eq!(settings.issuer, "test-issuer");
        assert_eq!(settings.audience, vec!["api", "web", "mobile"]);
        assert_eq!(settings.expiry_seconds, 7200);
        assert!(settings.validation_key.is_none());

        // Clean up
        env::remove_var("JWT_SECRET");
        env::remove_var("JWT_ALGORITHM");
        env::remove_var("JWT_ISSUER");
        env::remove_var("JWT_AUDIENCE");
        env::remove_var("JWT_EXPIRY_SECONDS");
    }

    #[test]
    fn test_database_settings_from_env() {
        env::set_var("DATABASE_URL", "postgres://localhost/test");
        env::set_var("DATABASE_MAX_CONNECTIONS", "100");

        let settings = DatabaseSettings::from_env().unwrap();

        assert_eq!(settings.url, "postgres://localhost/test");
        assert_eq!(settings.max_connections, 100);
        assert_eq!(settings.min_connections, 5); // Default

        env::remove_var("DATABASE_URL");
        env::remove_var("DATABASE_MAX_CONNECTIONS");
    }

    #[test]
    fn test_redis_settings_from_env() {
        env::set_var("REDIS_URL", "redis://localhost:6379");

        let settings = RedisSettings::from_env().unwrap();

        assert_eq!(settings.url, "redis://localhost:6379");
        assert_eq!(settings.pool_size, 10); // Default

        env::remove_var("REDIS_URL");
    }

    #[test]
    fn test_kafka_settings_from_env() {
        env::set_var("KAFKA_BROKERS", "localhost:9092,localhost:9093");
        env::set_var("KAFKA_TOPIC_PREFIX", "test");

        let settings = KafkaSettings::from_env().unwrap();

        assert_eq!(settings.brokers, vec!["localhost:9092", "localhost:9093"]);
        assert_eq!(settings.topic_prefix, "test");

        env::remove_var("KAFKA_BROKERS");
        env::remove_var("KAFKA_TOPIC_PREFIX");
    }
}
