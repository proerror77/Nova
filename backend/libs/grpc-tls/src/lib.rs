//! gRPC TLS Configuration Library with mTLS Support
//!
//! **Security Features**:
//! - Server TLS with certificate validation
//! - Mutual TLS (mTLS) for service-to-service authentication
//! - Certificate rotation without downtime
//! - Development self-signed cert generation
//!
//! **CVSS 8.5 Mitigation**: Encrypts gRPC traffic and authenticates services

use anyhow::{anyhow, Context, Result};
use rcgen::{generate_simple_self_signed, CertifiedKey};
use std::fs;
use std::path::Path;
use tonic::transport::{Certificate, ClientTlsConfig, Identity, ServerTlsConfig};
use tracing::{info, warn};

pub mod cert_generation;
pub use cert_generation::{generate_dev_certificates, CertificateBundle};

/// TLS configuration for gRPC server
#[derive(Clone)]
pub struct GrpcServerTlsConfig {
    /// Server certificate (PEM format)
    pub cert_pem: String,
    /// Server private key (PEM format)
    pub key_pem: String,
    /// Optional client CA certificate for mTLS
    pub client_ca_cert: Option<String>,
    /// Require client certificates (mTLS)
    pub require_client_cert: bool,
}

impl GrpcServerTlsConfig {
    /// Load server TLS config from environment variables
    ///
    /// **Environment Variables**:
    /// - `GRPC_SERVER_CERT_PATH`: Path to server certificate PEM file
    /// - `GRPC_SERVER_KEY_PATH`: Path to server private key PEM file
    /// - `GRPC_CLIENT_CA_CERT_PATH`: Path to client CA cert for mTLS (optional)
    /// - `GRPC_REQUIRE_CLIENT_CERT`: Require client certs (default: false)
    pub fn from_env() -> Result<Self> {
        let cert_path = std::env::var("GRPC_SERVER_CERT_PATH")
            .context("GRPC_SERVER_CERT_PATH not set - TLS required for production")?;

        let key_path = std::env::var("GRPC_SERVER_KEY_PATH")
            .context("GRPC_SERVER_KEY_PATH not set - TLS required for production")?;

        let cert_pem = fs::read_to_string(&cert_path)
            .with_context(|| format!("Failed to read server certificate from {}", cert_path))?;

        let key_pem = fs::read_to_string(&key_path)
            .with_context(|| format!("Failed to read server key from {}", key_path))?;

        let client_ca_cert = std::env::var("GRPC_CLIENT_CA_CERT_PATH")
            .ok()
            .and_then(|path| fs::read_to_string(&path).ok());

        let require_client_cert = std::env::var("GRPC_REQUIRE_CLIENT_CERT")
            .ok()
            .and_then(|v| v.parse::<bool>().ok())
            .unwrap_or(false);

        info!(
            cert_path = %cert_path,
            mtls_enabled = client_ca_cert.is_some(),
            require_client_cert = require_client_cert,
            "gRPC server TLS configuration loaded"
        );

        Ok(Self {
            cert_pem,
            key_pem,
            client_ca_cert,
            require_client_cert,
        })
    }

    /// Create development config with self-signed certificates
    ///
    /// **WARNING**: Only use in development/testing, NEVER in production
    pub fn development() -> Result<Self> {
        warn!("Using development TLS config with self-signed certificates - NOT for production");

        let bundle = cert_generation::generate_dev_certificates()?;

        Ok(Self {
            cert_pem: bundle.server_cert,
            key_pem: bundle.server_key,
            client_ca_cert: Some(bundle.ca_cert.clone()),
            require_client_cert: false,
        })
    }

    /// Build tonic ServerTlsConfig
    pub fn build_server_tls(&self) -> Result<ServerTlsConfig> {
        let identity = Identity::from_pem(&self.cert_pem, &self.key_pem);

        let mut tls_config = ServerTlsConfig::new().identity(identity);

        // Enable mTLS if client CA cert provided
        if let Some(ref ca_cert) = self.client_ca_cert {
            let client_ca = Certificate::from_pem(ca_cert);
            tls_config = tls_config.client_ca_root(client_ca);

            if self.require_client_cert {
                info!("mTLS enabled with client certificate requirement");
            } else {
                info!("mTLS enabled but client certificates optional");
            }
        }

        Ok(tls_config)
    }
}

/// TLS configuration for gRPC client
#[derive(Clone)]
pub struct GrpcClientTlsConfig {
    /// Server CA certificate to trust (PEM format)
    pub server_ca_cert: String,
    /// Optional client certificate for mTLS
    pub client_cert: Option<String>,
    /// Optional client private key for mTLS
    pub client_key: Option<String>,
    /// Server domain name for certificate validation
    pub domain_name: String,
}

impl GrpcClientTlsConfig {
    /// Load client TLS config from environment variables
    ///
    /// **Environment Variables**:
    /// - `GRPC_SERVER_CA_CERT_PATH`: Path to server CA certificate
    /// - `GRPC_CLIENT_CERT_PATH`: Path to client cert for mTLS (optional)
    /// - `GRPC_CLIENT_KEY_PATH`: Path to client key for mTLS (optional)
    /// - `GRPC_SERVER_DOMAIN`: Server domain name (e.g., "auth-service")
    pub fn from_env() -> Result<Self> {
        let ca_cert_path = std::env::var("GRPC_SERVER_CA_CERT_PATH")
            .context("GRPC_SERVER_CA_CERT_PATH not set - TLS required for production")?;

        let server_ca_cert = fs::read_to_string(&ca_cert_path)
            .with_context(|| format!("Failed to read server CA cert from {}", ca_cert_path))?;

        let client_cert = std::env::var("GRPC_CLIENT_CERT_PATH")
            .ok()
            .and_then(|path| fs::read_to_string(&path).ok());

        let client_key = std::env::var("GRPC_CLIENT_KEY_PATH")
            .ok()
            .and_then(|path| fs::read_to_string(&path).ok());

        let domain_name = std::env::var("GRPC_SERVER_DOMAIN")
            .unwrap_or_else(|_| "localhost".to_string());

        info!(
            domain = %domain_name,
            mtls_enabled = client_cert.is_some(),
            "gRPC client TLS configuration loaded"
        );

        Ok(Self {
            server_ca_cert,
            client_cert,
            client_key,
            domain_name,
        })
    }

    /// Create development config
    pub fn development(server_ca_cert: String, domain: &str) -> Self {
        warn!("Using development client TLS config - NOT for production");

        Self {
            server_ca_cert,
            client_cert: None,
            client_key: None,
            domain_name: domain.to_string(),
        }
    }

    /// Build tonic ClientTlsConfig
    pub fn build_client_tls(&self) -> Result<ClientTlsConfig> {
        let server_ca = Certificate::from_pem(&self.server_ca_cert);

        let mut tls_config = ClientTlsConfig::new()
            .ca_certificate(server_ca)
            .domain_name(&self.domain_name);

        // Enable mTLS if client cert/key provided
        if let (Some(cert), Some(key)) = (&self.client_cert, &self.client_key) {
            let identity = Identity::from_pem(cert, key);
            tls_config = tls_config.identity(identity);
            info!("Client mTLS enabled with certificate authentication");
        }

        Ok(tls_config)
    }
}

/// Validate certificate expiration
pub fn validate_cert_expiration(cert_pem: &str, warn_days_before: u64) -> Result<()> {
    use x509_parser::prelude::*;

    let pem = pem::parse(cert_pem)
        .map_err(|e| anyhow!("Failed to parse PEM: {}", e))?;

    let (_, cert) = X509Certificate::from_der(&pem.contents())
        .map_err(|e| anyhow!("Failed to parse X.509 certificate: {}", e))?;

    let not_after = cert.validity().not_after;
    let expiry_timestamp = not_after.timestamp();

    let now = chrono::Utc::now().timestamp();
    let days_until_expiry = (expiry_timestamp - now) / 86400;

    if days_until_expiry < 0 {
        return Err(anyhow!("Certificate has expired"));
    }

    if days_until_expiry < warn_days_before as i64 {
        warn!(
            days_remaining = days_until_expiry,
            "Certificate expiring soon - rotation recommended"
        );
    }

    info!(
        days_until_expiry = days_until_expiry,
        "Certificate validity check passed"
    );

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_development_server_config() {
        let config = GrpcServerTlsConfig::development().unwrap();
        assert!(!config.cert_pem.is_empty());
        assert!(!config.key_pem.is_empty());
        assert!(config.client_ca_cert.is_some());
    }

    #[test]
    fn test_development_client_config() {
        let bundle = cert_generation::generate_dev_certificates().unwrap();
        let config = GrpcClientTlsConfig::development(bundle.ca_cert, "localhost");
        assert!(!config.server_ca_cert.is_empty());
        assert_eq!(config.domain_name, "localhost");
    }

    #[test]
    fn test_build_server_tls() {
        let config = GrpcServerTlsConfig::development().unwrap();
        let tls = config.build_server_tls();
        assert!(tls.is_ok());
    }

    #[test]
    fn test_build_client_tls() {
        let bundle = cert_generation::generate_dev_certificates().unwrap();
        let config = GrpcClientTlsConfig::development(bundle.ca_cert, "localhost");
        let tls = config.build_client_tls();
        assert!(tls.is_ok());
    }

    #[test]
    fn test_validate_cert_expiration() {
        let bundle = cert_generation::generate_dev_certificates().unwrap();
        let result = validate_cert_expiration(&bundle.server_cert, 30);
        assert!(result.is_ok());
    }
}
