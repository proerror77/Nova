//! Redis configuration

use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use validator::Validate;

/// Redis configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct RedisConfig {
    /// Redis mode
    #[serde(default)]
    pub mode: RedisMode,

    /// Connection configuration based on mode
    #[serde(flatten)]
    pub connection: ConnectionConfig,

    /// Database number (0-15)
    #[validate(range(min = 0, max = 15))]
    #[serde(default)]
    pub database: u8,

    /// Password (if required)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub password: Option<SecretString>,

    /// Username (for ACL)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub username: Option<String>,

    /// Connection pool configuration
    #[serde(default)]
    pub pool: RedisPoolConfig,

    /// Key prefix for namespacing
    #[serde(default)]
    pub key_prefix: Option<String>,

    /// Enable connection keep-alive
    #[serde(default = "default_keep_alive")]
    pub keep_alive: bool,

    /// TLS configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tls: Option<RedisTlsConfig>,
}

fn default_keep_alive() -> bool {
    true
}

impl RedisConfig {
    /// Get Redis connection URL
    pub fn connection_url(&self) -> SecretString {
        let auth = if let Some(password) = &self.password {
            if let Some(username) = &self.username {
                format!("{}:{}@", username, password.expose_secret())
            } else {
                format!(":{}@", password.expose_secret())
            }
        } else {
            String::new()
        };

        let url = match &self.connection {
            ConnectionConfig::Single { host, port } => {
                format!("redis://{}{}:{}/{}", auth, host, port, self.database)
            }
            ConnectionConfig::Sentinel { .. } => {
                // Sentinel URLs are handled differently
                format!("redis-sentinel://{}", auth)
            }
            ConnectionConfig::Cluster { nodes } => {
                // Cluster mode doesn't support database selection
                let node_urls = nodes
                    .iter()
                    .map(|node| format!("{}:{}", node.host, node.port))
                    .collect::<Vec<_>>()
                    .join(",");
                format!("redis-cluster://{}[{}]", auth, node_urls)
            }
        };

        SecretString::from(url)
    }

    /// Check if using cluster mode
    pub fn is_cluster(&self) -> bool {
        matches!(self.mode, RedisMode::Cluster)
    }

    /// Check if using sentinel mode
    pub fn is_sentinel(&self) -> bool {
        matches!(self.mode, RedisMode::Sentinel)
    }
}

/// Redis deployment mode
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RedisMode {
    /// Single Redis instance
    #[default]
    Single,
    /// Redis Sentinel (high availability)
    Sentinel,
    /// Redis Cluster (sharding)
    Cluster,
}

/// Connection configuration based on mode
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(untagged)]
pub enum ConnectionConfig {
    /// Single instance configuration
    Single {
        /// Redis host
        #[validate(length(min = 1))]
        host: String,

        /// Redis port
        #[validate(range(min = 1, max = 65535))]
        #[serde(default = "default_redis_port")]
        port: u16,
    },

    /// Sentinel configuration
    Sentinel {
        /// Sentinel nodes
        #[validate(length(min = 1))]
        sentinels: Vec<SentinelNode>,

        /// Master set name
        #[validate(length(min = 1))]
        master_name: String,
    },

    /// Cluster configuration
    Cluster {
        /// Cluster nodes
        #[validate(length(min = 1))]
        nodes: Vec<ClusterNode>,
    },
}

fn default_redis_port() -> u16 {
    6379
}

/// Sentinel node configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct SentinelNode {
    /// Sentinel host
    #[validate(length(min = 1))]
    pub host: String,

    /// Sentinel port
    #[validate(range(min = 1, max = 65535))]
    #[serde(default = "default_sentinel_port")]
    pub port: u16,
}

fn default_sentinel_port() -> u16 {
    26379
}

/// Cluster node configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct ClusterNode {
    /// Node host
    #[validate(length(min = 1))]
    pub host: String,

    /// Node port
    #[validate(range(min = 1, max = 65535))]
    #[serde(default = "default_redis_port")]
    pub port: u16,
}

/// Redis connection pool configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct RedisPoolConfig {
    /// Maximum number of connections
    #[validate(range(min = 1, max = 1000))]
    #[serde(default = "default_max_connections")]
    pub max_connections: u32,

    /// Minimum idle connections
    #[validate(range(min = 0, max = 1000))]
    #[serde(default = "default_min_idle")]
    pub min_idle: u32,

    /// Maximum idle connections
    #[validate(range(min = 1, max = 1000))]
    #[serde(default = "default_max_idle")]
    pub max_idle: u32,

    /// Connection timeout in seconds
    #[serde(default = "default_connection_timeout")]
    pub connection_timeout_secs: u64,

    /// Idle timeout in seconds
    #[serde(default = "default_idle_timeout")]
    pub idle_timeout_secs: u64,

    /// Maximum lifetime of a connection in seconds
    #[serde(default = "default_max_lifetime")]
    pub max_lifetime_secs: u64,

    /// Test connections on checkout
    #[serde(default)]
    pub test_on_checkout: bool,
}

fn default_max_connections() -> u32 {
    20
}

fn default_min_idle() -> u32 {
    2
}

fn default_max_idle() -> u32 {
    10
}

fn default_connection_timeout() -> u64 {
    5
}

fn default_idle_timeout() -> u64 {
    300
}

fn default_max_lifetime() -> u64 {
    3600
}

impl Default for RedisPoolConfig {
    fn default() -> Self {
        Self {
            max_connections: default_max_connections(),
            min_idle: default_min_idle(),
            max_idle: default_max_idle(),
            connection_timeout_secs: default_connection_timeout(),
            idle_timeout_secs: default_idle_timeout(),
            max_lifetime_secs: default_max_lifetime(),
            test_on_checkout: false,
        }
    }
}

impl RedisPoolConfig {
    /// Get connection timeout as Duration
    pub fn connection_timeout(&self) -> Duration {
        Duration::from_secs(self.connection_timeout_secs)
    }

    /// Get idle timeout as Duration
    pub fn idle_timeout(&self) -> Duration {
        Duration::from_secs(self.idle_timeout_secs)
    }

    /// Get max lifetime as Duration
    pub fn max_lifetime(&self) -> Duration {
        Duration::from_secs(self.max_lifetime_secs)
    }
}

/// Redis TLS configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RedisTlsConfig {
    /// Enable TLS
    #[serde(default = "default_enable_tls")]
    pub enabled: bool,

    /// CA certificate path
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ca_cert_path: Option<String>,

    /// Client certificate path
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_cert_path: Option<String>,

    /// Client key path
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_key_path: Option<String>,

    /// Server name for SNI
    #[serde(skip_serializing_if = "Option::is_none")]
    pub server_name: Option<String>,
}

fn default_enable_tls() -> bool {
    true
}

/// Redis cache configuration (higher-level)
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CacheConfig {
    /// Default TTL in seconds
    #[serde(default = "default_ttl")]
    pub default_ttl_secs: u64,

    /// Maximum TTL in seconds
    #[serde(default = "default_max_ttl")]
    pub max_ttl_secs: u64,

    /// Enable cache warming
    #[serde(default)]
    pub enable_warming: bool,

    /// Cache key versioning
    #[serde(default = "default_cache_version")]
    pub version: u32,

    /// Serialization format
    #[serde(default)]
    pub serialization: SerializationFormat,
}

fn default_ttl() -> u64 {
    3600 // 1 hour
}

fn default_max_ttl() -> u64 {
    86400 // 24 hours
}

fn default_cache_version() -> u32 {
    1
}

/// Serialization format for cached values
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum SerializationFormat {
    /// JSON serialization
    #[default]
    Json,
    /// MessagePack serialization
    MessagePack,
    /// Protocol Buffers
    Protobuf,
    /// Binary (raw bytes)
    Binary,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_single_redis_url() {
        let config = RedisConfig {
            mode: RedisMode::Single,
            connection: ConnectionConfig::Single {
                host: "localhost".to_string(),
                port: 6379,
            },
            database: 0,
            password: Some(SecretString::from("secret")),
            username: None,
            pool: RedisPoolConfig::default(),
            key_prefix: Some("nova:".to_string()),
            keep_alive: true,
            tls: None,
        };

        let url = config.connection_url();
        assert!(url.expose_secret().starts_with("redis://:secret@localhost:6379/0"));
    }

    #[test]
    fn test_cluster_config() {
        let config = RedisConfig {
            mode: RedisMode::Cluster,
            connection: ConnectionConfig::Cluster {
                nodes: vec![
                    ClusterNode {
                        host: "node1".to_string(),
                        port: 7000,
                    },
                    ClusterNode {
                        host: "node2".to_string(),
                        port: 7001,
                    },
                ],
            },
            database: 0,
            password: None,
            username: None,
            pool: RedisPoolConfig::default(),
            key_prefix: None,
            keep_alive: true,
            tls: None,
        };

        assert!(config.is_cluster());
        let url = config.connection_url();
        assert!(url.expose_secret().contains("redis-cluster://"));
    }
}