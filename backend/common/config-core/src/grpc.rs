//! gRPC server configuration

use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::time::Duration;
use validator::Validate;

/// gRPC server configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct GrpcConfig {
    /// Server host
    #[validate(length(min = 1))]
    #[serde(default = "default_host")]
    pub host: String,

    /// Server port
    #[validate(range(min = 1, max = 65535))]
    #[serde(default = "default_port")]
    pub port: u16,

    /// Maximum message size in bytes
    #[validate(range(min = 1024, max = 104857600))] // 1KB - 100MB
    #[serde(default = "default_max_message_size")]
    pub max_message_size: usize,

    /// Maximum connection idle time in seconds
    #[serde(default = "default_connection_idle_timeout")]
    pub connection_idle_timeout_secs: u64,

    /// Maximum connection age in seconds
    #[serde(default = "default_max_connection_age")]
    pub max_connection_age_secs: u64,

    /// Keep-alive ping interval in seconds
    #[serde(default = "default_keepalive_interval")]
    pub keepalive_interval_secs: u64,

    /// Keep-alive timeout in seconds
    #[serde(default = "default_keepalive_timeout")]
    pub keepalive_timeout_secs: u64,

    /// Enable reflection for development
    #[serde(default)]
    pub enable_reflection: bool,

    /// Enable health service
    #[serde(default = "default_enable_health")]
    pub enable_health_service: bool,

    /// TLS configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tls: Option<GrpcTlsConfig>,

    /// Rate limiting
    #[serde(default)]
    pub rate_limit: RateLimitConfig,

    /// Service discovery
    #[serde(skip_serializing_if = "Option::is_none")]
    pub service_discovery: Option<ServiceDiscoveryConfig>,
}

fn default_host() -> String {
    "0.0.0.0".to_string()
}

fn default_port() -> u16 {
    50051
}

fn default_max_message_size() -> usize {
    4 * 1024 * 1024 // 4MB
}

fn default_connection_idle_timeout() -> u64 {
    300 // 5 minutes
}

fn default_max_connection_age() -> u64 {
    3600 // 1 hour
}

fn default_keepalive_interval() -> u64 {
    60 // 1 minute
}

fn default_keepalive_timeout() -> u64 {
    20
}

fn default_enable_health() -> bool {
    true
}

impl Default for GrpcConfig {
    fn default() -> Self {
        Self {
            host: default_host(),
            port: default_port(),
            max_message_size: default_max_message_size(),
            connection_idle_timeout_secs: default_connection_idle_timeout(),
            max_connection_age_secs: default_max_connection_age(),
            keepalive_interval_secs: default_keepalive_interval(),
            keepalive_timeout_secs: default_keepalive_timeout(),
            enable_reflection: false,
            enable_health_service: true,
            tls: None,
            rate_limit: RateLimitConfig::default(),
            service_discovery: None,
        }
    }
}

impl GrpcConfig {
    /// Get socket address for binding
    pub fn socket_addr(&self) -> SocketAddr {
        format!("{}:{}", self.host, self.port)
            .parse()
            .expect("Invalid gRPC server address")
    }

    /// Get connection idle timeout as Duration
    pub fn connection_idle_timeout(&self) -> Duration {
        Duration::from_secs(self.connection_idle_timeout_secs)
    }

    /// Get max connection age as Duration
    pub fn max_connection_age(&self) -> Duration {
        Duration::from_secs(self.max_connection_age_secs)
    }

    /// Get keepalive interval as Duration
    pub fn keepalive_interval(&self) -> Duration {
        Duration::from_secs(self.keepalive_interval_secs)
    }

    /// Get keepalive timeout as Duration
    pub fn keepalive_timeout(&self) -> Duration {
        Duration::from_secs(self.keepalive_timeout_secs)
    }
}

/// gRPC TLS configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GrpcTlsConfig {
    /// Path to server certificate
    pub cert_path: String,

    /// Path to server private key
    pub key_path: String,

    /// Path to CA certificate (for client verification)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ca_cert_path: Option<String>,

    /// Require client certificate
    #[serde(default)]
    pub client_auth: bool,
}

/// Rate limiting configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct RateLimitConfig {
    /// Requests per second
    #[validate(range(min = 1, max = 100000))]
    #[serde(default = "default_requests_per_second")]
    pub requests_per_second: u32,

    /// Burst size
    #[validate(range(min = 1, max = 1000))]
    #[serde(default = "default_burst_size")]
    pub burst_size: u32,

    /// Enable rate limiting
    #[serde(default)]
    pub enabled: bool,
}

fn default_requests_per_second() -> u32 {
    1000
}

fn default_burst_size() -> u32 {
    100
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            requests_per_second: default_requests_per_second(),
            burst_size: default_burst_size(),
            enabled: false,
        }
    }
}

/// Service discovery configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ServiceDiscoveryConfig {
    /// Discovery method
    pub method: DiscoveryMethod,

    /// Service name for registration
    pub service_name: String,

    /// Service tags
    #[serde(default)]
    pub tags: Vec<String>,

    /// Health check interval in seconds
    #[serde(default = "default_health_check_interval")]
    pub health_check_interval_secs: u64,

    /// TTL for service registration in seconds
    #[serde(default = "default_ttl")]
    pub ttl_secs: u64,
}

fn default_health_check_interval() -> u64 {
    10
}

fn default_ttl() -> u64 {
    30
}

/// Discovery method
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DiscoveryMethod {
    /// Kubernetes service discovery
    Kubernetes,
    /// Consul service discovery
    Consul {
        address: String,
        token: Option<String>,
    },
    /// Etcd service discovery
    Etcd {
        endpoints: Vec<String>,
    },
    /// DNS-based discovery
    Dns,
}

/// Client-side gRPC configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GrpcClientConfig {
    /// Target endpoint
    pub endpoint: String,

    /// Connection timeout in seconds
    #[serde(default = "default_client_timeout")]
    pub connect_timeout_secs: u64,

    /// Request timeout in seconds
    #[serde(default = "default_client_timeout")]
    pub request_timeout_secs: u64,

    /// Enable retry
    #[serde(default = "default_enable_retry")]
    pub enable_retry: bool,

    /// Maximum retry attempts
    #[serde(default = "default_max_retries")]
    pub max_retries: u32,

    /// TLS configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tls: Option<GrpcClientTlsConfig>,
}

fn default_client_timeout() -> u64 {
    30
}

fn default_enable_retry() -> bool {
    true
}

fn default_max_retries() -> u32 {
    3
}

/// Client-side TLS configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GrpcClientTlsConfig {
    /// Server name for verification
    pub domain_name: String,

    /// Path to CA certificate
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ca_cert_path: Option<String>,

    /// Client certificate for mTLS
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_cert_path: Option<String>,

    /// Client key for mTLS
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_key_path: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grpc_config_defaults() {
        let config = GrpcConfig::default();
        assert_eq!(config.host, "0.0.0.0");
        assert_eq!(config.port, 50051);
        assert_eq!(config.max_message_size, 4 * 1024 * 1024);
        assert!(config.enable_health_service);
        assert!(!config.enable_reflection);
    }

    #[test]
    fn test_socket_addr() {
        let config = GrpcConfig {
            host: "127.0.0.1".to_string(),
            port: 9090,
            ..Default::default()
        };

        let addr = config.socket_addr();
        assert_eq!(addr.to_string(), "127.0.0.1:9090");
    }
}