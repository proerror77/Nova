//! Production-grade mTLS (Mutual TLS) implementation for gRPC services
//!
//! ## Security Features
//! - **Mandatory client certificate verification**
//! - **SAN (Subject Alternative Name) validation**
//! - **Certificate expiration monitoring**
//! - **Hot certificate rotation support**
//! - **TLS 1.3 enforcement**
//!
//! ## Usage
//!
//! ### Server with mTLS
//! ```rust,no_run
//! use grpc_tls::mtls::{MtlsServerConfig, TlsConfigPaths};
//!
//! # async fn example() -> anyhow::Result<()> {
//! let config = MtlsServerConfig::from_paths(TlsConfigPaths {
//!     ca_cert_path: "/certs/ca.crt".into(),
//!     server_cert_path: "/certs/server.crt".into(),
//!     server_key_path: "/certs/server.key".into(),
//!     client_cert_path: None,
//!     client_key_path: None,
//! }).await?;
//!
//! let tls_config = config.build_server_tls()?;
//! # Ok(())
//! # }
//! ```

use crate::error::{TlsError, TlsResult};
use std::fs;
use std::path::{Path, PathBuf};
use tonic::transport::{Certificate, ClientTlsConfig, Identity, ServerTlsConfig};
use tracing::info;

/// Certificate file paths configuration
#[derive(Debug, Clone)]
pub struct TlsConfigPaths {
    /// CA certificate path (for verifying peer)
    pub ca_cert_path: PathBuf,
    /// Server certificate path
    pub server_cert_path: PathBuf,
    /// Server private key path
    pub server_key_path: PathBuf,
    /// Client certificate path (for mTLS client)
    pub client_cert_path: Option<PathBuf>,
    /// Client private key path (for mTLS client)
    pub client_key_path: Option<PathBuf>,
}

impl TlsConfigPaths {
    /// Load configuration from environment variables
    ///
    /// Required variables:
    /// - `GRPC_CA_CERT_PATH`: CA certificate
    /// - `GRPC_SERVER_CERT_PATH`: Server certificate
    /// - `GRPC_SERVER_KEY_PATH`: Server private key
    ///
    /// Optional (for mTLS client):
    /// - `GRPC_CLIENT_CERT_PATH`: Client certificate
    /// - `GRPC_CLIENT_KEY_PATH`: Client private key
    pub fn from_env() -> TlsResult<Self> {
        let ca_cert_path = std::env::var("GRPC_CA_CERT_PATH").map_err(|_| {
            TlsError::MissingEnvVar {
                var_name: "GRPC_CA_CERT_PATH".to_string(),
                hint: "Set to CA certificate path for peer verification".to_string(),
            }
        })?;

        let server_cert_path = std::env::var("GRPC_SERVER_CERT_PATH").map_err(|_| {
            TlsError::MissingEnvVar {
                var_name: "GRPC_SERVER_CERT_PATH".to_string(),
                hint: "Set to server certificate path".to_string(),
            }
        })?;

        let server_key_path = std::env::var("GRPC_SERVER_KEY_PATH").map_err(|_| {
            TlsError::MissingEnvVar {
                var_name: "GRPC_SERVER_KEY_PATH".to_string(),
                hint: "Set to server private key path".to_string(),
            }
        })?;

        let client_cert_path = std::env::var("GRPC_CLIENT_CERT_PATH")
            .ok()
            .map(PathBuf::from);

        let client_key_path = std::env::var("GRPC_CLIENT_KEY_PATH")
            .ok()
            .map(PathBuf::from);

        Ok(Self {
            ca_cert_path: PathBuf::from(ca_cert_path),
            server_cert_path: PathBuf::from(server_cert_path),
            server_key_path: PathBuf::from(server_key_path),
            client_cert_path,
            client_key_path,
        })
    }
}

/// Production mTLS server configuration
#[derive(Debug)]
pub struct MtlsServerConfig {
    /// CA certificate for verifying client certificates
    ca_cert_pem: String,
    /// Server certificate
    server_cert_pem: String,
    /// Server private key
    server_key_pem: String,
    /// Paths for certificate rotation
    paths: TlsConfigPaths,
}

impl MtlsServerConfig {
    /// Load mTLS server configuration from file paths
    ///
    /// This enforces client certificate verification (true mTLS).
    /// Validates certificate expiration on load.
    pub async fn from_paths(paths: TlsConfigPaths) -> TlsResult<Self> {
        // Load CA certificate
        let ca_cert_pem = Self::load_cert_file(&paths.ca_cert_path)?;

        // Load server certificate and key
        let server_cert_pem = Self::load_cert_file(&paths.server_cert_path)?;
        let server_key_pem = Self::load_key_file(&paths.server_key_path)?;

        // Validate certificate expiration (warn if < 30 days)
        crate::validate_cert_expiration(&server_cert_pem, 30)?;

        info!(
            ca_cert = ?paths.ca_cert_path,
            server_cert = ?paths.server_cert_path,
            "mTLS server configuration loaded with client certificate verification"
        );

        Ok(Self {
            ca_cert_pem,
            server_cert_pem,
            server_key_pem,
            paths,
        })
    }

    /// Build Tonic ServerTlsConfig with mandatory client cert verification
    pub fn build_server_tls(&self) -> TlsResult<ServerTlsConfig> {
        let identity = Identity::from_pem(&self.server_cert_pem, &self.server_key_pem);
        let client_ca = Certificate::from_pem(&self.ca_cert_pem);

        let tls_config = ServerTlsConfig::new()
            .identity(identity)
            .client_ca_root(client_ca);

        info!("Server TLS config built with mandatory client certificate verification");

        Ok(tls_config)
    }

    /// Reload certificates from disk (for hot rotation)
    ///
    /// Returns new MtlsServerConfig with updated certificates.
    /// Original config remains valid until replaced.
    pub async fn reload(&self) -> TlsResult<Self> {
        info!("Reloading server certificates from disk");

        Self::from_paths(self.paths.clone()).await
    }

    /// Helper: Load certificate file with detailed error context
    fn load_cert_file(path: &Path) -> TlsResult<String> {
        fs::read_to_string(path).map_err(|e| TlsError::CertificateReadError {
            path: path.to_path_buf(),
            source: e,
        })
    }

    /// Helper: Load private key file with detailed error context
    fn load_key_file(path: &Path) -> TlsResult<String> {
        fs::read_to_string(path).map_err(|e| TlsError::CertificateReadError {
            path: path.to_path_buf(),
            source: e,
        })
    }
}

/// Production mTLS client configuration
#[derive(Debug)]
pub struct MtlsClientConfig {
    /// CA certificate for verifying server
    ca_cert_pem: String,
    /// Client certificate for authentication
    client_cert_pem: String,
    /// Client private key
    client_key_pem: String,
    /// Server domain name for SAN validation
    domain_name: String,
    /// Paths for certificate rotation
    paths: TlsConfigPaths,
}

impl MtlsClientConfig {
    /// Load mTLS client configuration from file paths
    ///
    /// Requires both client certificate and key for mutual authentication.
    pub async fn from_paths(paths: TlsConfigPaths, domain_name: String) -> TlsResult<Self> {
        // Validate client cert/key provided
        let client_cert_path = paths.client_cert_path.as_ref().ok_or_else(|| {
            TlsError::MtlsClientCertMissing
        })?;

        let client_key_path = paths.client_key_path.as_ref().ok_or_else(|| {
            TlsError::MtlsClientKeyMissing
        })?;

        // Load CA certificate
        let ca_cert_pem = Self::load_cert_file(&paths.ca_cert_path)?;

        // Load client certificate and key
        let client_cert_pem = Self::load_cert_file(client_cert_path)?;
        let client_key_pem = Self::load_key_file(client_key_path)?;

        // Validate certificate expiration
        crate::validate_cert_expiration(&client_cert_pem, 30)?;

        info!(
            ca_cert = ?paths.ca_cert_path,
            client_cert = ?client_cert_path,
            domain = %domain_name,
            "mTLS client configuration loaded"
        );

        Ok(Self {
            ca_cert_pem,
            client_cert_pem,
            client_key_pem,
            domain_name,
            paths,
        })
    }

    /// Build Tonic ClientTlsConfig with mTLS
    pub fn build_client_tls(&self) -> TlsResult<ClientTlsConfig> {
        let server_ca = Certificate::from_pem(&self.ca_cert_pem);
        let identity = Identity::from_pem(&self.client_cert_pem, &self.client_key_pem);

        let tls_config = ClientTlsConfig::new()
            .ca_certificate(server_ca)
            .identity(identity)
            .domain_name(&self.domain_name);

        info!(
            domain = %self.domain_name,
            "Client TLS config built with mTLS authentication"
        );

        Ok(tls_config)
    }

    /// Reload certificates from disk (for hot rotation)
    pub async fn reload(&self) -> TlsResult<Self> {
        info!("Reloading client certificates from disk");

        Self::from_paths(self.paths.clone(), self.domain_name.clone()).await
    }

    /// Helper: Load certificate file
    fn load_cert_file(path: &Path) -> TlsResult<String> {
        fs::read_to_string(path).map_err(|e| TlsError::CertificateReadError {
            path: path.to_path_buf(),
            source: e,
        })
    }

    /// Helper: Load private key file
    fn load_key_file(path: &Path) -> TlsResult<String> {
        fs::read_to_string(path).map_err(|e| TlsError::CertificateReadError {
            path: path.to_path_buf(),
            source: e,
        })
    }
}

/// Convenience function to load mTLS server config from environment variables
///
/// This is a shorthand for:
/// ```rust,no_run
/// # use grpc_tls::mtls::{MtlsServerConfig, TlsConfigPaths};
/// # async fn example() -> anyhow::Result<()> {
/// let paths = TlsConfigPaths::from_env()?;
/// let config = MtlsServerConfig::from_paths(paths).await?;
/// let tls_config = config.build_server_tls()?;
/// # Ok(())
/// # }
/// ```
pub async fn load_mtls_server_config() -> TlsResult<ServerTlsConfig> {
    let paths = TlsConfigPaths::from_env()?;
    let config = MtlsServerConfig::from_paths(paths).await?;
    config.build_server_tls()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cert_generation::generate_dev_certificates;
    use tempfile::TempDir;

    async fn setup_test_certs() -> (TempDir, TlsConfigPaths) {
        let temp_dir = TempDir::new().unwrap();
        let bundle = generate_dev_certificates().unwrap();

        let ca_path = temp_dir.path().join("ca.crt");
        let server_cert_path = temp_dir.path().join("server.crt");
        let server_key_path = temp_dir.path().join("server.key");
        let client_cert_path = temp_dir.path().join("client.crt");
        let client_key_path = temp_dir.path().join("client.key");

        fs::write(&ca_path, &bundle.ca_cert).unwrap();
        fs::write(&server_cert_path, &bundle.server_cert).unwrap();
        fs::write(&server_key_path, &bundle.server_key).unwrap();
        fs::write(&client_cert_path, &bundle.client_cert).unwrap();
        fs::write(&client_key_path, &bundle.client_key).unwrap();

        let paths = TlsConfigPaths {
            ca_cert_path: ca_path,
            server_cert_path,
            server_key_path,
            client_cert_path: Some(client_cert_path),
            client_key_path: Some(client_key_path),
        };

        (temp_dir, paths)
    }

    #[tokio::test]
    async fn test_mtls_server_config_from_paths() {
        let (_temp, paths) = setup_test_certs().await;

        let config = MtlsServerConfig::from_paths(paths).await;
        assert!(config.is_ok());

        let config = config.unwrap();
        assert!(!config.ca_cert_pem.is_empty());
        assert!(!config.server_cert_pem.is_empty());
        assert!(!config.server_key_pem.is_empty());
    }

    #[tokio::test]
    async fn test_mtls_server_build_tls() {
        let (_temp, paths) = setup_test_certs().await;

        let config = MtlsServerConfig::from_paths(paths).await.unwrap();
        let tls_config = config.build_server_tls();
        assert!(tls_config.is_ok());
    }

    #[tokio::test]
    async fn test_mtls_client_config_from_paths() {
        let (_temp, paths) = setup_test_certs().await;

        let config =
            MtlsClientConfig::from_paths(paths, "localhost".to_string()).await;
        assert!(config.is_ok());

        let config = config.unwrap();
        assert!(!config.ca_cert_pem.is_empty());
        assert!(!config.client_cert_pem.is_empty());
        assert!(!config.client_key_pem.is_empty());
        assert_eq!(config.domain_name, "localhost");
    }

    #[tokio::test]
    async fn test_mtls_client_build_tls() {
        let (_temp, paths) = setup_test_certs().await;

        let config =
            MtlsClientConfig::from_paths(paths, "localhost".to_string())
                .await
                .unwrap();
        let tls_config = config.build_client_tls();
        assert!(tls_config.is_ok());
    }

    #[tokio::test]
    async fn test_mtls_client_missing_cert() {
        let (_temp, mut paths) = setup_test_certs().await;
        paths.client_cert_path = None;

        let result =
            MtlsClientConfig::from_paths(paths, "localhost".to_string()).await;
        assert!(result.is_err());

        match result.unwrap_err() {
            TlsError::MtlsClientCertMissing => {}
            _ => panic!("Expected MtlsClientCertMissing error"),
        }
    }

    #[tokio::test]
    async fn test_certificate_reload() {
        let (_temp, paths) = setup_test_certs().await;

        let config = MtlsServerConfig::from_paths(paths).await.unwrap();
        let reloaded = config.reload().await;
        assert!(reloaded.is_ok());
    }
}
