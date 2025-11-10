//! Certificate Generation for Development and Testing
//!
//! Generates self-signed certificates for gRPC TLS in development environments.
//! **WARNING**: NEVER use in production - use proper CA-signed certificates.

use anyhow::{Context, Result};
use rcgen::{
    BasicConstraints, Certificate, CertificateParams, DistinguishedName, DnType, IsCa, KeyPair,
    SanType,
};
use std::fs;
use std::path::Path;
use time::{Duration, OffsetDateTime};
use tracing::info;

/// Bundle of certificates for development
#[derive(Clone)]
pub struct CertificateBundle {
    /// CA certificate (PEM)
    pub ca_cert: String,
    /// CA private key (PEM)
    pub ca_key: String,
    /// Server certificate signed by CA (PEM)
    pub server_cert: String,
    /// Server private key (PEM)
    pub server_key: String,
    /// Client certificate for mTLS (PEM)
    pub client_cert: String,
    /// Client private key (PEM)
    pub client_key: String,
}

/// Generate development certificates (CA, server, client)
///
/// **Usage**: Development and testing only
/// **Validity**: 365 days
/// **Subject**: CN=Nova Development CA / CN=localhost / CN=client
pub fn generate_dev_certificates() -> Result<CertificateBundle> {
    // 1. Generate CA certificate
    let mut ca_params = CertificateParams::default();
    ca_params.distinguished_name = DistinguishedName::new();
    ca_params
        .distinguished_name
        .push(DnType::CommonName, "Nova Development CA");
    ca_params
        .distinguished_name
        .push(DnType::OrganizationName, "Nova Development");
    ca_params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    ca_params.not_before = OffsetDateTime::now_utc();
    ca_params.not_after = OffsetDateTime::now_utc() + Duration::days(365);

    let ca_key_pair = KeyPair::generate()?;
    ca_params.key_pair = Some(ca_key_pair);

    let ca_cert = Certificate::from_params(ca_params)
        .context("Failed to generate CA certificate")?;

    let ca_cert_pem = ca_cert.serialize_pem()?;
    let ca_key_pem = ca_cert.serialize_private_key_pem();

    // 2. Generate server certificate signed by CA
    let mut server_params = CertificateParams::default();
    server_params.distinguished_name = DistinguishedName::new();
    server_params
        .distinguished_name
        .push(DnType::CommonName, "localhost");
    server_params
        .distinguished_name
        .push(DnType::OrganizationName, "Nova Development");

    // Add Subject Alternative Names (SANs)
    server_params
        .subject_alt_names
        .push(SanType::DnsName("localhost".to_string()));
    server_params
        .subject_alt_names
        .push(SanType::DnsName("*.nova-backend.svc.cluster.local".to_string()));
    server_params
        .subject_alt_names
        .push(SanType::IpAddress(std::net::IpAddr::V4(
            std::net::Ipv4Addr::new(127, 0, 0, 1),
        )));

    server_params.not_before = OffsetDateTime::now_utc();
    server_params.not_after = OffsetDateTime::now_utc() + Duration::days(365);

    let server_key_pair = KeyPair::generate()?;
    server_params.key_pair = Some(server_key_pair);

    let server_cert = Certificate::from_params(server_params)
        .context("Failed to generate server certificate")?;

    let server_cert_pem = server_cert.serialize_pem_with_signer(&ca_cert)?;
    let server_key_pem = server_cert.serialize_private_key_pem();

    // 3. Generate client certificate for mTLS
    let mut client_params = CertificateParams::default();
    client_params.distinguished_name = DistinguishedName::new();
    client_params
        .distinguished_name
        .push(DnType::CommonName, "client");
    client_params
        .distinguished_name
        .push(DnType::OrganizationName, "Nova Development");

    client_params.not_before = OffsetDateTime::now_utc();
    client_params.not_after = OffsetDateTime::now_utc() + Duration::days(365);

    let client_key_pair = KeyPair::generate()?;
    client_params.key_pair = Some(client_key_pair);

    let client_cert = Certificate::from_params(client_params)
        .context("Failed to generate client certificate")?;

    let client_cert_pem = client_cert.serialize_pem_with_signer(&ca_cert)?;
    let client_key_pem = client_cert.serialize_private_key_pem();

    info!("Generated development certificates (CA, server, client)");

    Ok(CertificateBundle {
        ca_cert: ca_cert_pem,
        ca_key: ca_key_pem,
        server_cert: server_cert_pem,
        server_key: server_key_pem,
        client_cert: client_cert_pem,
        client_key: client_key_pem,
    })
}

/// Write certificate bundle to files
///
/// Creates directory structure:
/// ```
/// certs/
///   ca.crt        (CA certificate)
///   ca.key        (CA private key)
///   server.crt    (Server certificate)
///   server.key    (Server private key)
///   client.crt    (Client certificate)
///   client.key    (Client private key)
/// ```
pub fn write_cert_bundle(bundle: &CertificateBundle, output_dir: &Path) -> Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("Failed to create directory: {:?}", output_dir))?;

    fs::write(output_dir.join("ca.crt"), &bundle.ca_cert)
        .context("Failed to write CA certificate")?;
    fs::write(output_dir.join("ca.key"), &bundle.ca_key).context("Failed to write CA key")?;

    fs::write(output_dir.join("server.crt"), &bundle.server_cert)
        .context("Failed to write server certificate")?;
    fs::write(output_dir.join("server.key"), &bundle.server_key)
        .context("Failed to write server key")?;

    fs::write(output_dir.join("client.crt"), &bundle.client_cert)
        .context("Failed to write client certificate")?;
    fs::write(output_dir.join("client.key"), &bundle.client_key)
        .context("Failed to write client key")?;

    info!(output_dir = ?output_dir, "Certificate bundle written to disk");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn test_generate_dev_certificates() {
        let bundle = generate_dev_certificates().unwrap();

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

    #[test]
    fn test_write_cert_bundle() {
        let bundle = generate_dev_certificates().unwrap();
        let temp_dir = env::temp_dir().join("nova-certs-test");

        let result = write_cert_bundle(&bundle, &temp_dir);
        assert!(result.is_ok());

        // Verify files exist
        assert!(temp_dir.join("ca.crt").exists());
        assert!(temp_dir.join("server.crt").exists());
        assert!(temp_dir.join("client.crt").exists());

        // Cleanup
        let _ = fs::remove_dir_all(temp_dir);
    }
}
