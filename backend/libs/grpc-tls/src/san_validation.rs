//! Subject Alternative Name (SAN) validation for mTLS
//!
//! Validates that certificates contain expected SAN entries to prevent
//! man-in-the-middle attacks and ensure service identity.

use crate::error::{TlsError, TlsResult};
use std::net::IpAddr;
use x509_parser::prelude::*;

/// SAN (Subject Alternative Name) types we validate
#[derive(Debug, Clone, PartialEq)]
pub enum SanEntry {
    /// DNS name (e.g., "auth-service.nova.internal")
    DnsName(String),
    /// IP address
    IpAddress(IpAddr),
}

impl SanEntry {
    /// Check if this SAN entry matches a pattern
    ///
    /// Supports wildcards in DNS names (e.g., "*.nova.internal")
    pub fn matches(&self, pattern: &str) -> bool {
        match self {
            SanEntry::DnsName(name) => {
                if pattern.contains('*') {
                    // Wildcard matching: "*.nova.internal" matches "auth.nova.internal"
                    let pattern_parts: Vec<&str> = pattern.split('.').collect();
                    let name_parts: Vec<&str> = name.split('.').collect();

                    if pattern_parts.len() != name_parts.len() {
                        return false;
                    }

                    pattern_parts
                        .iter()
                        .zip(name_parts.iter())
                        .all(|(p, n)| *p == "*" || p == n)
                } else {
                    // Exact match
                    name == pattern
                }
            }
            SanEntry::IpAddress(ip) => {
                // Try parsing pattern as IP and compare
                pattern.parse::<IpAddr>().ok() == Some(*ip)
            }
        }
    }
}

/// Extract SAN entries from a PEM certificate
pub fn extract_san_entries(cert_pem: &str) -> TlsResult<Vec<SanEntry>> {
    let pem = ::pem::parse(cert_pem.as_bytes())?;

    let (_, cert) =
        X509Certificate::from_der(pem.contents()).map_err(|e| {
            TlsError::CertificateParseError {
                path: "memory".into(),
                reason: format!("X.509 parse failed: {}", e),
            }
        })?;

    let mut san_entries = Vec::new();

    // Find SubjectAlternativeName extension
    if let Ok(Some(san_ext)) = cert.subject_alternative_name() {
        for name in &san_ext.value.general_names {
            match name {
                GeneralName::DNSName(dns) => {
                    san_entries.push(SanEntry::DnsName(dns.to_string()));
                }
                GeneralName::IPAddress(ip_bytes) => {
                    if let Some(ip) = parse_ip_address(ip_bytes) {
                        san_entries.push(SanEntry::IpAddress(ip));
                    }
                }
                _ => {
                    // Ignore other types (Email, URI, etc.)
                }
            }
        }
    }

    Ok(san_entries)
}

/// Validate that a certificate contains at least one expected SAN
///
/// Returns Ok if ANY expected SAN matches.
/// Returns Err if NO expected SANs found.
pub fn validate_san(cert_pem: &str, expected_sans: &[String]) -> TlsResult<()> {
    let actual_sans = extract_san_entries(cert_pem)?;

    // Check if any expected SAN matches
    for expected in expected_sans {
        for actual in &actual_sans {
            if actual.matches(expected) {
                tracing::debug!(
                    expected = %expected,
                    actual = ?actual,
                    "SAN validation passed"
                );
                return Ok(());
            }
        }
    }

    // No match found
    let actual_str = actual_sans
        .iter()
        .map(|s| format!("{:?}", s))
        .collect::<Vec<_>>()
        .join(", ");

    Err(TlsError::SanValidationError {
        expected: expected_sans.join(", "),
        actual: actual_str,
    })
}

/// Helper: Parse IP address bytes from certificate
fn parse_ip_address(bytes: &[u8]) -> Option<IpAddr> {
    if bytes.len() == 4 {
        // IPv4
        Some(IpAddr::V4(std::net::Ipv4Addr::new(
            bytes[0], bytes[1], bytes[2], bytes[3],
        )))
    } else if bytes.len() == 16 {
        // IPv6
        let mut segments = [0u16; 8];
        for i in 0..8 {
            segments[i] = u16::from_be_bytes([bytes[i * 2], bytes[i * 2 + 1]]);
        }
        Some(IpAddr::V6(std::net::Ipv6Addr::new(
            segments[0],
            segments[1],
            segments[2],
            segments[3],
            segments[4],
            segments[5],
            segments[6],
            segments[7],
        )))
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cert_generation::generate_dev_certificates;

    #[test]
    fn test_extract_san_entries() {
        let bundle = generate_dev_certificates().unwrap();
        let sans = extract_san_entries(&bundle.server_cert).unwrap();

        assert!(!sans.is_empty());

        // Should contain localhost
        assert!(sans
            .iter()
            .any(|san| matches!(san, SanEntry::DnsName(name) if name == "localhost")));
    }

    #[test]
    fn test_san_exact_match() {
        let san = SanEntry::DnsName("localhost".to_string());
        assert!(san.matches("localhost"));
        assert!(!san.matches("example.com"));
    }

    #[test]
    fn test_san_wildcard_match() {
        let san = SanEntry::DnsName("auth.nova.internal".to_string());
        assert!(san.matches("*.nova.internal"));
        assert!(san.matches("auth.nova.internal"));
        assert!(!san.matches("*.example.com"));
    }

    #[test]
    fn test_san_ip_match() {
        let san = SanEntry::IpAddress("127.0.0.1".parse().unwrap());
        assert!(san.matches("127.0.0.1"));
        assert!(!san.matches("192.168.1.1"));
    }

    #[test]
    fn test_validate_san_success() {
        let bundle = generate_dev_certificates().unwrap();
        let expected = vec!["localhost".to_string()];

        let result = validate_san(&bundle.server_cert, &expected);
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_san_wildcard() {
        let bundle = generate_dev_certificates().unwrap();
        let expected = vec!["*.nova-backend.svc.cluster.local".to_string()];

        let result = validate_san(&bundle.server_cert, &expected);
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_san_failure() {
        let bundle = generate_dev_certificates().unwrap();
        let expected = vec!["nonexistent.com".to_string()];

        let result = validate_san(&bundle.server_cert, &expected);
        assert!(result.is_err());

        match result.unwrap_err() {
            TlsError::SanValidationError { .. } => {}
            _ => panic!("Expected SanValidationError"),
        }
    }

    #[test]
    fn test_wildcard_pattern_parts_mismatch() {
        let san = SanEntry::DnsName("a.b.c".to_string());
        assert!(!san.matches("*.b")); // Different number of parts
    }
}
