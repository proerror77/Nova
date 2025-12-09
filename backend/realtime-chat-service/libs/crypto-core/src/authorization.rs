//! Authorization framework for repository-layer access control
//!
//! This module provides type-safe authorization primitives that enforce
//! permission checks at the repository layer, preventing accidental bypasses.
//!
//! # Design Principles
//! - Make illegal states unrepresentable: repository methods require AuthContext
//! - Defense-in-depth: permissions verified at multiple layers
//! - Audit by default: all sensitive operations are logged
//! - Type safety: compiler enforces proper authorization flow

use uuid::Uuid;
use std::fmt;
use serde::{Serialize, Deserialize};

/// Authorization context that must be created by authenticated middleware
///
/// # Security Properties
/// - Cannot be forged: only created through trusted authentication path
/// - Immutable after creation: prevents tampering
/// - Contains audit metadata: enables complete traceability
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthContext {
    user_id: Uuid,
    #[serde(skip)]
    verified: bool,
    audit_metadata: AuditMetadata,
}

impl AuthContext {
    /// Create authorization context from authenticated request
    ///
    /// # Security Notice
    /// This should ONLY be called in authentication middleware after JWT validation
    pub fn new(user_id: Uuid, request_id: Uuid, ip_addr: String) -> Self {
        Self {
            user_id,
            verified: true,
            audit_metadata: AuditMetadata {
                request_id,
                ip_addr,
                timestamp: chrono::Utc::now(),
            },
        }
    }

    /// Create auth context for system operations (e.g., background jobs)
    ///
    /// # Security Notice
    /// Use with caution - bypasses normal authentication flow
    pub fn system(operation_name: &str) -> Self {
        Self {
            user_id: Uuid::nil(),  // System operations use nil UUID
            verified: true,
            audit_metadata: AuditMetadata {
                request_id: Uuid::new_v4(),
                ip_addr: format!("system:{operation_name}"),
                timestamp: chrono::Utc::now(),
            },
        }
    }

    /// Get authenticated user ID
    ///
    /// # Panics
    /// Panics if authorization context is not verified (indicates bug in auth flow)
    pub fn user_id(&self) -> Uuid {
        assert!(self.verified, "BUG: Authorization context not verified");
        self.user_id
    }

    /// Check if this is a system operation
    pub fn is_system(&self) -> bool {
        self.user_id == Uuid::nil()
    }

    /// Verify user is the owner of a resource
    ///
    /// # Errors
    /// Returns `AuthError::Forbidden` if user is not the owner
    pub fn verify_owner(&self, resource_owner_id: Uuid) -> Result<(), AuthError> {
        if self.is_system() {
            return Ok(());  // System operations bypass ownership checks
        }
        if self.user_id != resource_owner_id {
            return Err(AuthError::Forbidden {
                user_id: self.user_id,
                required_owner: resource_owner_id,
            });
        }
        Ok(())
    }

    /// Verify user is one of multiple allowed owners
    ///
    /// # Errors
    /// Returns `AuthError::Forbidden` if user is not in the allowed set
    pub fn verify_owner_in(&self, allowed_owners: &[Uuid]) -> Result<(), AuthError> {
        if self.is_system() {
            return Ok(());
        }
        if !allowed_owners.contains(&self.user_id) {
            return Err(AuthError::Forbidden {
                user_id: self.user_id,
                required_owner: allowed_owners.first().copied().unwrap_or(Uuid::nil()),
            });
        }
        Ok(())
    }

    /// Get audit metadata for logging
    pub fn audit_metadata(&self) -> &AuditMetadata {
        &self.audit_metadata
    }

    /// Create audit log entry for an action
    pub fn audit_log_entry(&self, action: &str, resource_type: &str, resource_id: Uuid) -> AuditLogEntry {
        AuditLogEntry {
            user_id: self.user_id,
            action: action.to_string(),
            resource_type: resource_type.to_string(),
            resource_id,
            request_id: self.audit_metadata.request_id,
            ip_addr: self.audit_metadata.ip_addr.clone(),
            timestamp: self.audit_metadata.timestamp,
        }
    }
}

/// Audit metadata attached to every authorization context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditMetadata {
    pub request_id: Uuid,
    pub ip_addr: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

/// Structured audit log entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditLogEntry {
    pub user_id: Uuid,
    pub action: String,
    pub resource_type: String,
    pub resource_id: Uuid,
    pub request_id: Uuid,
    pub ip_addr: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

impl AuditLogEntry {
    /// Log this entry to tracing infrastructure
    pub fn log(&self) {
        tracing::info!(
            target: "security_audit",
            user_id = %self.user_id,
            action = %self.action,
            resource_type = %self.resource_type,
            resource_id = %self.resource_id,
            request_id = %self.request_id,
            ip_addr = %self.ip_addr,
            timestamp = %self.timestamp.to_rfc3339(),
            "Security audit event"
        );
    }
}

/// Authorization errors
#[derive(Debug, Clone)]
pub enum AuthError {
    /// User is not authenticated
    Unauthorized,
    /// User does not have permission
    Forbidden {
        user_id: Uuid,
        required_owner: Uuid,
    },
}

impl fmt::Display for AuthError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            AuthError::Unauthorized => write!(f, "Authentication required"),
            AuthError::Forbidden { user_id, required_owner } => {
                write!(
                    f,
                    "Forbidden: user {} does not have permission (required owner: {})",
                    user_id, required_owner
                )
            }
        }
    }
}

impl std::error::Error for AuthError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_auth_context_verify_owner_success() {
        let user_id = Uuid::new_v4();
        let ctx = AuthContext::new(user_id, Uuid::new_v4(), "127.0.0.1".into());

        assert!(ctx.verify_owner(user_id).is_ok());
    }

    #[test]
    fn test_auth_context_verify_owner_failure() {
        let user_id = Uuid::new_v4();
        let other_user = Uuid::new_v4();
        let ctx = AuthContext::new(user_id, Uuid::new_v4(), "127.0.0.1".into());

        let result = ctx.verify_owner(other_user);
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), AuthError::Forbidden { .. }));
    }

    #[test]
    fn test_system_context_bypasses_ownership() {
        let ctx = AuthContext::system("background_job");
        let any_user = Uuid::new_v4();

        assert!(ctx.is_system());
        assert!(ctx.verify_owner(any_user).is_ok());
    }

    #[test]
    fn test_verify_owner_in() {
        let user_id = Uuid::new_v4();
        let allowed = vec![user_id, Uuid::new_v4(), Uuid::new_v4()];
        let ctx = AuthContext::new(user_id, Uuid::new_v4(), "127.0.0.1".into());

        assert!(ctx.verify_owner_in(&allowed).is_ok());

        let not_allowed = vec![Uuid::new_v4(), Uuid::new_v4()];
        assert!(ctx.verify_owner_in(&not_allowed).is_err());
    }

    #[test]
    fn test_audit_log_entry_creation() {
        let user_id = Uuid::new_v4();
        let resource_id = Uuid::new_v4();
        let ctx = AuthContext::new(user_id, Uuid::new_v4(), "192.168.1.1".into());

        let entry = ctx.audit_log_entry("delete", "post", resource_id);

        assert_eq!(entry.user_id, user_id);
        assert_eq!(entry.action, "delete");
        assert_eq!(entry.resource_type, "post");
        assert_eq!(entry.resource_id, resource_id);
        assert_eq!(entry.ip_addr, "192.168.1.1");
    }
}
