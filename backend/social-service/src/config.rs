/// Configuration management for Social Service
///
/// Loads configuration from environment variables.
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

/// Main application configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Application settings
    pub app: AppConfig,
    /// Database configuration
    pub database: DatabaseConfig,
    /// Redis configuration
    pub redis: RedisConfig,
    /// gRPC configuration
    pub grpc: GrpcConfig,
}

/// Application settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    /// Application environment (dev, staging, prod)
    pub env: String,
    /// Server host to bind to
    pub host: String,
    /// HTTP port for health checks
    pub http_port: u16,
}

/// Database configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    /// Database URL
    pub url: String,
    /// Max connections in pool
    #[serde(default = "default_max_connections")]
    pub max_connections: u32,
    /// Min connections in pool
    #[serde(default = "default_min_connections")]
    pub min_connections: u32,
}

/// Redis configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RedisConfig {
    /// Redis URL (redis://host:port or redis+sentinel://...)
    pub url: String,
}

/// gRPC server configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GrpcConfig {
    /// gRPC server port
    pub port: u16,
    /// mTLS server certificate path
    pub server_cert_path: Option<String>,
    /// mTLS server key path
    pub server_key_path: Option<String>,
    /// mTLS CA certificate path
    pub ca_cert_path: Option<String>,
}

// Default values
fn default_max_connections() -> u32 {
    20
}

fn default_min_connections() -> u32 {
    5
}

impl Config {
    /// Load configuration from environment variables
    pub fn from_env() -> Result<Self> {
        let app = AppConfig {
            env: std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string()),
            host: std::env::var("APP_HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
            http_port: std::env::var("PORT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(8006), // social-service default HTTP port
        };

        let database = DatabaseConfig {
            url: std::env::var("DATABASE_URL")
                .context("DATABASE_URL environment variable not set")?,
            max_connections: std::env::var("DB_MAX_CONNECTIONS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_max_connections),
            min_connections: std::env::var("DB_MIN_CONNECTIONS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(default_min_connections),
        };

        let redis = RedisConfig {
            url: std::env::var("REDIS_URL")
                .context("REDIS_URL environment variable not set")?,
        };

        let grpc = GrpcConfig {
            port: std::env::var("GRPC_PORT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(50053), // social-service default gRPC port
            server_cert_path: std::env::var("GRPC_SERVER_CERT_PATH").ok(),
            server_key_path: std::env::var("GRPC_SERVER_KEY_PATH").ok(),
            ca_cert_path: std::env::var("GRPC_CA_CERT_PATH").ok(),
        };

        Ok(Config {
            app,
            database,
            redis,
            grpc,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_values() {
        std::env::set_var("DATABASE_URL", "postgres://test");
        std::env::set_var("REDIS_URL", "redis://localhost");

        let config = Config::from_env().unwrap();

        assert_eq!(config.app.env, "development");
        assert_eq!(config.app.host, "0.0.0.0");
        assert_eq!(config.app.http_port, 8006);
        assert_eq!(config.database.max_connections, 20);
        assert_eq!(config.database.min_connections, 5);
        assert_eq!(config.grpc.port, 50053);
    }
}
