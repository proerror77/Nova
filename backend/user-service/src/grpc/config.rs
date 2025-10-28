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
}

impl GrpcClientConfig {
    /// Create a new gRPC client configuration
    pub fn new(
        content_service_url: String,
        media_service_url: String,
    ) -> Self {
        Self {
            content_service_url,
            media_service_url,
            connection_timeout_secs: 10,
            request_timeout_secs: 30,
            max_concurrent_streams: 100,
            enable_health_check: true,
            health_check_interval_secs: 30,
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

    /// Load configuration from environment variables
    pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        let content_service_url = std::env::var("CONTENT_SERVICE_GRPC_URL")
            .unwrap_or_else(|_| "http://localhost:9081".to_string());

        let media_service_url = std::env::var("MEDIA_SERVICE_GRPC_URL")
            .unwrap_or_else(|_| "http://localhost:9082".to_string());

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

        Ok(Self {
            content_service_url,
            media_service_url,
            connection_timeout_secs,
            request_timeout_secs,
            max_concurrent_streams,
            enable_health_check,
            health_check_interval_secs,
        })
    }
}

impl Default for GrpcClientConfig {
    fn default() -> Self {
        Self::new(
            "http://localhost:9081".to_string(),
            "http://localhost:9082".to_string(),
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
    }

    #[test]
    fn test_config_timeouts() {
        let config = GrpcClientConfig::default();
        assert_eq!(config.connection_timeout(), Duration::from_secs(10));
        assert_eq!(config.request_timeout(), Duration::from_secs(30));
    }
}
