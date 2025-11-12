//! Simple mTLS Server/Client Example
//!
//! Run with: cargo run --example simple_mtls

use grpc_tls::{
    cert_generation::generate_dev_certificates,
    mtls::{MtlsClientConfig, MtlsServerConfig, TlsConfigPaths},
};
use std::fs;
use tempfile::TempDir;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Setup logging
    tracing_subscriber::fmt::init();

    println!("=== Nova mTLS Example ===\n");

    // 1. Generate development certificates
    println!("[1/4] Generating development certificates...");
    let bundle = generate_dev_certificates()?;
    println!("✓ Generated CA, server, and client certificates\n");

    // 2. Write certificates to temporary directory
    println!("[2/4] Writing certificates to disk...");
    let temp_dir = TempDir::new()?;
    let cert_dir = temp_dir.path();

    fs::write(cert_dir.join("ca.crt"), &bundle.ca_cert)?;
    fs::write(cert_dir.join("server.crt"), &bundle.server_cert)?;
    fs::write(cert_dir.join("server.key"), &bundle.server_key)?;
    fs::write(cert_dir.join("client.crt"), &bundle.client_cert)?;
    fs::write(cert_dir.join("client.key"), &bundle.client_key)?;
    println!("✓ Certificates written to: {:?}\n", cert_dir);

    // 3. Load server mTLS configuration
    println!("[3/4] Loading mTLS server configuration...");
    let server_paths = TlsConfigPaths {
        ca_cert_path: cert_dir.join("ca.crt"),
        server_cert_path: cert_dir.join("server.crt"),
        server_key_path: cert_dir.join("server.key"),
        client_cert_path: None,
        client_key_path: None,
    };

    let server_config = MtlsServerConfig::from_paths(server_paths).await?;
    let _server_tls = server_config.build_server_tls()?;
    println!("✓ Server mTLS configured (requires client certificates)\n");

    // 4. Load client mTLS configuration
    println!("[4/4] Loading mTLS client configuration...");
    let client_paths = TlsConfigPaths {
        ca_cert_path: cert_dir.join("ca.crt"),
        server_cert_path: cert_dir.join("dummy.crt"),
        server_key_path: cert_dir.join("dummy.key"),
        client_cert_path: Some(cert_dir.join("client.crt")),
        client_key_path: Some(cert_dir.join("client.key")),
    };

    let client_config =
        MtlsClientConfig::from_paths(client_paths, "localhost".to_string()).await?;
    let _client_tls = client_config.build_client_tls()?;
    println!("✓ Client mTLS configured with certificate authentication\n");

    // 5. Validate SAN entries
    println!("[Validation] Checking SAN entries...");
    let san_entries = grpc_tls::extract_san_entries(&bundle.server_cert)?;
    println!("Server certificate SANs: {:?}", san_entries);

    let expected_sans = vec!["localhost".to_string()];
    grpc_tls::validate_san(&bundle.server_cert, &expected_sans)?;
    println!("✓ SAN validation passed\n");

    // 6. Check certificate expiration
    println!("[Validation] Checking certificate expiration...");
    grpc_tls::validate_cert_expiration(&bundle.server_cert, 30)?;
    println!("✓ Certificate valid (expires in > 30 days)\n");

    println!("=== mTLS Setup Complete ===");
    println!("\nNext steps:");
    println!("1. Use server_tls with tonic::transport::Server");
    println!("2. Use client_tls with tonic::transport::Channel");
    println!("3. All connections will use mutual TLS authentication");

    Ok(())
}
