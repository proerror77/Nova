//! JWT Claims Structure and Authorization Helpers
//!
//! This module defines the JwtClaims structure that is extracted from validated tokens
//! and stored in request extensions for access by service handlers.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// JWT Claims extracted from validated tokens
///
/// This structure is derived from crypto-core's JWT Claims but simplified
/// for authorization purposes in backend services.
///
/// ## Design Notes
///
/// - Fields are public for direct access (no getter boilerplate)
/// - Cloneable for storing in multiple contexts if needed
/// - Derived from crypto_core::jwt::Claims via validation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JwtClaims {
    /// User ID (UUID parsed from `sub` claim)
    pub user_id: Uuid,

    /// Email address
    pub email: String,

    /// Username
    pub username: String,

    /// Token type ("access" or "refresh")
    pub token_type: String,

    /// Issued at timestamp (Unix timestamp)
    pub iat: i64,

    /// Expiration timestamp (Unix timestamp)
    pub exp: i64,

    /// Unique token identifier (for replay protection)
    pub jti: Option<String>,
}

impl JwtClaims {
    /// Create JwtClaims from crypto-core's validated Claims
    ///
    /// This is the bridge between the JWT validation layer and the authorization layer.
    ///
    /// ## Errors
    ///
    /// Returns error if `sub` field is not a valid UUID
    pub fn from_validated_claims(claims: &crypto_core::jwt::Claims) -> Result<Self, anyhow::Error> {
        let user_id = Uuid::parse_str(&claims.sub)
            .map_err(|e| anyhow::anyhow!("Invalid user ID in JWT: {}", e))?;

        Ok(Self {
            user_id,
            email: claims.email.clone(),
            username: claims.username.clone(),
            token_type: claims.token_type.clone(),
            iat: claims.iat,
            exp: claims.exp,
            jti: claims.jti.clone(),
        })
    }

    /// Check if token is an access token
    ///
    /// Access tokens should be used for API authentication.
    /// Refresh tokens should only be used for token renewal.
    pub fn is_access_token(&self) -> bool {
        self.token_type == "access"
    }

    /// Check if token is a refresh token
    pub fn is_refresh_token(&self) -> bool {
        self.token_type == "refresh"
    }

    /// Check if the user ID matches a given UUID
    ///
    /// Useful for resource ownership checks:
    ///
    /// ```rust,no_run
    /// # use uuid::Uuid;
    /// # use grpc_jwt_propagation::JwtClaims;
    /// # let claims = JwtClaims {
    /// #     user_id: Uuid::new_v4(),
    /// #     email: "test@example.com".to_string(),
    /// #     username: "testuser".to_string(),
    /// #     token_type: "access".to_string(),
    /// #     iat: 0,
    /// #     exp: 0,
    /// #     jti: None,
    /// # };
    /// let resource_owner_id = Uuid::new_v4();
    ///
    /// if !claims.is_owner(&resource_owner_id) {
    ///     // Return permission denied
    /// }
    /// ```
    pub fn is_owner(&self, resource_owner_id: &Uuid) -> bool {
        &self.user_id == resource_owner_id
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_from_validated_claims() {
        let user_id = Uuid::new_v4();
        let crypto_claims = crypto_core::jwt::Claims {
            sub: user_id.to_string(),
            email: "test@example.com".to_string(),
            username: "testuser".to_string(),
            token_type: "access".to_string(),
            iat: 1234567890,
            exp: 1234571490,
            nbf: Some(1234567890),
            jti: Some(Uuid::new_v4().to_string()),
        };

        let jwt_claims =
            JwtClaims::from_validated_claims(&crypto_claims).expect("Should convert successfully");

        assert_eq!(jwt_claims.user_id, user_id);
        assert_eq!(jwt_claims.email, "test@example.com");
        assert_eq!(jwt_claims.username, "testuser");
        assert_eq!(jwt_claims.token_type, "access");
        assert_eq!(jwt_claims.iat, 1234567890);
        assert_eq!(jwt_claims.exp, 1234571490);
        assert!(jwt_claims.jti.is_some());
    }

    #[test]
    fn test_from_validated_claims_invalid_uuid() {
        let crypto_claims = crypto_core::jwt::Claims {
            sub: "not-a-uuid".to_string(),
            email: "test@example.com".to_string(),
            username: "testuser".to_string(),
            token_type: "access".to_string(),
            iat: 1234567890,
            exp: 1234571490,
            nbf: Some(1234567890),
            jti: Some(Uuid::new_v4().to_string()),
        };

        let result = JwtClaims::from_validated_claims(&crypto_claims);
        assert!(result.is_err());
    }

    #[test]
    fn test_is_access_token() {
        let claims = JwtClaims {
            user_id: Uuid::new_v4(),
            email: "test@example.com".to_string(),
            username: "testuser".to_string(),
            token_type: "access".to_string(),
            iat: 0,
            exp: 0,
            jti: None,
        };

        assert!(claims.is_access_token());
        assert!(!claims.is_refresh_token());
    }

    #[test]
    fn test_is_refresh_token() {
        let claims = JwtClaims {
            user_id: Uuid::new_v4(),
            email: "test@example.com".to_string(),
            username: "testuser".to_string(),
            token_type: "refresh".to_string(),
            iat: 0,
            exp: 0,
            jti: None,
        };

        assert!(!claims.is_access_token());
        assert!(claims.is_refresh_token());
    }

    #[test]
    fn test_is_owner() {
        let user_id = Uuid::new_v4();
        let claims = JwtClaims {
            user_id,
            email: "test@example.com".to_string(),
            username: "testuser".to_string(),
            token_type: "access".to_string(),
            iat: 0,
            exp: 0,
            jti: None,
        };

        assert!(claims.is_owner(&user_id));
        assert!(!claims.is_owner(&Uuid::new_v4()));
    }
}
