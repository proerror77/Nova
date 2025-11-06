/// gRPC Configuration
///
/// Manages service endpoint configuration for all inter-service gRPC calls.
/// Supports environment-based configuration for different deployments.
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::time::Duration;

use tonic::transport::{Certificate, Channel, ClientTlsConfig, Endpoint, Identity};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GrpcConfig {
    /// Auth Service endpoint
    pub auth_service_url: String,

    /// User Service endpoint
    pub user_service_url: String,

    /// Messaging Service endpoint
    pub messaging_service_url: String,

    /// Content Service endpoint
    pub content_service_url: String,

    /// Feed Service endpoint
    pub feed_service_url: String,

    /// Search Service endpoint
    pub search_service_url: String,

    /// Media Service endpoint
    pub media_service_url: String,

    /// Notification Service endpoint
    pub notification_service_url: String,

    /// Streaming Service endpoint
    pub streaming_service_url: String,

    /// CDN Service endpoint
    pub cdn_service_url: String,

    /// Events Service endpoint
    pub events_service_url: String,

    /// Video Service endpoint
    pub video_service_url: String,

    /// gRPC connection timeout in seconds
    pub connection_timeout_secs: u64,

    /// gRPC request timeout in seconds
    pub request_timeout_secs: u64,

    /// Maximum concurrent streams per connection
    pub max_concurrent_streams: u32,

    /// HTTP/2 keep-alive interval in seconds
    pub keepalive_interval_secs: u64,

    /// HTTP/2 keep-alive timeout in seconds
    pub keepalive_timeout_secs: u64,

    /// Enable connection pooling
    pub enable_connection_pooling: bool,

    /// Connection pool size
    pub connection_pool_size: usize,

    /// Enable TLS/mTLS for gRPC clients
    pub tls_enabled: bool,
    /// Optional custom domain name for TLS SNI/verification
    pub tls_domain_name: Option<String>,
    /// Path to CA certificate (PEM)
    pub tls_ca_cert_path: Option<String>,
    /// Path to client certificate (PEM) for mTLS
    pub tls_client_cert_path: Option<String>,
    /// Path to client private key (PEM) for mTLS
    pub tls_client_key_path: Option<String>,
}

impl GrpcConfig {
    /// Load configuration from environment variables
    /// Falls back to defaults for development
    pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        let config = Self {
            auth_service_url: env::var("GRPC_AUTH_SERVICE_URL")
                .unwrap_or_else(|_| "http://auth-service:9080".to_string()),
            user_service_url: env::var("GRPC_USER_SERVICE_URL")
                .unwrap_or_else(|_| "http://user-service:9080".to_string()),
            messaging_service_url: env::var("GRPC_MESSAGING_SERVICE_URL")
                .unwrap_or_else(|_| "http://messaging-service:9080".to_string()),
            content_service_url: env::var("GRPC_CONTENT_SERVICE_URL")
                .unwrap_or_else(|_| "http://content-service:9080".to_string()),
            feed_service_url: env::var("GRPC_FEED_SERVICE_URL")
                .unwrap_or_else(|_| "http://feed-service:9080".to_string()),
            search_service_url: env::var("GRPC_SEARCH_SERVICE_URL")
                .unwrap_or_else(|_| "http://search-service:9080".to_string()),
            media_service_url: env::var("GRPC_MEDIA_SERVICE_URL")
                .unwrap_or_else(|_| "http://media-service:9080".to_string()),
            notification_service_url: env::var("GRPC_NOTIFICATION_SERVICE_URL")
                .unwrap_or_else(|_| "http://notification-service:9080".to_string()),
            streaming_service_url: env::var("GRPC_STREAMING_SERVICE_URL")
                .unwrap_or_else(|_| "http://streaming-service:9080".to_string()),
            cdn_service_url: env::var("GRPC_CDN_SERVICE_URL")
                .unwrap_or_else(|_| "http://cdn-service:9080".to_string()),
            events_service_url: env::var("GRPC_EVENTS_SERVICE_URL")
                .unwrap_or_else(|_| "http://events-service:9080".to_string()),
            video_service_url: env::var("GRPC_VIDEO_SERVICE_URL")
                .unwrap_or_else(|_| "http://video-service:9080".to_string()),
            connection_timeout_secs: env::var("GRPC_CONNECTION_TIMEOUT_SECS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(10),
            request_timeout_secs: env::var("GRPC_REQUEST_TIMEOUT_SECS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(30),
            max_concurrent_streams: env::var("GRPC_MAX_CONCURRENT_STREAMS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(1000),
            keepalive_interval_secs: env::var("GRPC_KEEPALIVE_INTERVAL_SECS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(30),
            keepalive_timeout_secs: env::var("GRPC_KEEPALIVE_TIMEOUT_SECS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(10),
            enable_connection_pooling: env::var("GRPC_ENABLE_CONNECTION_POOLING")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(true),
            connection_pool_size: env::var("GRPC_CONNECTION_POOL_SIZE")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(10),

            // TLS/mTLS
            tls_enabled: env::var("GRPC_TLS_ENABLED")
                .map(|v| matches!(v.as_str(), "1" | "true" | "TRUE"))
                .unwrap_or(false),
            tls_domain_name: env::var("GRPC_TLS_DOMAIN_NAME").ok(),
            tls_ca_cert_path: env::var("GRPC_TLS_CA_CERT_PATH").ok(),
            tls_client_cert_path: env::var("GRPC_TLS_CLIENT_CERT_PATH").ok(),
            tls_client_key_path: env::var("GRPC_TLS_CLIENT_KEY_PATH").ok(),
        };

        Ok(config)
    }

    /// Configuration for development/testing
    pub fn development() -> Self {
        Self {
            auth_service_url: "http://localhost:9080".to_string(),
            user_service_url: "http://localhost:9081".to_string(),
            messaging_service_url: "http://localhost:9082".to_string(),
            content_service_url: "http://localhost:9083".to_string(),
            feed_service_url: "http://localhost:9084".to_string(),
            search_service_url: "http://localhost:9085".to_string(),
            media_service_url: "http://localhost:9086".to_string(),
            notification_service_url: "http://localhost:9087".to_string(),
            streaming_service_url: "http://localhost:9088".to_string(),
            cdn_service_url: "http://localhost:9089".to_string(),
            events_service_url: "http://localhost:9090".to_string(),
            video_service_url: "http://localhost:9091".to_string(),
            connection_timeout_secs: 10,
            request_timeout_secs: 30,
            max_concurrent_streams: 1000,
            keepalive_interval_secs: 30,
            keepalive_timeout_secs: 10,
            enable_connection_pooling: true,
            connection_pool_size: 10,

            tls_enabled: false,
            tls_domain_name: None,
            tls_ca_cert_path: None,
            tls_client_cert_path: None,
            tls_client_key_path: None,
        }
    }

    /// Build a tonic Endpoint from URL with timeouts/keepalive and optional TLS/mTLS
    pub fn make_endpoint(&self, url: &str) -> Result<Endpoint, Box<dyn std::error::Error>> {
        let mut ep = Endpoint::from_shared(url.to_string())?
            .connect_timeout(Duration::from_secs(self.connection_timeout_secs))
            .timeout(Duration::from_secs(self.request_timeout_secs))
            .http2_keep_alive_interval(Duration::from_secs(self.keepalive_interval_secs))
            .keep_alive_timeout(Duration::from_secs(self.keepalive_timeout_secs))
            .tcp_nodelay(true)
            .concurrency_limit(self.max_concurrent_streams as usize);

        if self.tls_enabled {
            // CA certificate (server verification)
            let mut tls = ClientTlsConfig::new();

            if let Some(ca_path) = &self.tls_ca_cert_path {
                let ca_pem = fs::read(ca_path)?;
                tls = tls.ca_certificate(Certificate::from_pem(ca_pem));
            }

            // Domain override if provided
            if let Some(domain) = &self.tls_domain_name {
                tls = tls.domain_name(domain);
            }

            // Client identity for mTLS if provided
            if let (Some(cert_path), Some(key_path)) =
                (&self.tls_client_cert_path, &self.tls_client_key_path)
            {
                let cert_pem = fs::read(cert_path)?;
                let key_pem = fs::read(key_path)?;
                let identity = Identity::from_pem(cert_pem, key_pem);
                tls = tls.identity(identity);
            }

            ep = ep.tls_config(tls)?;
        }

        Ok(ep)
    }

    /// Connect to a Channel using this configuration
    pub async fn connect_channel(&self, url: &str) -> Result<Channel, Box<dyn std::error::Error>> {
        Ok(self.make_endpoint(url)?.connect().await?)
    }
}
