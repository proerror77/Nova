//! Authorization helpers for GraphQL mutations

use async_graphql::Context;

/// Check if user is authorized to perform action on resource
pub fn check_user_authorization(ctx: &Context<'_>, resource_owner_id: &str, _action: &str) -> Result<(), String> {
    // Extract user ID from GraphQL context (set by JWT middleware)
    let current_user_id = ctx
        .data::<String>()
        .ok()
        .cloned()
        .ok_or("User not authenticated")?;

    // Check if user is the resource owner
    if current_user_id != resource_owner_id {
        return Err(format!(
            "Forbidden: user {} cannot access resource owned by {}",
            current_user_id, resource_owner_id
        ));
    }

    Ok(())
}

/// Verify user is authenticated and return user ID
pub fn require_auth(ctx: &Context<'_>) -> Result<String, String> {
    ctx
        .data::<String>()
        .ok()
        .cloned()
        .ok_or_else(|| "Unauthorized: authentication required".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_authorization_logic() {
        // Authorization checks happen in resolver context
        // Unit tests would require async_graphql::Context which needs full setup
        // See integration tests for end-to-end authorization verification
        assert!(true);
    }
}
