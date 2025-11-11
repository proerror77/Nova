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
            dotenv::dotenv().ok();
            info!("Loaded .env file for development");
        }

        let jwt = JwtSettings::load().await?;

        Ok(Settings {
            database: DatabaseSettings::from_env()?,
            redis: RedisSettings::from_env()?,
            kafka: KafkaSettings::from_env()?,
            jwt,
            server: ServerSettings::from_env()?,
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
            url: env::var("DATABASE_URL")
                .context("DATABASE_URL must be set")?,
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
            url: env::var("REDIS_URL")
                .context("REDIS_URL must be set")?,
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
        let brokers_str = env::var("KAFKA_BROKERS")
            .context("KAFKA_BROKERS must be set")?;
        let brokers = brokers_str
            .split(',')
            .map(|s| s.trim().to_string())
            .collect();

        Ok(Self {
            brokers,
            topic_prefix: env::var("KAFKA_TOPIC_PREFIX")
                .unwrap_or_else(|_| "identity".to_string()),
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
        let signing_key = env::var("JWT_SECRET")
            .context("JWT_SECRET must be set when AWS_SECRETS_JWT_NAME is not available")?;

        let algorithm = env::var("JWT_ALGORITHM")
            .unwrap_or_else(|_| "HS256".to_string());

        let issuer = env::var("JWT_ISSUER")
            .unwrap_or_else(|_| "nova-platform".to_string());

        let audience_str = env::var("JWT_AUDIENCE")
            .unwrap_or_else(|_| "api,web".to_string());
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
            host: env::var("SERVER_HOST")
                .unwrap_or_else(|_| "0.0.0.0".to_string()),
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
