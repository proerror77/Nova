//! gRPC client configuration supporting mTLS

use serde::{Deserialize, Serialize};
use std::fs;
use std::time::Duration;
use tonic::transport::{Certificate, ClientTlsConfig, Identity};
use url::Url;

/// Configuration for gRPC client connections
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GrpcClientConfig {
    /// Content service gRPC address
    pub content_service_url: String,
    /// Media service gRPC address
    pub media_service_url: String,
    /// Auth service gRPC address
    pub auth_service_url: String,
    /// Connection timeout in seconds
    pub connection_timeout_secs: u64,
    /// Request timeout in seconds
    pub request_timeout_secs: u64,
    /// Maximum concurrent requests per connection
    pub max_concurrent_streams: u32,
    /// Enable health checking
    pub enable_health_check: bool,
    /// Health check interval in seconds
    pub health_check_interval_secs: u64,
    /// gRPC client connection pool size per service
    pub pool_size: usize,
    /// Number of connection retry attempts
    pub connect_retry_attempts: u32,
    /// Backoff between connection retries in milliseconds
    pub connect_retry_backoff_ms: u64,
    /// HTTP/2 keep-alive interval in seconds
    pub http2_keep_alive_interval_secs: u64,
    /// Whether to enable mutual TLS
    #[serde(default)]
    pub tls_enabled: bool,
    /// Optional override for the TLS domain name
    pub tls_domain_name: Option<String>,
    /// PEM encoded CA certificate (only used when TLS enabled)
    pub tls_ca_certificate: Option<String>,
    /// PEM encoded client certificate (only used when TLS enabled)
    pub tls_client_certificate: Option<String>,
    /// PEM encoded client private key (only used when TLS enabled)
    pub tls_client_private_key: Option<String>,
}

impl GrpcClientConfig {
    /// Create a new gRPC client configuration
    pub fn new(
        content_service_url: String,
        media_service_url: String,
        auth_service_url: String,
    ) -> Self {
        Self {
            content_service_url,
            media_service_url,
            auth_service_url,
            connection_timeout_secs: 10,
            request_timeout_secs: 30,
            max_concurrent_streams: 100,
            enable_health_check: true,
            health_check_interval_secs: 30,
            pool_size: 4,
            connect_retry_attempts: 3,
            connect_retry_backoff_ms: 200,
            http2_keep_alive_interval_secs: 30,
            tls_enabled: false,
            tls_domain_name: None,
            tls_ca_certificate: None,
            tls_client_certificate: None,
            tls_client_private_key: None,
        }
    }

    /// Get connection timeout as Duration
    pub fn connection_timeout(&self) -> Duration {
        Duration::from_secs(self.connection_timeout_secs)
    }

    /// Get request timeout as Duration
    pub fn request_timeout(&self) -> Duration {
        Duration::from_secs(self.request_timeout_secs)
    }

    /// Get health check interval as Duration
    pub fn health_check_interval(&self) -> Duration {
        Duration::from_secs(self.health_check_interval_secs)
    }

    /// Get gRPC client pool size (minimum 1)
    pub fn pool_size(&self) -> usize {
        self.pool_size.max(1)
    }

    /// Number of connection retry attempts
    pub fn connect_retry_attempts(&self) -> u32 {
        self.connect_retry_attempts.max(1)
    }

    /// Backoff duration between connection retries
    pub fn connect_retry_backoff(&self) -> Duration {
        let millis = self.connect_retry_backoff_ms.max(50);
        Duration::from_millis(millis)
    }

    /// HTTP/2 keep-alive interval
    pub fn http2_keep_alive_interval(&self) -> Duration {
        let secs = self.http2_keep_alive_interval_secs.max(5);
        Duration::from_secs(secs)
    }

    /// Load configuration from environment variables
    pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        let content_service_url = std::env::var("CONTENT_SERVICE_GRPC_URL")
            .unwrap_or_else(|_| "http://localhost:9081".to_string());

        let media_service_url = std::env::var("MEDIA_SERVICE_GRPC_URL")
            .unwrap_or_else(|_| "http://localhost:9082".to_string());

        let auth_service_url = std::env::var("AUTH_SERVICE_GRPC_URL")
            .unwrap_or_else(|_| "http://localhost:9080".to_string());

        let connection_timeout_secs = std::env::var("GRPC_CONNECTION_TIMEOUT_SECS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(10);

        let request_timeout_secs = std::env::var("GRPC_REQUEST_TIMEOUT_SECS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(30);

        let max_concurrent_streams = std::env::var("GRPC_MAX_CONCURRENT_STREAMS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(100);

        let enable_health_check = std::env::var("GRPC_ENABLE_HEALTH_CHECK")
            .ok()
            .map(|s| matches!(s.to_lowercase().as_str(), "true" | "1" | "yes"))
            .unwrap_or(true);

        let health_check_interval_secs = std::env::var("GRPC_HEALTH_CHECK_INTERVAL_SECS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(30);

        let pool_size = std::env::var("GRPC_CLIENT_POOL_SIZE")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(4);

        let connect_retry_attempts = std::env::var("GRPC_CONNECT_RETRY_ATTEMPTS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(3);

        let connect_retry_backoff_ms = std::env::var("GRPC_CONNECT_RETRY_BACKOFF_MS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(200);

        let http2_keep_alive_interval_secs = std::env::var("GRPC_HTTP2_KEEP_ALIVE_SECS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(30);

        let tls_enabled = std::env::var("GRPC_TLS_ENABLED")
            .ok()
            .map(|s| matches!(s.to_lowercase().as_str(), "true" | "1" | "yes"))
            .unwrap_or(false);

        let (tls_ca_certificate, tls_client_certificate, tls_client_private_key, tls_domain_name) =
            if tls_enabled {
                let ca_path = std::env::var("GRPC_TLS_CA_CERT_PATH")
                    .map_err(|_| "GRPC_TLS_CA_CERT_PATH must be set when GRPC_TLS_ENABLED=true")?;
                let client_cert_path =
                    std::env::var("GRPC_TLS_CLIENT_CERT_PATH").map_err(|_| {
                        "GRPC_TLS_CLIENT_CERT_PATH must be set when GRPC_TLS_ENABLED=true"
                    })?;
                let client_key_path = std::env::var("GRPC_TLS_CLIENT_KEY_PATH").map_err(|_| {
                    "GRPC_TLS_CLIENT_KEY_PATH must be set when GRPC_TLS_ENABLED=true"
                })?;

                let ca_certificate = fs::read_to_string(&ca_path).map_err(|e| {
                    format!(
                        "Failed to read GRPC TLS CA certificate from {}: {}",
                        ca_path, e
                    )
                })?;
                let client_certificate = fs::read_to_string(&client_cert_path).map_err(|e| {
                    format!(
                        "Failed to read GRPC TLS client certificate from {}: {}",
                        client_cert_path, e
                    )
                })?;
                let client_key = fs::read_to_string(&client_key_path).map_err(|e| {
                    format!(
                        "Failed to read GRPC TLS client key from {}: {}",
                        client_key_path, e
                    )
                })?;

                let domain_override = std::env::var("GRPC_TLS_DOMAIN_NAME")
                    .ok()
                    .filter(|s| !s.is_empty());

                (
                    Some(ca_certificate),
                    Some(client_certificate),
                    Some(client_key),
                    domain_override,
                )
            } else {
                (None, None, None, None)
            };

        Ok(Self {
            content_service_url,
            media_service_url,
            auth_service_url,
            connection_timeout_secs,
            request_timeout_secs,
            max_concurrent_streams,
            enable_health_check,
            health_check_interval_secs,
            pool_size,
            connect_retry_attempts,
            connect_retry_backoff_ms,
            http2_keep_alive_interval_secs,
            tls_enabled,
            tls_domain_name,
            tls_ca_certificate,
            tls_client_certificate,
            tls_client_private_key,
        })
    }

    fn parsed_url(&self, raw_url: &str) -> Result<Url, Box<dyn std::error::Error>> {
        let mut parsed = Url::parse(raw_url)?;
        if self.tls_enabled && parsed.scheme() == "http" {
            parsed
                .set_scheme("https")
                .map_err(|_| "Failed to update gRPC URL scheme to https for TLS")?;
        }
        Ok(parsed)
    }

    /// Return a URL suitable for tonic Endpoint, applying TLS scheme if required.
    pub fn endpoint_url(&self, raw_url: &str) -> Result<String, Box<dyn std::error::Error>> {
        Ok(self.parsed_url(raw_url)?.to_string())
    }

    /// Build a ClientTlsConfig when TLS is enabled.
    pub fn tls_config_for(
        &self,
        service_url: &str,
    ) -> Result<Option<ClientTlsConfig>, Box<dyn std::error::Error>> {
        if !self.tls_enabled {
            return Ok(None);
        }

        let ca_pem = self
            .tls_ca_certificate
            .as_ref()
            .ok_or("GRPC TLS enabled but CA certificate missing")?;
        let client_cert = self
            .tls_client_certificate
            .as_ref()
            .ok_or("GRPC TLS enabled but client certificate missing")?;
        let client_key = self
            .tls_client_private_key
            .as_ref()
            .ok_or("GRPC TLS enabled but client key missing")?;

        let parsed = self.parsed_url(service_url)?;
        let domain = if let Some(domain) = &self.tls_domain_name {
            domain.clone()
        } else {
            parsed
                .host_str()
                .ok_or("Unable to determine host for TLS domain name")?
                .to_string()
        };

        let ca = Certificate::from_pem(ca_pem.as_bytes());
        let identity = Identity::from_pem(client_cert.as_bytes(), client_key.as_bytes());
        let tls = ClientTlsConfig::new()
            .ca_certificate(ca)
            .identity(identity)
            .domain_name(domain);

        Ok(Some(tls))
    }
}

impl Default for GrpcClientConfig {
    fn default() -> Self {
        Self::new(
            "http://localhost:9081".to_string(),
            "http://localhost:9082".to_string(),
            "http://localhost:9080".to_string(),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = GrpcClientConfig::default();
        assert_eq!(config.content_service_url, "http://localhost:9081");
        assert_eq!(config.media_service_url, "http://localhost:9082");
        assert_eq!(config.connection_timeout_secs, 10);
        assert_eq!(config.request_timeout_secs, 30);
        assert_eq!(config.pool_size(), 4);
        assert!(!config.tls_enabled);
    }

    #[test]
    fn test_config_timeouts() {
        let config = GrpcClientConfig::default();
        assert_eq!(config.connection_timeout(), Duration::from_secs(10));
        assert_eq!(config.request_timeout(), Duration::from_secs(30));
    }
}
