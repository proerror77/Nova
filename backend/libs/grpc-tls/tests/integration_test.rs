//! Integration tests for mTLS configuration and certificate validation
//!
//! Tests core mTLS functionality without requiring a full gRPC server.

use grpc_tls::{
    cert_generation::{generate_dev_certificates, write_cert_bundle},
    mtls::{MtlsClientConfig, MtlsServerConfig, TlsConfigPaths},
    validate_san,
};
use std::fs;
use tempfile::TempDir;

/// Setup test environment with certificates
async fn setup_test_env() -> (TempDir, TlsConfigPaths) {
    let temp_dir = TempDir::new().unwrap();
    let bundle = generate_dev_certificates().unwrap();

    write_cert_bundle(&bundle, temp_dir.path()).unwrap();

    let paths = TlsConfigPaths {
        ca_cert_path: temp_dir.path().join("ca.crt"),
        server_cert_path: temp_dir.path().join("server.crt"),
        server_key_path: temp_dir.path().join("server.key"),
        client_cert_path: Some(temp_dir.path().join("client.crt")),
        client_key_path: Some(temp_dir.path().join("client.key")),
    };

    (temp_dir, paths)
}

#[tokio::test]
async fn test_mtls_server_config_from_paths() {
    let (_temp, paths) = setup_test_env().await;

    let config = MtlsServerConfig::from_paths(paths).await;
    assert!(config.is_ok(), "Failed to load server config");

    let config = config.unwrap();
    let tls_config = config.build_server_tls();
    assert!(tls_config.is_ok(), "Failed to build server TLS");
}

#[tokio::test]
async fn test_mtls_client_config_from_paths() {
    let (_temp, paths) = setup_test_env().await;

    let config = MtlsClientConfig::from_paths(paths, "localhost".to_string()).await;
    assert!(config.is_ok(), "Failed to load client config");

    let config = config.unwrap();
    let tls_config = config.build_client_tls();
    assert!(tls_config.is_ok(), "Failed to build client TLS");
}

#[tokio::test]
async fn test_client_without_certificate_fails() {
    let (_temp, mut paths) = setup_test_env().await;

    // Remove client certificate
    paths.client_cert_path = None;
    paths.client_key_path = None;

    let result = MtlsClientConfig::from_paths(paths, "localhost".to_string()).await;

    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        grpc_tls::TlsError::MtlsClientCertMissing
    ));
}

#[tokio::test]
async fn test_certificate_expiration_validation() {
    let (_temp, paths) = setup_test_env().await;

    // Load and validate certificate expiration
    let server_cert = fs::read_to_string(&paths.server_cert_path)
        .expect("Failed to read server cert");

    let result = grpc_tls::validate_cert_expiration(&server_cert, 30);
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_san_validation_success() {
    let (_temp, paths) = setup_test_env().await;

    let server_cert = fs::read_to_string(&paths.server_cert_path)
        .expect("Failed to read server cert");

    let expected_sans = vec!["localhost".to_string()];
    let result = validate_san(&server_cert, &expected_sans);

    assert!(result.is_ok());
}

#[tokio::test]
async fn test_san_validation_wildcard() {
    let (_temp, paths) = setup_test_env().await;

    let server_cert = fs::read_to_string(&paths.server_cert_path)
        .expect("Failed to read server cert");

    let expected_sans = vec!["*.nova-backend.svc.cluster.local".to_string()];
    let result = validate_san(&server_cert, &expected_sans);

    assert!(result.is_ok());
}

#[tokio::test]
async fn test_san_validation_failure() {
    let (_temp, paths) = setup_test_env().await;

    let server_cert = fs::read_to_string(&paths.server_cert_path)
        .expect("Failed to read server cert");

    let expected_sans = vec!["nonexistent.com".to_string()];
    let result = validate_san(&server_cert, &expected_sans);

    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        grpc_tls::TlsError::SanValidationError { .. }
    ));
}

#[tokio::test]
async fn test_certificate_reload() {
    let (_temp, paths) = setup_test_env().await;

    let config = MtlsServerConfig::from_paths(paths)
        .await
        .expect("Failed to load config");

    // Reload should succeed with same certificates
    let reloaded = config.reload().await;
    assert!(reloaded.is_ok());
}

#[tokio::test]
async fn test_invalid_certificate_path() {
    let paths = TlsConfigPaths {
        ca_cert_path: "/nonexistent/ca.crt".into(),
        server_cert_path: "/nonexistent/server.crt".into(),
        server_key_path: "/nonexistent/server.key".into(),
        client_cert_path: None,
        client_key_path: None,
    };

    let result = MtlsServerConfig::from_paths(paths).await;
    assert!(result.is_err());

    match result.unwrap_err() {
        grpc_tls::TlsError::CertificateReadError { path, .. } => {
            assert_eq!(path, std::path::PathBuf::from("/nonexistent/ca.crt"));
        }
        _ => panic!("Expected CertificateReadError"),
    }
}

#[tokio::test]
async fn test_certificate_bundle_generation() {
    let bundle = generate_dev_certificates().expect("Failed to generate bundle");

    // Verify all certificates present
    assert!(!bundle.ca_cert.is_empty());
    assert!(!bundle.ca_key.is_empty());
    assert!(!bundle.server_cert.is_empty());
    assert!(!bundle.server_key.is_empty());
    assert!(!bundle.client_cert.is_empty());
    assert!(!bundle.client_key.is_empty());

    // Verify PEM format
    assert!(bundle.ca_cert.contains("BEGIN CERTIFICATE"));
    assert!(bundle.server_cert.contains("BEGIN CERTIFICATE"));
    assert!(bundle.client_cert.contains("BEGIN CERTIFICATE"));
}

#[tokio::test]
async fn test_config_from_env_missing_vars() {
    // Clear environment variables
    std::env::remove_var("GRPC_CA_CERT_PATH");
    std::env::remove_var("GRPC_SERVER_CERT_PATH");
    std::env::remove_var("GRPC_SERVER_KEY_PATH");

    let result = TlsConfigPaths::from_env();
    assert!(result.is_err());

    match result.unwrap_err() {
        grpc_tls::TlsError::MissingEnvVar { var_name, .. } => {
            assert_eq!(var_name, "GRPC_CA_CERT_PATH");
        }
        _ => panic!("Expected MissingEnvVar error"),
    }
}
