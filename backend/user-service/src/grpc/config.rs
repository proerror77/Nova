//! gRPC client configuration

use serde::{Deserialize, Serialize};
use std::time::Duration;

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
            .map(|s| s.to_lowercase() == "true")
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
        })
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
    }

    #[test]
    fn test_config_timeouts() {
        let config = GrpcClientConfig::default();
        assert_eq!(config.connection_timeout(), Duration::from_secs(10));
        assert_eq!(config.request_timeout(), Duration::from_secs(30));
    }
}
