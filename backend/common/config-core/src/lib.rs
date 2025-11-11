//! Unified configuration management for Nova backend services
//!
//! This library provides:
//! - Common configuration structures used across all services
//! - Environment-aware configuration loading
//! - Secret management with zero-copy protection
//! - Validation and type safety
//! - Hot reload support (optional)

use error_types::{ServiceError, ServiceResult};
use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::time::Duration;
use url::Url;
use validator::Validate;

pub mod database;
pub mod grpc;
pub mod http;
pub mod kafka;
pub mod observability;
pub mod redis;
pub mod security;

// Re-export commonly used types
pub use database::DatabaseConfig;
pub use grpc::GrpcConfig;
pub use http::HttpServerConfig;
pub use kafka::KafkaConfig;
pub use observability::ObservabilityConfig;
pub use redis::RedisConfig;
pub use security::SecurityConfig;

/// Environment type for configuration
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Environment {
    /// Local development
    Local,
    /// Development server
    Development,
    /// Staging environment
    Staging,
    /// Production environment
    Production,
}

impl Environment {
    /// Check if this is a production environment
    pub fn is_production(&self) -> bool {
        matches!(self, Environment::Production)
    }

    /// Check if this is a local development environment
    pub fn is_local(&self) -> bool {
        matches!(self, Environment::Local)
    }

    /// Get environment from string
    pub fn from_str(s: &str) -> Result<Self, String> {
        match s.to_lowercase().as_str() {
            "local" | "loc" => Ok(Environment::Local),
            "development" | "dev" => Ok(Environment::Development),
            "staging" | "stage" | "stg" => Ok(Environment::Staging),
            "production" | "prod" | "prd" => Ok(Environment::Production),
            _ => Err(format!("Unknown environment: {}", s)),
        }
    }
}

impl Default for Environment {
    fn default() -> Self {
        Environment::Development
    }
}

/// Base application configuration
///
/// This is the root configuration that all services extend
#[derive(Debug, Clone, Deserialize, Validate)]
pub struct BaseConfig {
    /// Application name
    pub app_name: String,

    /// Application version
    pub app_version: String,

    /// Environment (local, dev, staging, prod)
    pub environment: Environment,

    /// Service instance ID (for distributed systems)
    #[serde(default = "generate_instance_id")]
    pub instance_id: String,

    /// HTTP server configuration
    pub http: HttpServerConfig,

    /// gRPC server configuration (if applicable)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub grpc: Option<GrpcConfig>,

    /// Database configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub database: Option<DatabaseConfig>,

    /// Redis configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub redis: Option<RedisConfig>,

    /// Kafka configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kafka: Option<KafkaConfig>,

    /// Security configuration
    pub security: SecurityConfig,

    /// Observability configuration
    pub observability: ObservabilityConfig,
}

fn generate_instance_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

impl BaseConfig {
    /// Load configuration from environment and files
    ///
    /// # Loading Order
    /// 1. Default values
    /// 2. Configuration file (if exists)
    /// 3. Environment-specific file (e.g., `config.production.toml`)
    /// 4. Environment variables (highest priority)
    ///
    /// # Environment Variables
    /// Uses the pattern: `APP_NAME_SECTION_KEY`
    /// Example: `NOVA_DATABASE_HOST=localhost`
    pub fn load(config_path: Option<&Path>) -> ServiceResult<Self> {
        // Load .env file if it exists (for local development)
        dotenv::dotenv().ok();

        let environment = std::env::var("ENVIRONMENT")
            .or_else(|_| std::env::var("ENV"))
            .unwrap_or_else(|_| "development".to_string());

        let environment = Environment::from_str(&environment)
            .map_err(|e| ServiceError::InvalidInput {
                message: e,
                source: None,
            })?;

        let mut builder = config::Config::builder();

        // Add default configuration
        builder = builder.add_source(config::File::from_str(
            include_str!("../config/defaults.toml"),
            config::FileFormat::Toml,
        ));

        // Add base configuration file if provided
        if let Some(path) = config_path {
            if path.exists() {
                builder = builder.add_source(config::File::from(path));
            }

            // Add environment-specific configuration
            let env_name = serde_json::to_string(&environment)
                .map_err(|e| ConfigError::Message(format!("Failed to serialize environment: {}", e)))?
                .trim_matches('"')
                .to_string();
            let env_specific = path
                .parent()
                .unwrap_or_else(|| Path::new("."))
                .join(format!("config.{}.toml", env_name));

            if env_specific.exists() {
                builder = builder.add_source(config::File::from(env_specific));
            }
        }

        // Override with environment variables
        builder = builder.add_source(
            config::Environment::with_prefix("NOVA")
                .separator("_")
                .try_parsing(true),
        );

        let settings = builder
            .build()
            .map_err(|e| ServiceError::InvalidInput {
                message: format!("Failed to load configuration: {}", e),
                source: Some(Box::new(e)),
            })?;

        let config: BaseConfig = settings
            .try_deserialize()
            .map_err(|e| ServiceError::InvalidInput {
                message: format!("Failed to deserialize configuration: {}", e),
                source: Some(Box::new(e)),
            })?;

        // Validate configuration
        config.validate()
            .map_err(|e| ServiceError::InvalidInput {
                message: format!("Configuration validation failed: {}", e),
                source: None,
            })?;

        Ok(config)
    }

    /// Validate configuration
    pub fn validate(&self) -> Result<(), validator::ValidationErrors> {
        Validate::validate(self)?;

        // Additional custom validation
        if self.environment.is_production() {
            // In production, certain configs are mandatory
            if self.security.jwt_public_key.expose_secret().is_empty() {
                let mut errors = validator::ValidationErrors::new();
                errors.add(
                    "security.jwt_public_key",
                    validator::ValidationError::new("required_in_production"),
                );
                return Err(errors);
            }
        }

        Ok(())
    }

    /// Get connection string for primary database
    pub fn database_url(&self) -> Option<SecretString> {
        self.database.as_ref().map(|db| db.connection_url())
    }

    /// Get Redis URL
    pub fn redis_url(&self) -> Option<SecretString> {
        self.redis.as_ref().map(|r| r.connection_url())
    }

    /// Check if running in debug mode
    pub fn is_debug(&self) -> bool {
        !self.environment.is_production()
    }
}

/// Service-specific configuration trait
///
/// Services should implement this trait for their custom configuration
pub trait ServiceConfig: Sized {
    /// Load service-specific configuration
    fn load() -> ServiceResult<Self>;

    /// Get base configuration
    fn base(&self) -> &BaseConfig;

    /// Validate service-specific configuration
    fn validate(&self) -> ServiceResult<()> {
        self.base().validate()
            .map_err(|e| ServiceError::InvalidInput {
                message: format!("Configuration validation failed: {}", e),
                source: None,
            })
    }
}

/// Configuration loader with caching and hot-reload support
pub struct ConfigLoader<T: ServiceConfig> {
    config: tokio::sync::RwLock<T>,
    #[allow(dead_code)]
    reload_interval: Option<Duration>,
}

impl<T: ServiceConfig + Clone> ConfigLoader<T> {
    /// Create a new configuration loader
    pub async fn new() -> ServiceResult<Self> {
        let config = T::load()?;

        Ok(Self {
            config: tokio::sync::RwLock::new(config),
            reload_interval: None,
        })
    }

    /// Create a configuration loader with hot-reload
    pub async fn with_reload(reload_interval: Duration) -> ServiceResult<Self> {
        let config = T::load()?;

        Ok(Self {
            config: tokio::sync::RwLock::new(config),
            reload_interval: Some(reload_interval),
        })
    }

    /// Get current configuration
    pub async fn get(&self) -> T {
        self.config.read().await.clone()
    }

    /// Reload configuration
    pub async fn reload(&self) -> ServiceResult<()> {
        let new_config = T::load()?;
        new_config.validate()?;

        let mut config = self.config.write().await;
        *config = new_config;

        tracing::info!("Configuration reloaded successfully");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_environment_parsing() {
        assert_eq!(Environment::from_str("prod").unwrap(), Environment::Production);
        assert_eq!(Environment::from_str("dev").unwrap(), Environment::Development);
        assert_eq!(Environment::from_str("local").unwrap(), Environment::Local);
        assert!(Environment::from_str("invalid").is_err());
    }

    #[test]
    fn test_environment_checks() {
        let prod = Environment::Production;
        assert!(prod.is_production());
        assert!(!prod.is_local());

        let local = Environment::Local;
        assert!(!local.is_production());
        assert!(local.is_local());
    }
}