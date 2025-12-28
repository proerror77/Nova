//! Configuration for GraphQL Gateway
//!
//! Loads settings from:
//! 1. AWS Secrets Manager (production)
//! 2. Environment variables (development fallback)
//! 3. .env file (local development)

use anyhow::{Context, Result};
use aws_secrets::SecretManager;
use serde::{Deserialize, Serialize};
use std::env;
use tracing::{info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Server configuration
    pub server: ServerConfig,

    /// Service endpoints
    pub services: ServiceEndpoints,

    /// Database configuration (for caching)
    pub database: DatabaseConfig,

    /// JWT configuration
    pub jwt: JwtConfig,

    /// GraphQL configuration
    pub graphql: GraphQLConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub workers: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceEndpoints {
    pub auth_service: String,
    // user_service removed - service is deprecated
    pub content_service: String,
    pub messaging_service: String,
    pub notification_service: String,
    pub feed_service: String,
    pub video_service: String,
    pub media_service: String,
    pub streaming_service: String,
    pub search_service: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
    pub min_connections: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JwtConfig {
    pub signing_key: String,
    pub validation_key: Option<String>,
    pub algorithm: String,
    pub issuer: String,
    pub audience: Vec<String>,
    pub expiry_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphQLConfig {
    /// Enable GraphQL Playground
    pub playground: bool,
    /// Max query depth
    pub max_depth: usize,
    /// Max query complexity
    pub max_complexity: usize,
    /// Enable introspection
    pub introspection: bool,
}

impl Config {
    /// Load configuration from environment variables and AWS Secrets Manager
    ///
    /// Priority:
    /// 1. AWS Secrets Manager (if AWS_SECRETS_JWT_NAME is set)
    /// 2. Environment variables (fallback)
    /// 3. .env file (local development)
    pub async fn from_env() -> Result<Self> {
        dotenvy::dotenv().ok();

        let jwt = Self::load_jwt_config().await?;

        Ok(Self {
            server: ServerConfig {
                host: env::var("SERVER_HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
                port: env::var("SERVER_PORT")
                    .ok()
                    .and_then(|p| p.parse().ok())
                    .unwrap_or(8080),
                workers: env::var("SERVER_WORKERS")
                    .ok()
                    .and_then(|w| w.parse().ok())
                    .unwrap_or(num_cpus::get()),
            },
            services: ServiceEndpoints {
                auth_service: env::var("AUTH_SERVICE_URL")
                    .unwrap_or_else(|_| "http://auth-service:50051".to_string()),
                // user_service removed - service is deprecated
                content_service: env::var("CONTENT_SERVICE_URL")
                    .unwrap_or_else(|_| "http://content-service:50053".to_string()),
                messaging_service: env::var("MESSAGING_SERVICE_URL")
                    .unwrap_or_else(|_| "http://messaging-service:50054".to_string()),
                notification_service: env::var("GRPC_NOTIFICATION_SERVICE_URL")
                    .or_else(|_| env::var("NOTIFICATION_SERVICE_URL"))
                    .unwrap_or_else(|_| "http://notification-service:9080".to_string()),
                feed_service: env::var("FEED_SERVICE_URL")
                    .unwrap_or_else(|_| "http://feed-service:50056".to_string()),
                video_service: env::var("VIDEO_SERVICE_URL")
                    .unwrap_or_else(|_| "http://video-service:50057".to_string()),
                media_service: env::var("MEDIA_SERVICE_URL")
                    .unwrap_or_else(|_| "http://media-service:50058".to_string()),
                streaming_service: env::var("STREAMING_SERVICE_URL")
                    .unwrap_or_else(|_| "http://streaming-service:50059".to_string()),
                search_service: env::var("SEARCH_SERVICE_URL")
                    .unwrap_or_else(|_| "http://search-service:50060".to_string()),
            },
            database: DatabaseConfig {
                url: env::var("DATABASE_URL")
                    .unwrap_or_else(|_| "postgres://postgres:password@localhost/nova".to_string()),
                max_connections: env::var("DB_MAX_CONNECTIONS")
                    .ok()
                    .and_then(|c| c.parse().ok())
                    .unwrap_or(10),
                min_connections: env::var("DB_MIN_CONNECTIONS")
                    .ok()
                    .and_then(|c| c.parse().ok())
                    .unwrap_or(2),
            },
            jwt,
            graphql: GraphQLConfig {
                playground: env::var("GRAPHQL_PLAYGROUND")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(true),
                max_depth: env::var("GRAPHQL_MAX_DEPTH")
                    .ok()
                    .and_then(|d| d.parse().ok())
                    .unwrap_or(10),
                max_complexity: env::var("GRAPHQL_MAX_COMPLEXITY")
                    .ok()
                    .and_then(|c| c.parse().ok())
                    .unwrap_or(1000),
                introspection: env::var("GRAPHQL_INTROSPECTION")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(true),
            },
        })
    }

    /// Load JWT configuration from AWS Secrets Manager or environment variables
    ///
    /// Priority:
    /// 1. AWS Secrets Manager (if AWS_SECRETS_JWT_NAME is set)
    /// 2. Environment variables (development mode)
    /// 3. Error if neither is available
    async fn load_jwt_config() -> Result<JwtConfig> {
        // Try AWS Secrets Manager first
        if let Ok(secret_name) = env::var("AWS_SECRETS_JWT_NAME") {
            info!(
                secret_name = %secret_name,
                "Loading JWT configuration from AWS Secrets Manager"
            );

            match Self::jwt_from_aws_secrets(&secret_name).await {
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
        Self::jwt_from_env()
    }

    /// Load JWT configuration from AWS Secrets Manager
    async fn jwt_from_aws_secrets(secret_name: &str) -> Result<JwtConfig> {
        let manager = SecretManager::new()
            .await
            .context("Failed to initialize AWS Secrets Manager client")?;

        let aws_config = manager
            .get_jwt_config(secret_name)
            .await
            .context("Failed to fetch JWT config from AWS Secrets Manager")?;

        Ok(JwtConfig {
            signing_key: aws_config.signing_key,
            validation_key: aws_config.validation_key,
            algorithm: aws_config.algorithm,
            issuer: aws_config.issuer,
            audience: aws_config.audience,
            expiry_seconds: aws_config.expiry_seconds,
        })
    }

    /// Load JWT configuration from environment variables
    fn jwt_from_env() -> Result<JwtConfig> {
        let signing_key = env::var("JWT_SECRET")
            .context("JWT_SECRET must be set when AWS_SECRETS_JWT_NAME is not available")?;

        let algorithm = env::var("JWT_ALGORITHM").unwrap_or_else(|_| "HS256".to_string());

        let issuer = env::var("JWT_ISSUER").unwrap_or_else(|_| "nova-graphql-gateway".to_string());

        let audience_str = env::var("JWT_AUDIENCE").unwrap_or_else(|_| "nova-api".to_string());
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

        Ok(JwtConfig {
            signing_key,
            validation_key,
            algorithm,
            issuer,
            audience,
            expiry_seconds,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Note: test_config_defaults uses synchronous jwt_from_env() via test_jwt_config_from_env below.
    // The async Config::from_env() test is skipped because env::set_var is not thread-safe
    // when tests run in parallel, causing flaky failures.
    #[tokio::test]
    #[ignore = "env::set_var is not thread-safe; use test_jwt_config_from_env instead"]
    async fn test_config_defaults() {
        // Ensure AWS Secrets Manager is not used (use env vars only)
        env::remove_var("AWS_SECRETS_JWT_NAME");
        // Set required JWT_SECRET for test
        env::set_var("JWT_SECRET", "test-secret-key");

        // This will use defaults for missing env vars
        let config = Config::from_env().await;
        assert!(
            config.is_ok(),
            "Config should load with defaults: {:?}",
            config.err()
        );

        // Clean up
        env::remove_var("JWT_SECRET");
    }

    #[test]
    fn test_jwt_config_from_env() {
        // Set test environment variables
        env::set_var("JWT_SECRET", "test-secret-key");
        env::set_var("JWT_ALGORITHM", "HS256");
        env::set_var("JWT_ISSUER", "test-issuer");
        env::set_var("JWT_AUDIENCE", "api,web,mobile");
        env::set_var("JWT_EXPIRY_SECONDS", "7200");

        let config = Config::jwt_from_env().unwrap();

        assert_eq!(config.signing_key, "test-secret-key");
        assert_eq!(config.algorithm, "HS256");
        assert_eq!(config.issuer, "test-issuer");
        assert_eq!(config.audience, vec!["api", "web", "mobile"]);
        assert_eq!(config.expiry_seconds, 7200);
        assert!(config.validation_key.is_none());

        // Clean up
        env::remove_var("JWT_SECRET");
        env::remove_var("JWT_ALGORITHM");
        env::remove_var("JWT_ISSUER");
        env::remove_var("JWT_AUDIENCE");
        env::remove_var("JWT_EXPIRY_SECONDS");
    }
}
