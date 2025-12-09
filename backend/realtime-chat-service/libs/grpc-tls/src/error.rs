//! Error types for gRPC TLS/mTLS operations
//!
//! Provides structured error handling for certificate loading, validation,
//! and TLS configuration failures.

use std::path::PathBuf;
use thiserror::Error;

/// Errors that can occur during TLS/mTLS configuration
#[derive(Error, Debug)]
pub enum TlsError {
    /// Failed to read certificate file from disk
    #[error("Failed to read certificate file '{path}': {source}")]
    CertificateReadError {
        path: PathBuf,
        source: std::io::Error,
    },

    /// Failed to parse PEM-encoded certificate
    #[error("Failed to parse PEM certificate from '{path}': {reason}")]
    CertificateParseError { path: PathBuf, reason: String },

    /// Certificate has expired
    #[error("Certificate has expired (expired on {expiry_date})")]
    CertificateExpiredError { expiry_date: String },

    /// Certificate will expire soon
    #[error("Certificate expires in {days_remaining} days (warning threshold: {warn_threshold})")]
    CertificateExpiringWarning {
        days_remaining: i64,
        warn_threshold: u64,
    },

    /// Missing required environment variable
    #[error("Required environment variable '{var_name}' not set: {hint}")]
    MissingEnvVar { var_name: String, hint: String },

    /// Invalid TLS configuration
    #[error("Invalid TLS configuration: {reason}")]
    InvalidConfig { reason: String },

    /// mTLS required but client certificate missing
    #[error("mTLS is required but client certificate not provided")]
    MtlsClientCertMissing,

    /// mTLS required but client key missing
    #[error("mTLS is required but client private key not provided")]
    MtlsClientKeyMissing,

    /// SAN (Subject Alternative Name) validation failed
    #[error("SAN validation failed: expected '{expected}', found '{actual}'")]
    SanValidationError { expected: String, actual: String },

    /// Certificate rotation failed
    #[error("Certificate rotation failed: {reason}")]
    RotationError { reason: String },

    /// Generic TLS error
    #[error("TLS error: {0}")]
    TlsGeneric(String),
}

/// Result type alias for TLS operations
pub type TlsResult<T> = Result<T, TlsError>;

impl TlsError {
    /// Check if this error is a blocker (must fix before production)
    pub fn is_blocker(&self) -> bool {
        matches!(
            self,
            TlsError::CertificateExpiredError { .. }
                | TlsError::MtlsClientCertMissing
                | TlsError::MtlsClientKeyMissing
                | TlsError::SanValidationError { .. }
        )
    }

    /// Check if this is a warning (should fix but not critical)
    pub fn is_warning(&self) -> bool {
        matches!(self, TlsError::CertificateExpiringWarning { .. })
    }
}

// Implement From for common error types
impl From<rcgen::Error> for TlsError {
    fn from(err: rcgen::Error) -> Self {
        TlsError::TlsGeneric(format!("Certificate generation error: {}", err))
    }
}

impl From<pem::PemError> for TlsError {
    fn from(err: pem::PemError) -> Self {
        TlsError::CertificateParseError {
            path: "memory".into(),
            reason: format!("PEM parse error: {}", err),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_blocker_errors() {
        let err = TlsError::CertificateExpiredError {
            expiry_date: "2024-01-01".to_string(),
        };
        assert!(err.is_blocker());
        assert!(!err.is_warning());

        let err = TlsError::MtlsClientCertMissing;
        assert!(err.is_blocker());
    }

    #[test]
    fn test_warning_errors() {
        let err = TlsError::CertificateExpiringWarning {
            days_remaining: 10,
            warn_threshold: 30,
        };
        assert!(err.is_warning());
        assert!(!err.is_blocker());
    }

    #[test]
    fn test_error_display() {
        let err = TlsError::MissingEnvVar {
            var_name: "GRPC_SERVER_CERT_PATH".to_string(),
            hint: "Set to path of server certificate PEM file".to_string(),
        };
        assert!(err.to_string().contains("GRPC_SERVER_CERT_PATH"));
        assert!(err.to_string().contains("not set"));
    }
}
