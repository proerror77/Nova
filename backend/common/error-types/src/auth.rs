//! Authentication and authorization error types
//!
//! Provides detailed error handling for auth flows
//! without exposing sensitive information.

use thiserror::Error;
use chrono::{DateTime, Utc};

/// Authentication/Authorization errors
#[derive(Debug, Error)]
pub enum AuthError {
    /// Missing authentication credentials
    #[error("Authentication required")]
    MissingCredentials,

    /// Invalid credentials provided
    #[error("Invalid credentials")]
    InvalidCredentials,

    /// Token expired
    #[error("Token expired")]
    TokenExpired {
        expired_at: DateTime<Utc>,
    },

    /// Token not yet valid
    #[error("Token not yet valid")]
    TokenNotYetValid {
        valid_from: DateTime<Utc>,
    },

    /// Invalid token format
    #[error("Invalid token format")]
    InvalidTokenFormat,

    /// Token signature verification failed
    #[error("Invalid token signature")]
    InvalidSignature,

    /// Token issuer not recognized
    #[error("Unknown token issuer")]
    UnknownIssuer {
        issuer: String,
    },

    /// Invalid audience for token
    #[error("Invalid token audience")]
    InvalidAudience {
        expected: String,
        actual: String,
    },

    /// Missing required claims
    #[error("Missing required claims")]
    MissingClaims {
        claims: Vec<String>,
    },

    /// Account locked
    #[error("Account locked")]
    AccountLocked {
        reason: String,
        locked_until: Option<DateTime<Utc>>,
    },

    /// Account suspended
    #[error("Account suspended")]
    AccountSuspended {
        reason: String,
    },

    /// Account not verified
    #[error("Account not verified")]
    AccountNotVerified,

    /// Two-factor authentication required
    #[error("Two-factor authentication required")]
    TwoFactorRequired,

    /// Invalid two-factor code
    #[error("Invalid two-factor code")]
    InvalidTwoFactorCode,

    /// Session expired
    #[error("Session expired")]
    SessionExpired,

    /// Session invalidated
    #[error("Session invalidated")]
    SessionInvalidated,

    /// Insufficient permissions
    #[error("Insufficient permissions")]
    InsufficientPermissions {
        required: Vec<String>,
        actual: Vec<String>,
    },

    /// Resource access denied
    #[error("Access denied to resource")]
    ResourceAccessDenied {
        resource_type: String,
        resource_id: String,
        action: String,
    },

    /// API key invalid
    #[error("Invalid API key")]
    InvalidApiKey,

    /// API key revoked
    #[error("API key revoked")]
    ApiKeyRevoked,

    /// Rate limit for auth attempts
    #[error("Too many authentication attempts")]
    TooManyAttempts {
        retry_after: DateTime<Utc>,
    },

    /// Generic auth error (for security)
    #[error("Authentication failed")]
    Generic,
}

impl AuthError {
    /// Check if error is retryable
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            Self::TooManyAttempts { .. } | Self::AccountLocked { .. }
        )
    }

    /// Get retry delay if applicable
    pub fn retry_after(&self) -> Option<DateTime<Utc>> {
        match self {
            Self::TooManyAttempts { retry_after } => Some(*retry_after),
            Self::AccountLocked { locked_until, .. } => *locked_until,
            _ => None,
        }
    }

    /// Check if error indicates permanent failure
    pub fn is_permanent(&self) -> bool {
        matches!(
            self,
            Self::AccountSuspended { .. }
            | Self::ApiKeyRevoked
            | Self::InvalidCredentials
        )
    }

    /// Get safe error message for client
    /// This avoids leaking information about what specifically failed
    pub fn client_message(&self) -> &'static str {
        match self {
            Self::MissingCredentials => "Authentication required",
            Self::InvalidCredentials
            | Self::InvalidTokenFormat
            | Self::InvalidSignature
            | Self::UnknownIssuer { .. }
            | Self::InvalidAudience { .. } => "Authentication failed",
            Self::TokenExpired { .. } => "Session expired",
            Self::TokenNotYetValid { .. } => "Token not yet valid",
            Self::AccountLocked { .. } => "Account temporarily locked",
            Self::AccountSuspended { .. } => "Account suspended",
            Self::AccountNotVerified => "Account verification required",
            Self::TwoFactorRequired => "Two-factor authentication required",
            Self::InvalidTwoFactorCode => "Invalid verification code",
            Self::SessionExpired | Self::SessionInvalidated => "Session expired",
            Self::InsufficientPermissions { .. } | Self::ResourceAccessDenied { .. } => {
                "Access denied"
            }
            Self::InvalidApiKey | Self::ApiKeyRevoked => "Invalid API key",
            Self::TooManyAttempts { .. } => "Too many attempts",
            _ => "Authentication failed",
        }
    }

    /// Log the error with appropriate context (no PII)
    pub fn log(&self) {
        match self {
            Self::TooManyAttempts { retry_after } => {
                tracing::warn!(
                    retry_after = %retry_after,
                    "Authentication rate limited"
                );
            }
            Self::AccountLocked { reason, locked_until } => {
                tracing::warn!(
                    reason = reason,
                    locked_until = ?locked_until,
                    "Account locked"
                );
            }
            Self::InvalidCredentials => {
                tracing::debug!("Invalid credentials attempted");
            }
            Self::TokenExpired { expired_at } => {
                tracing::debug!(expired_at = %expired_at, "Token expired");
            }
            Self::InsufficientPermissions { required, actual } => {
                tracing::warn!(
                    required = ?required,
                    actual = ?actual,
                    "Insufficient permissions"
                );
            }
            _ => {
                tracing::debug!(error = ?self, "Authentication error");
            }
        }
    }
}

/// Permission check builder
pub struct PermissionCheck {
    required: Vec<String>,
    actual: Vec<String>,
}

impl PermissionCheck {
    /// Create new permission check
    pub fn new() -> Self {
        Self {
            required: Vec::new(),
            actual: Vec::new(),
        }
    }

    /// Add required permission
    pub fn require(mut self, permission: impl Into<String>) -> Self {
        self.required.push(permission.into());
        self
    }

    /// Add multiple required permissions
    pub fn require_all(mut self, permissions: impl IntoIterator<Item = impl Into<String>>) -> Self {
        self.required.extend(permissions.into_iter().map(Into::into));
        self
    }

    /// Set actual permissions
    pub fn with_actual(mut self, permissions: impl IntoIterator<Item = impl Into<String>>) -> Self {
        self.actual = permissions.into_iter().map(Into::into).collect();
        self
    }

    /// Check if permissions are satisfied
    pub fn check(self) -> Result<(), AuthError> {
        let missing: Vec<_> = self.required
            .iter()
            .filter(|req| !self.actual.contains(req))
            .collect();

        if !missing.is_empty() {
            return Err(AuthError::InsufficientPermissions {
                required: self.required,
                actual: self.actual,
            });
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_message_safety() {
        // Ensure sensitive errors don't leak information
        let error = AuthError::InvalidCredentials;
        assert_eq!(error.client_message(), "Authentication failed");

        let error = AuthError::UnknownIssuer {
            issuer: "malicious.com".to_string(),
        };
        assert_eq!(error.client_message(), "Authentication failed");
        // The actual issuer is not exposed in client message
    }

    #[test]
    fn test_permission_check() {
        let result = PermissionCheck::new()
            .require("read")
            .require("write")
            .with_actual(vec!["read", "write", "admin"])
            .check();

        assert!(result.is_ok());

        let result = PermissionCheck::new()
            .require("admin")
            .with_actual(vec!["read", "write"])
            .check();

        assert!(result.is_err());
    }

    #[test]
    fn test_retryable_errors() {
        let error = AuthError::TooManyAttempts {
            retry_after: Utc::now() + chrono::Duration::minutes(5),
        };
        assert!(error.is_retryable());
        assert!(error.retry_after().is_some());

        let error = AuthError::InvalidCredentials;
        assert!(!error.is_retryable());
        assert!(error.retry_after().is_none());
    }
}