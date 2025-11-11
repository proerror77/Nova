//! HTTP server configuration

use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::time::Duration;
use validator::Validate;

/// HTTP server configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct HttpServerConfig {
    /// Server host
    #[validate(length(min = 1))]
    #[serde(default = "default_host")]
    pub host: String,

    /// Server port
    #[validate(range(min = 1, max = 65535))]
    #[serde(default = "default_port")]
    pub port: u16,

    /// Request timeout in seconds
    #[serde(default = "default_request_timeout")]
    pub request_timeout_secs: u64,

    /// Keep-alive timeout in seconds
    #[serde(default = "default_keepalive_timeout")]
    pub keepalive_timeout_secs: u64,

    /// Maximum request body size in bytes
    #[validate(range(min = 1024, max = 104857600))] // 1KB - 100MB
    #[serde(default = "default_max_body_size")]
    pub max_body_size: usize,

    /// Number of worker threads (0 = number of CPU cores)
    #[serde(default)]
    pub workers: usize,

    /// Enable compression
    #[serde(default = "default_enable_compression")]
    pub enable_compression: bool,

    /// CORS configuration
    #[serde(default)]
    pub cors: CorsConfig,

    /// TLS configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tls: Option<HttpTlsConfig>,
}

fn default_host() -> String {
    "0.0.0.0".to_string()
}

fn default_port() -> u16 {
    8080
}

fn default_request_timeout() -> u64 {
    30
}

fn default_keepalive_timeout() -> u64 {
    75
}

fn default_max_body_size() -> usize {
    10 * 1024 * 1024 // 10MB
}

fn default_enable_compression() -> bool {
    true
}

impl Default for HttpServerConfig {
    fn default() -> Self {
        Self {
            host: default_host(),
            port: default_port(),
            request_timeout_secs: default_request_timeout(),
            keepalive_timeout_secs: default_keepalive_timeout(),
            max_body_size: default_max_body_size(),
            workers: 0,
            enable_compression: true,
            cors: CorsConfig::default(),
            tls: None,
        }
    }
}

impl HttpServerConfig {
    /// Get socket address for binding
    pub fn socket_addr(&self) -> SocketAddr {
        format!("{}:{}", self.host, self.port)
            .parse()
            .expect("Invalid HTTP server address")
    }

    /// Get request timeout as Duration
    pub fn request_timeout(&self) -> Duration {
        Duration::from_secs(self.request_timeout_secs)
    }

    /// Get keepalive timeout as Duration
    pub fn keepalive_timeout(&self) -> Duration {
        Duration::from_secs(self.keepalive_timeout_secs)
    }

    /// Get base URL for the server
    pub fn base_url(&self) -> String {
        let scheme = if self.tls.is_some() { "https" } else { "http" };
        format!("{}://{}:{}", scheme, self.host, self.port)
    }
}

/// CORS configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CorsConfig {
    /// Enable CORS
    #[serde(default)]
    pub enabled: bool,

    /// Allowed origins
    #[serde(default)]
    pub allowed_origins: Vec<String>,

    /// Allowed methods
    #[serde(default = "default_allowed_methods")]
    pub allowed_methods: Vec<String>,

    /// Allowed headers
    #[serde(default = "default_allowed_headers")]
    pub allowed_headers: Vec<String>,

    /// Exposed headers
    #[serde(default)]
    pub exposed_headers: Vec<String>,

    /// Allow credentials
    #[serde(default)]
    pub allow_credentials: bool,

    /// Max age in seconds for preflight cache
    #[serde(default = "default_max_age")]
    pub max_age_secs: u64,
}

fn default_allowed_methods() -> Vec<String> {
    vec![
        "GET".to_string(),
        "POST".to_string(),
        "PUT".to_string(),
        "DELETE".to_string(),
        "OPTIONS".to_string(),
    ]
}

fn default_allowed_headers() -> Vec<String> {
    vec![
        "Content-Type".to_string(),
        "Authorization".to_string(),
        "Accept".to_string(),
    ]
}

fn default_max_age() -> u64 {
    3600
}

impl Default for CorsConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            allowed_origins: vec![],
            allowed_methods: default_allowed_methods(),
            allowed_headers: default_allowed_headers(),
            exposed_headers: vec![],
            allow_credentials: false,
            max_age_secs: default_max_age(),
        }
    }
}

impl CorsConfig {
    /// Create a permissive CORS config for development
    pub fn development() -> Self {
        Self {
            enabled: true,
            allowed_origins: vec!["*".to_string()],
            allowed_methods: vec!["*".to_string()],
            allowed_headers: vec!["*".to_string()],
            exposed_headers: vec![],
            allow_credentials: true,
            max_age_secs: 3600,
        }
    }
}

/// HTTP TLS configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct HttpTlsConfig {
    /// Path to certificate file
    pub cert_path: String,

    /// Path to private key file
    pub key_path: String,

    /// Minimum TLS version
    #[serde(default = "default_min_tls_version")]
    pub min_version: TlsVersion,
}

fn default_min_tls_version() -> TlsVersion {
    TlsVersion::Tls12
}

/// TLS version
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
pub enum TlsVersion {
    #[serde(rename = "1.2")]
    Tls12,
    #[serde(rename = "1.3")]
    Tls13,
}

/// HTTP client configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct HttpClientConfig {
    /// Base URL for the client
    pub base_url: String,

    /// Request timeout in seconds
    #[serde(default = "default_client_timeout")]
    pub timeout_secs: u64,

    /// Connection pool idle timeout in seconds
    #[serde(default = "default_pool_idle_timeout")]
    pub pool_idle_timeout_secs: u64,

    /// Maximum idle connections per host
    #[serde(default = "default_pool_max_idle")]
    pub pool_max_idle_per_host: usize,

    /// User agent string
    #[serde(default = "default_user_agent")]
    pub user_agent: String,

    /// Enable compression
    #[serde(default = "default_enable_compression")]
    pub enable_compression: bool,

    /// Follow redirects
    #[serde(default = "default_follow_redirects")]
    pub follow_redirects: bool,

    /// Maximum redirect depth
    #[serde(default = "default_max_redirects")]
    pub max_redirects: usize,

    /// TLS configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tls: Option<HttpClientTlsConfig>,
}

fn default_client_timeout() -> u64 {
    30
}

fn default_pool_idle_timeout() -> u64 {
    90
}

fn default_pool_max_idle() -> usize {
    10
}

fn default_user_agent() -> String {
    "Nova/1.0".to_string()
}

fn default_follow_redirects() -> bool {
    true
}

fn default_max_redirects() -> usize {
    10
}

impl HttpClientConfig {
    /// Get timeout as Duration
    pub fn timeout(&self) -> Duration {
        Duration::from_secs(self.timeout_secs)
    }

    /// Get pool idle timeout as Duration
    pub fn pool_idle_timeout(&self) -> Duration {
        Duration::from_secs(self.pool_idle_timeout_secs)
    }
}

/// HTTP client TLS configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct HttpClientTlsConfig {
    /// Accept invalid certificates (DANGEROUS - dev only)
    #[serde(default)]
    pub danger_accept_invalid_certs: bool,

    /// Accept invalid hostnames (DANGEROUS - dev only)
    #[serde(default)]
    pub danger_accept_invalid_hostnames: bool,

    /// Root CA certificate path
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ca_cert_path: Option<String>,

    /// Client certificate path (for mTLS)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_cert_path: Option<String>,

    /// Client key path (for mTLS)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_key_path: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_http_config_defaults() {
        let config = HttpServerConfig::default();
        assert_eq!(config.host, "0.0.0.0");
        assert_eq!(config.port, 8080);
        assert_eq!(config.max_body_size, 10 * 1024 * 1024);
        assert!(config.enable_compression);
    }

    #[test]
    fn test_base_url() {
        let config = HttpServerConfig {
            host: "api.example.com".to_string(),
            port: 443,
            tls: Some(HttpTlsConfig {
                cert_path: "/path/to/cert".to_string(),
                key_path: "/path/to/key".to_string(),
                min_version: TlsVersion::Tls13,
            }),
            ..Default::default()
        };

        assert_eq!(config.base_url(), "https://api.example.com:443");
    }

    #[test]
    fn test_cors_development() {
        let cors = CorsConfig::development();
        assert!(cors.enabled);
        assert_eq!(cors.allowed_origins, vec!["*"]);
        assert!(cors.allow_credentials);
    }
}