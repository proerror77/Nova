//! Database configuration

use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use url::Url;
use validator::Validate;

/// Database configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct DatabaseConfig {
    /// Database host
    #[validate(length(min = 1))]
    pub host: String,

    /// Database port
    #[validate(range(min = 1, max = 65535))]
    pub port: u16,

    /// Database name
    #[validate(length(min = 1))]
    pub database: String,

    /// Database username
    #[validate(length(min = 1))]
    pub username: String,

    /// Database password (secret)
    #[serde(skip_serializing)]
    pub password: SecretString,

    /// Use SSL/TLS
    #[serde(default)]
    pub ssl_mode: SslMode,

    /// Connection pool configuration
    #[serde(default)]
    pub pool: PoolConfig,

    /// Query timeout in seconds
    #[serde(default = "default_query_timeout")]
    pub query_timeout_secs: u64,

    /// Enable query logging (debug only)
    #[serde(default)]
    pub log_queries: bool,

    /// Read replicas for load balancing
    #[serde(default)]
    pub read_replicas: Vec<ReplicaConfig>,
}

fn default_query_timeout() -> u64 {
    30
}

impl DatabaseConfig {
    /// Get connection URL for the primary database
    pub fn connection_url(&self) -> SecretString {
        let password = self.password.expose_secret();
        let ssl_param = match self.ssl_mode {
            SslMode::Disable => "?sslmode=disable",
            SslMode::Require => "?sslmode=require",
            SslMode::VerifyCa => "?sslmode=verify-ca",
            SslMode::VerifyFull => "?sslmode=verify-full",
        };

        SecretString::from(format!(
            "postgres://{}:{}@{}:{}/{}{}",
            self.username,
            password,
            self.host,
            self.port,
            self.database,
            ssl_param
        ))
    }

    /// Get connection URL for a read replica by index
    pub fn replica_url(&self, index: usize) -> Option<SecretString> {
        self.read_replicas.get(index).map(|replica| {
            let password = self.password.expose_secret();
            SecretString::from(format!(
                "postgres://{}:{}@{}:{}/{}",
                self.username,
                password,
                replica.host,
                replica.port,
                self.database
            ))
        })
    }

    /// Get query timeout as Duration
    pub fn query_timeout(&self) -> Duration {
        Duration::from_secs(self.query_timeout_secs)
    }
}

/// SSL/TLS mode for database connections
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SslMode {
    /// No SSL
    Disable,
    /// SSL required
    #[default]
    Require,
    /// Verify CA certificate
    VerifyCa,
    /// Full verification
    VerifyFull,
}

/// Connection pool configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct PoolConfig {
    /// Maximum number of connections
    #[validate(range(min = 1, max = 1000))]
    #[serde(default = "default_max_connections")]
    pub max_connections: u32,

    /// Minimum number of connections
    #[validate(range(min = 0, max = 1000))]
    #[serde(default = "default_min_connections")]
    pub min_connections: u32,

    /// Connection timeout in seconds
    #[serde(default = "default_connect_timeout")]
    pub connect_timeout_secs: u64,

    /// Idle timeout in seconds
    #[serde(default = "default_idle_timeout")]
    pub idle_timeout_secs: u64,

    /// Maximum lifetime of a connection in seconds
    #[serde(default = "default_max_lifetime")]
    pub max_lifetime_secs: u64,

    /// Time to wait for a connection from the pool
    #[serde(default = "default_acquire_timeout")]
    pub acquire_timeout_secs: u64,
}

fn default_max_connections() -> u32 {
    20
}

fn default_min_connections() -> u32 {
    5
}

fn default_connect_timeout() -> u64 {
    5
}

fn default_idle_timeout() -> u64 {
    300
}

fn default_max_lifetime() -> u64 {
    1800
}

fn default_acquire_timeout() -> u64 {
    10
}

impl Default for PoolConfig {
    fn default() -> Self {
        Self {
            max_connections: default_max_connections(),
            min_connections: default_min_connections(),
            connect_timeout_secs: default_connect_timeout(),
            idle_timeout_secs: default_idle_timeout(),
            max_lifetime_secs: default_max_lifetime(),
            acquire_timeout_secs: default_acquire_timeout(),
        }
    }
}

impl PoolConfig {
    /// Get connection timeout as Duration
    pub fn connect_timeout(&self) -> Duration {
        Duration::from_secs(self.connect_timeout_secs)
    }

    /// Get idle timeout as Duration
    pub fn idle_timeout(&self) -> Duration {
        Duration::from_secs(self.idle_timeout_secs)
    }

    /// Get max lifetime as Duration
    pub fn max_lifetime(&self) -> Duration {
        Duration::from_secs(self.max_lifetime_secs)
    }

    /// Get acquire timeout as Duration
    pub fn acquire_timeout(&self) -> Duration {
        Duration::from_secs(self.acquire_timeout_secs)
    }
}

/// Read replica configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct ReplicaConfig {
    /// Replica host
    #[validate(length(min = 1))]
    pub host: String,

    /// Replica port
    #[validate(range(min = 1, max = 65535))]
    pub port: u16,

    /// Weight for load balancing (higher = more traffic)
    #[validate(range(min = 1, max = 100))]
    #[serde(default = "default_weight")]
    pub weight: u8,

    /// Whether this replica is active
    #[serde(default = "default_active")]
    pub active: bool,
}

fn default_weight() -> u8 {
    10
}

fn default_active() -> bool {
    true
}

/// Database type
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DatabaseType {
    PostgreSQL,
    MySQL,
    SQLite,
    ClickHouse,
    MongoDB,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_connection_url() {
        let config = DatabaseConfig {
            host: "localhost".to_string(),
            port: 5432,
            database: "nova".to_string(),
            username: "user".to_string(),
            password: SecretString::from("pass"),
            ssl_mode: SslMode::Require,
            pool: PoolConfig::default(),
            query_timeout_secs: 30,
            log_queries: false,
            read_replicas: vec![],
        };

        let url = config.connection_url();
        assert!(url.expose_secret().contains("postgres://"));
        assert!(url.expose_secret().contains("@localhost:5432/nova"));
        assert!(url.expose_secret().contains("sslmode=require"));
    }

    #[test]
    fn test_pool_config_defaults() {
        let pool = PoolConfig::default();
        assert_eq!(pool.max_connections, 20);
        assert_eq!(pool.min_connections, 5);
        assert_eq!(pool.connect_timeout(), Duration::from_secs(5));
    }
}