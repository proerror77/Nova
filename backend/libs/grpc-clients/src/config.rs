/// gRPC Configuration
///
/// Manages service endpoint configuration for all inter-service gRPC calls.
/// Supports environment-based configuration for different deployments.
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use tonic::transport::{Certificate, Channel, ClientTlsConfig, Endpoint, Identity};

/// Deployment environment
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Environment {
    Development,
    ProductionLike, // staging + production
}

impl Environment {
    fn from_env() -> Self {
        match env::var("APP_ENV").as_deref() {
            Ok("production") | Ok("staging") => Self::ProductionLike,
            _ => Self::Development,
        }
    }

    fn requires_tls(&self) -> bool {
        matches!(self, Self::ProductionLike)
    }
}

/// Client identity for mutual TLS (mTLS)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientIdentity {
    pub cert_path: PathBuf,
    pub key_path: PathBuf,
}

/// TLS configuration for gRPC clients
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TlsConfig {
    /// TLS disabled (development only)
    Disabled,
    /// TLS enabled with server verification
    Enabled {
        domain_name: String,
        ca_cert_path: PathBuf,
        /// Optional client certificate for mutual TLS
        client_identity: Option<ClientIdentity>,
    },
}

/// Dependency criticality tier for client connections.
///
/// Tier0 = hard dependency (fail fast on startup);
/// Tier1 = soft-critical (start but mark degraded and log warnings);
/// Tier2 = optional (best-effort).
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum DependencyTier {
    Tier0,
    Tier1,
    Tier2,
}

impl DependencyTier {
    fn from_env(var: &str, default: DependencyTier) -> DependencyTier {
        match env::var(var)
            .ok()
            .as_deref()
            .map(str::to_ascii_lowercase)
            .as_deref()
        {
            Some("0") | Some("tier0") | Some("hard") => DependencyTier::Tier0,
            Some("1") | Some("tier1") | Some("soft") | Some("soft-critical") => {
                DependencyTier::Tier1
            }
            Some("2") | Some("tier2") | Some("optional") => DependencyTier::Tier2,
            _ => default,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceEndpoint {
    pub url: String,
    #[serde(default = "default_tier")]
    pub tier: DependencyTier,
}

const fn default_tier() -> DependencyTier {
    DependencyTier::Tier1
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GrpcConfig {
    /// Identity Service endpoint (renamed from auth-service)
    pub identity_service: ServiceEndpoint,

    /// Content Service endpoint
    pub content_service: ServiceEndpoint,

    /// Feed Service endpoint
    pub feed_service: ServiceEndpoint,

    /// Search Service endpoint
    pub search_service: ServiceEndpoint,

    /// Media Service endpoint
    pub media_service: ServiceEndpoint,

    /// Notification Service endpoint
    pub notification_service: ServiceEndpoint,

    /// Analytics Service endpoint (renamed from events-service)
    pub analytics_service: ServiceEndpoint,

    /// Graph Service endpoint
    pub graph_service: ServiceEndpoint,

    /// Social Service endpoint
    pub social_service: ServiceEndpoint,

    /// Realtime Chat Service endpoint
    pub chat_service: ServiceEndpoint,

    /// Ranking Service endpoint
    pub ranking_service: ServiceEndpoint,

    /// Feature Store endpoint
    pub feature_store: ServiceEndpoint,

    /// Trust & Safety Service endpoint
    pub trust_safety_service: ServiceEndpoint,

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

    /// TLS configuration
    pub tls: TlsConfig,
}

impl GrpcConfig {
    /// Load configuration from environment variables
    /// Falls back to defaults for development
    ///
    /// **Security**: TLS is MANDATORY in production/staging environments.
    /// Attempting to disable TLS in production will cause a startup failure.
    pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        let env = Environment::from_env();
        let tls = Self::load_tls_config(env)?;

        let default_tier0 = DependencyTier::Tier0;
        let default_tier1 = DependencyTier::Tier1;

        let config = Self {
            identity_service: ServiceEndpoint {
                url: env::var("GRPC_IDENTITY_SERVICE_URL")
                    .unwrap_or_else(|_| "http://identity-service:9080".to_string()),
                tier: DependencyTier::from_env("GRPC_IDENTITY_SERVICE_TIER", default_tier0),
            },
            content_service: ServiceEndpoint {
                url: env::var("GRPC_CONTENT_SERVICE_URL")
                    .unwrap_or_else(|_| "http://content-service:9080".to_string()),
                tier: DependencyTier::from_env("GRPC_CONTENT_SERVICE_TIER", default_tier0),
            },
            feed_service: ServiceEndpoint {
                url: env::var("GRPC_FEED_SERVICE_URL")
                    .unwrap_or_else(|_| "http://feed-service:9080".to_string()),
                tier: DependencyTier::from_env("GRPC_FEED_SERVICE_TIER", default_tier1),
            },
            search_service: ServiceEndpoint {
                url: env::var("GRPC_SEARCH_SERVICE_URL")
                    .unwrap_or_else(|_| "http://search-service:9080".to_string()),
                tier: DependencyTier::from_env("GRPC_SEARCH_SERVICE_TIER", default_tier1),
            },
            media_service: ServiceEndpoint {
                url: env::var("GRPC_MEDIA_SERVICE_URL")
                    .unwrap_or_else(|_| "http://media-service:9080".to_string()),
                tier: DependencyTier::from_env("GRPC_MEDIA_SERVICE_TIER", default_tier1),
            },
            notification_service: ServiceEndpoint {
                url: env::var("GRPC_NOTIFICATION_SERVICE_URL")
                    .unwrap_or_else(|_| "http://notification-service:9080".to_string()),
                tier: DependencyTier::from_env("GRPC_NOTIFICATION_SERVICE_TIER", default_tier1),
            },
            analytics_service: ServiceEndpoint {
                url: env::var("GRPC_ANALYTICS_SERVICE_URL")
                    .unwrap_or_else(|_| "http://analytics-service:9080".to_string()),
                tier: DependencyTier::from_env("GRPC_ANALYTICS_SERVICE_TIER", default_tier1),
            },
            graph_service: ServiceEndpoint {
                url: env::var("GRPC_GRAPH_SERVICE_URL")
                    .unwrap_or_else(|_| "http://graph-service:9080".to_string()),
                tier: DependencyTier::from_env("GRPC_GRAPH_SERVICE_TIER", default_tier1),
            },
            social_service: ServiceEndpoint {
                url: env::var("GRPC_SOCIAL_SERVICE_URL")
                    .unwrap_or_else(|_| "http://social-service:9006".to_string()),
                tier: DependencyTier::from_env("GRPC_SOCIAL_SERVICE_TIER", default_tier0),
            },
            chat_service: ServiceEndpoint {
                url: env::var("GRPC_CHAT_SERVICE_URL")
                    .unwrap_or_else(|_| "http://realtime-chat-service:9086".to_string()),
                tier: DependencyTier::from_env("GRPC_CHAT_SERVICE_TIER", default_tier1),
            },
            ranking_service: ServiceEndpoint {
                url: env::var("GRPC_RANKING_SERVICE_URL")
                    .unwrap_or_else(|_| "http://ranking-service:9088".to_string()),
                tier: DependencyTier::from_env("GRPC_RANKING_SERVICE_TIER", default_tier0),
            },
            feature_store: ServiceEndpoint {
                url: env::var("GRPC_FEATURE_STORE_URL")
                    .unwrap_or_else(|_| "http://feature-store:9010".to_string()),
                tier: DependencyTier::from_env("GRPC_FEATURE_STORE_TIER", default_tier1),
            },
            trust_safety_service: ServiceEndpoint {
                url: env::var("GRPC_TRUST_SAFETY_SERVICE_URL")
                    .unwrap_or_else(|_| "http://trust-safety-service:9091".to_string()),
                tier: DependencyTier::from_env("GRPC_TRUST_SAFETY_SERVICE_TIER", default_tier1),
            },
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
            tls,
        };

        Ok(config)
    }

    /// Load TLS configuration with production enforcement
    fn load_tls_config(env: Environment) -> Result<TlsConfig, Box<dyn std::error::Error>> {
        let tls_enabled = env::var("GRPC_TLS_ENABLED")
            .map(|v| matches!(v.as_str(), "1" | "true" | "TRUE"))
            .unwrap_or(env.requires_tls());

        // Production/staging MUST have TLS
        if env.requires_tls() && !tls_enabled {
            return Err(format!(
                "gRPC TLS is MANDATORY in {:?} environment. Set GRPC_TLS_ENABLED=true",
                env
            )
            .into());
        }

        if !tls_enabled {
            tracing::warn!("⚠️  gRPC TLS is DISABLED (development only)");
            return Ok(TlsConfig::Disabled);
        }

        // TLS enabled - validate required configuration
        let domain_name = env::var("GRPC_TLS_DOMAIN_NAME")
            .map_err(|_| "GRPC_TLS_DOMAIN_NAME is required when TLS is enabled")?;

        let ca_cert_path = env::var("GRPC_TLS_CA_CERT_PATH")
            .map(PathBuf::from)
            .map_err(|_| "GRPC_TLS_CA_CERT_PATH is required when TLS is enabled")?;

        // Validate CA cert exists AND is readable
        let ca_pem = fs::read(&ca_cert_path).map_err(|e| {
            format!(
                "Failed to read CA certificate at {}: {}. \
                 Check file permissions (should be 644 or 400) and that the file exists.",
                ca_cert_path.display(),
                e
            )
        })?;

        // Basic PEM format validation
        let ca_pem_str = std::str::from_utf8(&ca_pem).map_err(|_| {
            format!(
                "CA certificate at {} is not valid UTF-8. \
                 Must be valid PEM-encoded X.509 certificate (-----BEGIN CERTIFICATE-----)",
                ca_cert_path.display()
            )
        })?;

        if !ca_pem_str.contains("-----BEGIN CERTIFICATE-----") {
            return Err(format!(
                "Invalid CA certificate format at {}. \
                 Must be valid PEM-encoded X.509 certificate (-----BEGIN CERTIFICATE-----)",
                ca_cert_path.display()
            )
            .into());
        }

        // Optional mTLS client identity
        let client_identity = match (
            env::var("GRPC_TLS_CLIENT_CERT_PATH").ok(),
            env::var("GRPC_TLS_CLIENT_KEY_PATH").ok(),
        ) {
            (Some(cert), Some(key)) => {
                let cert_path = PathBuf::from(cert);
                let key_path = PathBuf::from(key);

                // Validate client cert exists AND is readable
                let cert_pem = fs::read(&cert_path).map_err(|e| {
                    format!(
                        "Failed to read client certificate at {}: {}. \
                         Check file permissions (should be 644 or 400) and that the file exists.",
                        cert_path.display(),
                        e
                    )
                })?;

                // Validate client key exists AND is readable
                let key_pem = fs::read(&key_path).map_err(|e| {
                    format!(
                        "Failed to read client key at {}: {}. \
                         Check file permissions (MUST be 600 or 400 for security) and that the file exists.",
                        key_path.display(),
                        e
                    )
                })?;

                // Basic PEM format validation for cert
                let cert_pem_str = std::str::from_utf8(&cert_pem).map_err(|_| {
                    format!(
                        "Client certificate at {} is not valid UTF-8. \
                         Must be valid PEM-encoded",
                        cert_path.display()
                    )
                })?;

                if !cert_pem_str.contains("-----BEGIN CERTIFICATE-----") {
                    return Err(format!(
                        "Invalid client certificate format at {}. \
                         Must be valid PEM-encoded X.509 certificate (-----BEGIN CERTIFICATE-----)",
                        cert_path.display()
                    )
                    .into());
                }

                // Basic PEM format validation for key
                let key_pem_str = std::str::from_utf8(&key_pem).map_err(|_| {
                    format!(
                        "Client key at {} is not valid UTF-8. \
                         Must be valid PEM-encoded",
                        key_path.display()
                    )
                })?;

                if !key_pem_str.contains("-----BEGIN") || !key_pem_str.contains("PRIVATE KEY") {
                    return Err(format!(
                        "Invalid client key format at {}. \
                         Must be valid PEM-encoded private key (-----BEGIN ... PRIVATE KEY-----)",
                        key_path.display()
                    )
                    .into());
                }

                Some(ClientIdentity {
                    cert_path,
                    key_path,
                })
            }
            (None, None) => None,
            _ => return Err(
                "Both GRPC_TLS_CLIENT_CERT_PATH and GRPC_TLS_CLIENT_KEY_PATH must be set for mTLS"
                    .into(),
            ),
        };

        tracing::info!(
            "✅ gRPC TLS enabled for domain: {} (mTLS: {})",
            domain_name,
            client_identity.is_some()
        );

        Ok(TlsConfig::Enabled {
            domain_name,
            ca_cert_path,
            client_identity,
        })
    }

    /// Configuration for development/testing
    pub fn development() -> Self {
        Self {
            identity_service: ServiceEndpoint {
                url: "http://localhost:9080".to_string(),
                tier: DependencyTier::Tier0,
            },
            content_service: ServiceEndpoint {
                url: "http://localhost:9083".to_string(),
                tier: DependencyTier::Tier0,
            },
            feed_service: ServiceEndpoint {
                url: "http://localhost:9084".to_string(),
                tier: DependencyTier::Tier1,
            },
            search_service: ServiceEndpoint {
                url: "http://localhost:9085".to_string(),
                tier: DependencyTier::Tier1,
            },
            media_service: ServiceEndpoint {
                url: "http://localhost:9086".to_string(),
                tier: DependencyTier::Tier1,
            },
            notification_service: ServiceEndpoint {
                url: "http://localhost:9087".to_string(),
                tier: DependencyTier::Tier1,
            },
            analytics_service: ServiceEndpoint {
                url: "http://localhost:9090".to_string(),
                tier: DependencyTier::Tier1,
            },
            graph_service: ServiceEndpoint {
                url: "http://localhost:50051".to_string(),
                tier: DependencyTier::Tier1,
            },
            social_service: ServiceEndpoint {
                url: "http://localhost:9006".to_string(),
                tier: DependencyTier::Tier0,
            },
            chat_service: ServiceEndpoint {
                url: "http://localhost:9085".to_string(),
                tier: DependencyTier::Tier1,
            },
            ranking_service: ServiceEndpoint {
                url: "http://localhost:9088".to_string(),
                tier: DependencyTier::Tier0,
            },
            feature_store: ServiceEndpoint {
                url: "http://localhost:9010".to_string(),
                tier: DependencyTier::Tier1,
            },
            trust_safety_service: ServiceEndpoint {
                url: "http://localhost:9091".to_string(),
                tier: DependencyTier::Tier1,
            },
            connection_timeout_secs: 10,
            request_timeout_secs: 30,
            max_concurrent_streams: 1000,
            keepalive_interval_secs: 30,
            keepalive_timeout_secs: 10,
            enable_connection_pooling: true,
            connection_pool_size: 10,
            tls: TlsConfig::Disabled,
        }
    }

    /// Build a tonic Endpoint from URL with timeouts/keepalive and optional TLS/mTLS
    pub fn make_endpoint(&self, url: &str) -> Result<Endpoint, Box<dyn std::error::Error>> {
        let ep = Endpoint::from_shared(url.to_string())?
            .connect_timeout(Duration::from_secs(self.connection_timeout_secs))
            .timeout(Duration::from_secs(self.request_timeout_secs))
            .http2_keep_alive_interval(Duration::from_secs(self.keepalive_interval_secs))
            .keep_alive_timeout(Duration::from_secs(self.keepalive_timeout_secs))
            .keep_alive_while_idle(true)
            .tcp_nodelay(true)
            .concurrency_limit(self.max_concurrent_streams as usize);

        // No special cases - pattern match on TLS config
        match &self.tls {
            TlsConfig::Disabled => Ok(ep),
            TlsConfig::Enabled {
                domain_name: _,
                ca_cert_path,
                client_identity,
            } => {
                // Extract domain from URL for TLS verification instead of using hardcoded domain
                // This allows connecting to multiple services with the same wildcard certificate
                let tls_domain = Self::extract_host_from_url(url).unwrap_or_else(|| {
                    tracing::warn!(
                        "Could not extract host from URL {}, using URL as domain",
                        url
                    );
                    url.to_string()
                });

                let ca_pem = fs::read(ca_cert_path)?;
                let mut tls = ClientTlsConfig::new()
                    .ca_certificate(Certificate::from_pem(ca_pem))
                    .domain_name(&tls_domain);

                // Add mTLS identity if provided
                if let Some(identity) = client_identity {
                    let cert_pem = fs::read(&identity.cert_path)?;
                    let key_pem = fs::read(&identity.key_path)?;
                    tls = tls.identity(Identity::from_pem(cert_pem, key_pem));
                }

                Ok(ep.tls_config(tls)?)
            }
        }
    }

    /// Extract the host (domain) from a URL string
    fn extract_host_from_url(url: &str) -> Option<String> {
        // Remove scheme prefix
        let without_scheme = url
            .strip_prefix("https://")
            .or_else(|| url.strip_prefix("http://"))
            .unwrap_or(url);

        // Extract host (everything before the port or path)
        let host = without_scheme
            .split(':')
            .next()
            .or_else(|| without_scheme.split('/').next())?;

        if host.is_empty() {
            None
        } else {
            Some(host.to_string())
        }
    }

    /// Connect to a Channel using this configuration
    pub async fn connect_channel(&self, url: &str) -> Result<Channel, Box<dyn std::error::Error>> {
        Ok(self.make_endpoint(url)?.connect().await?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;
    use std::env;

    // Tests marked with #[serial] run sequentially to avoid environment variable conflicts

    #[test]
    #[serial]
    fn test_environment_detection_default() {
        // Save current env
        let original = env::var("APP_ENV").ok();

        env::remove_var("APP_ENV");
        assert_eq!(Environment::Development, Environment::from_env());

        // Restore
        if let Some(val) = original {
            env::set_var("APP_ENV", val);
        }
    }

    #[test]
    #[serial]
    fn test_environment_detection_production() {
        let original = env::var("APP_ENV").ok();

        env::set_var("APP_ENV", "production");
        assert_eq!(Environment::ProductionLike, Environment::from_env());

        if let Some(val) = original {
            env::set_var("APP_ENV", val);
        } else {
            env::remove_var("APP_ENV");
        }
    }

    #[test]
    #[serial]
    fn test_environment_detection_staging() {
        let original = env::var("APP_ENV").ok();

        env::set_var("APP_ENV", "staging");
        assert_eq!(Environment::ProductionLike, Environment::from_env());

        if let Some(val) = original {
            env::set_var("APP_ENV", val);
        } else {
            env::remove_var("APP_ENV");
        }
    }

    #[test]
    #[serial]
    fn test_production_requires_tls() {
        let original_env = env::var("APP_ENV").ok();
        let original_tls = env::var("GRPC_TLS_ENABLED").ok();

        env::set_var("GRPC_TLS_ENABLED", "false");

        let result = GrpcConfig::load_tls_config(Environment::ProductionLike);
        assert!(result.is_err());
        let err_msg = result.unwrap_err().to_string();
        assert!(
            err_msg.contains("MANDATORY") || err_msg.contains("mandatory"),
            "Error message should mention TLS is mandatory, got: {}",
            err_msg
        );

        // Restore
        if let Some(val) = original_env {
            env::set_var("APP_ENV", val);
        } else {
            env::remove_var("APP_ENV");
        }
        if let Some(val) = original_tls {
            env::set_var("GRPC_TLS_ENABLED", val);
        } else {
            env::remove_var("GRPC_TLS_ENABLED");
        }
    }

    #[test]
    #[serial]
    fn test_development_allows_disabled_tls() {
        let original = env::var("GRPC_TLS_ENABLED").ok();

        env::remove_var("GRPC_TLS_ENABLED");

        let result = GrpcConfig::load_tls_config(Environment::Development);
        assert!(result.is_ok());
        assert!(matches!(result.unwrap(), TlsConfig::Disabled));

        if let Some(val) = original {
            env::set_var("GRPC_TLS_ENABLED", val);
        }
    }

    #[test]
    #[serial]
    fn test_tls_requires_domain_and_ca() {
        let original_enabled = env::var("GRPC_TLS_ENABLED").ok();
        let original_domain = env::var("GRPC_TLS_DOMAIN_NAME").ok();
        let original_ca = env::var("GRPC_TLS_CA_CERT_PATH").ok();

        env::set_var("GRPC_TLS_ENABLED", "true");
        env::remove_var("GRPC_TLS_DOMAIN_NAME");
        env::remove_var("GRPC_TLS_CA_CERT_PATH");

        let result = GrpcConfig::load_tls_config(Environment::Development);
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("GRPC_TLS_DOMAIN_NAME"));

        // Restore
        if let Some(val) = original_enabled {
            env::set_var("GRPC_TLS_ENABLED", val);
        } else {
            env::remove_var("GRPC_TLS_ENABLED");
        }
        if let Some(val) = original_domain {
            env::set_var("GRPC_TLS_DOMAIN_NAME", val);
        }
        if let Some(val) = original_ca {
            env::set_var("GRPC_TLS_CA_CERT_PATH", val);
        }
    }

    #[test]
    #[serial]
    fn test_mtls_requires_both_cert_and_key() {
        let original_enabled = env::var("GRPC_TLS_ENABLED").ok();
        let original_domain = env::var("GRPC_TLS_DOMAIN_NAME").ok();
        let original_ca = env::var("GRPC_TLS_CA_CERT_PATH").ok();
        let original_cert = env::var("GRPC_TLS_CLIENT_CERT_PATH").ok();
        let original_key = env::var("GRPC_TLS_CLIENT_KEY_PATH").ok();

        // Create temp files for CA cert
        let temp_dir = std::env::temp_dir();
        let ca_path = temp_dir.join("test_ca.pem");
        std::fs::write(
            &ca_path,
            "-----BEGIN CERTIFICATE-----\nfake\n-----END CERTIFICATE-----",
        )
        .unwrap();

        env::set_var("GRPC_TLS_ENABLED", "true");
        env::set_var("GRPC_TLS_DOMAIN_NAME", "example.com");
        env::set_var("GRPC_TLS_CA_CERT_PATH", ca_path.to_str().unwrap());
        env::set_var("GRPC_TLS_CLIENT_CERT_PATH", "/tmp/cert.pem");
        env::remove_var("GRPC_TLS_CLIENT_KEY_PATH");

        let result = GrpcConfig::load_tls_config(Environment::Development);
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("Both GRPC_TLS_CLIENT_CERT_PATH and GRPC_TLS_CLIENT_KEY_PATH"));

        std::fs::remove_file(ca_path).ok();

        // Restore
        if let Some(val) = original_enabled {
            env::set_var("GRPC_TLS_ENABLED", val);
        } else {
            env::remove_var("GRPC_TLS_ENABLED");
        }
        if let Some(val) = original_domain {
            env::set_var("GRPC_TLS_DOMAIN_NAME", val);
        } else {
            env::remove_var("GRPC_TLS_DOMAIN_NAME");
        }
        if let Some(val) = original_ca {
            env::set_var("GRPC_TLS_CA_CERT_PATH", val);
        } else {
            env::remove_var("GRPC_TLS_CA_CERT_PATH");
        }
        if let Some(val) = original_cert {
            env::set_var("GRPC_TLS_CLIENT_CERT_PATH", val);
        } else {
            env::remove_var("GRPC_TLS_CLIENT_CERT_PATH");
        }
        if let Some(val) = original_key {
            env::set_var("GRPC_TLS_CLIENT_KEY_PATH", val);
        } else {
            env::remove_var("GRPC_TLS_CLIENT_KEY_PATH");
        }
    }
}
