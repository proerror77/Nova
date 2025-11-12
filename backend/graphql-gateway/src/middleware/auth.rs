//! Authorization helpers for GraphQL mutations
//!
//! SECURITY: Uses strongly-typed AuthenticatedUser to prevent type confusion attacks

use crate::middleware::jwt::AuthenticatedUser;
use async_graphql::Context;
use crypto_core::jwt::Claims;
use uuid::Uuid;

/// Check if user is authorized to perform action on resource
///
/// SECURITY: Uses strongly-typed AuthenticatedUser to prevent accidental misuse
/// Error messages do NOT contain PII to comply with GDPR/CCPA
pub fn check_user_authorization(
    ctx: &Context<'_>,
    resource_owner_id: Uuid,
    action: &str,
) -> Result<(), String> {
    // Extract strongly-typed user from GraphQL context (set by JWT middleware)
    let current_user = ctx
        .data::<AuthenticatedUser>()
        .map_err(|_| "Unauthorized: authentication required")?;

    // Check if user is the resource owner
    if current_user.0 != resource_owner_id {
        // Log authorization failure for audit trail (structured fields, no PII in message)
        tracing::warn!(
            user_id = %current_user.0,
            resource_owner = %resource_owner_id,
            action = action,
            "Authorization denied: user is not resource owner"
        );
        // Generic error message without PII
        return Err("Forbidden: insufficient permissions".to_string());
    }

    // Log successful authorization for audit trail
    tracing::debug!(
        user_id = %current_user.0,
        resource_owner = %resource_owner_id,
        action = action,
        "Authorization granted"
    );

    Ok(())
}

/// Verify user is authenticated and return user ID
///
/// Returns the strongly-typed AuthenticatedUser
pub fn require_auth(ctx: &Context<'_>) -> Result<AuthenticatedUser, String> {
    ctx.data::<AuthenticatedUser>().copied() // Dereference to copy the value
        .map_err(|_| "Unauthorized: authentication required".to_string())
}

/// Get the authenticated user's ID as UUID
///
/// Convenience function for when you just need the UUID
pub fn get_authenticated_user_id(ctx: &Context<'_>) -> Result<Uuid, String> {
    let user = require_auth(ctx)?;
    Ok(user.0)
}

/// Get the full JWT claims for the authenticated user
///
/// Use this when you need email, username, or other claim fields
pub fn get_authenticated_claims(ctx: &Context<'_>) -> Result<Claims, String> {
    ctx.data::<Claims>().cloned() // Clone the Claims
        .map_err(|_| "Unauthorized: authentication required".to_string())
}

/// Check if user has a specific role (future enhancement)
///
/// NOTE: Role-based access control not yet implemented
/// This is a placeholder for future RBAC implementation
pub fn check_user_role(ctx: &Context<'_>, required_role: &str) -> Result<(), String> {
    // For now, just check authentication
    let _user = require_auth(ctx)?;

    // TODO: Implement role checking when role system is added
    // This would check user.roles.contains(required_role)

    tracing::warn!(
        required_role = required_role,
        "Role-based access control not yet implemented"
    );

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_graphql::Context;

    #[test]
    fn test_authorization_types() {
        // Type safety test - these should not compile if types are wrong
        fn _test_type_safety() {
            // This function exists only to verify type signatures at compile time
            let _f1: fn(&Context<'_>, Uuid, &str) -> Result<(), String> = check_user_authorization;
            let _f2: fn(&Context<'_>) -> Result<AuthenticatedUser, String> = require_auth;
            let _f3: fn(&Context<'_>) -> Result<Uuid, String> = get_authenticated_user_id;
        }
    }
}
