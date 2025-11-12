//! Request Extension Trait for JWT Claims Access
//!
//! Provides ergonomic helpers for accessing JWT claims from gRPC request handlers.

use crate::JwtClaims;
use tonic::{Request, Status};
use uuid::Uuid;

/// Extension trait for accessing JWT claims from gRPC requests
///
/// This trait is implemented for all `Request<T>` types, providing convenient
/// methods to extract and validate JWT claims that were stored by the
/// JwtServerInterceptor.
///
/// ## Design
///
/// - **Type-safe**: Returns references to avoid cloning
/// - **Fail-fast**: Missing claims return `Status::unauthenticated`
/// - **Clear errors**: Permission errors return `Status::permission_denied`
/// - **Zero boilerplate**: One-line authorization checks
///
/// ## Usage
///
/// ```rust,no_run
/// use grpc_jwt_propagation::JwtClaimsExt;
/// use tonic::{Request, Response, Status};
/// use uuid::Uuid;
///
/// async fn delete_post(
///     request: Request<()>,
/// ) -> Result<Response<()>, Status> {
///     // Extract claims (fails if not authenticated)
///     let claims = request.jwt_claims()?;
///
///     // Check ownership: only post author can delete
///     let post_owner = Uuid::new_v4(); // From database
///     if !claims.is_owner(&post_owner) {
///         return Err(Status::permission_denied(
///             "You can only delete your own posts"
///         ));
///     }
///
///     Ok(Response::new(()))
/// }
/// ```
pub trait JwtClaimsExt {
    /// Extract JWT claims from request extensions
    ///
    /// ## Returns
    ///
    /// Reference to the validated JwtClaims stored by JwtServerInterceptor
    ///
    /// ## Errors
    ///
    /// Returns `Status::unauthenticated` if:
    /// - JwtServerInterceptor was not attached to the service
    /// - JWT validation failed (claims were not stored)
    ///
    /// ## Example
    ///
    /// ```rust,no_run
    /// use grpc_jwt_propagation::JwtClaimsExt;
    /// use tonic::{Request, Status};
    ///
    /// fn handler<T>(request: Request<T>) -> Result<(), Status> {
    ///     let claims = request.jwt_claims()?;
    ///     println!("User ID: {}", claims.user_id);
    ///     Ok(())
    /// }
    /// ```
    fn jwt_claims(&self) -> Result<&JwtClaims, Status>;

    /// Require that the authenticated user owns a specific resource
    ///
    /// This is a convenience method for the common pattern of checking if
    /// the current user is the owner of a resource.
    ///
    /// ## Arguments
    ///
    /// * `resource_owner_id` - UUID of the resource owner to check against
    ///
    /// ## Returns
    ///
    /// Reference to claims if user is the owner
    ///
    /// ## Errors
    ///
    /// - `Status::unauthenticated` if no JWT claims found
    /// - `Status::permission_denied` if user is not the owner
    ///
    /// ## Example
    ///
    /// ```rust,no_run
    /// use grpc_jwt_propagation::JwtClaimsExt;
    /// use tonic::{Request, Status};
    /// use uuid::Uuid;
    ///
    /// async fn update_profile(request: Request<()>) -> Result<(), Status> {
    ///     let user_id = Uuid::new_v4(); // From request
    ///     request.require_ownership(&user_id)?;
    ///     // User is confirmed to be the owner, proceed with update
    ///     Ok(())
    /// }
    /// ```
    fn require_ownership(&self, resource_owner_id: &Uuid) -> Result<&JwtClaims, Status>;

    /// Require that the token is an access token (not a refresh token)
    ///
    /// Refresh tokens should only be used for token renewal, not for API access.
    ///
    /// ## Returns
    ///
    /// Reference to claims if token is an access token
    ///
    /// ## Errors
    ///
    /// - `Status::unauthenticated` if no JWT claims found
    /// - `Status::permission_denied` if token is not an access token
    ///
    /// ## Example
    ///
    /// ```rust,no_run
    /// use grpc_jwt_propagation::JwtClaimsExt;
    /// use tonic::{Request, Status};
    ///
    /// async fn get_user_data(request: Request<()>) -> Result<(), Status> {
    ///     // Ensure this is an access token, not a refresh token
    ///     request.require_access_token()?;
    ///     Ok(())
    /// }
    /// ```
    fn require_access_token(&self) -> Result<&JwtClaims, Status>;
}

impl<T> JwtClaimsExt for Request<T> {
    fn jwt_claims(&self) -> Result<&JwtClaims, Status> {
        self.extensions()
            .get::<JwtClaims>()
            .ok_or_else(|| {
                Status::unauthenticated(
                    "No JWT claims found. Ensure JwtServerInterceptor is attached."
                )
            })
    }

    fn require_ownership(&self, resource_owner_id: &Uuid) -> Result<&JwtClaims, Status> {
        let claims = self.jwt_claims()?;

        if !claims.is_owner(resource_owner_id) {
            return Err(Status::permission_denied(
                "You do not have permission to access this resource"
            ));
        }

        Ok(claims)
    }

    fn require_access_token(&self) -> Result<&JwtClaims, Status> {
        let claims = self.jwt_claims()?;

        if !claims.is_access_token() {
            return Err(Status::permission_denied(
                "Access token required (refresh tokens not allowed)"
            ));
        }

        Ok(claims)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jwt_claims_missing() {
        let request = Request::new(());
        let result = request.jwt_claims();

        assert!(result.is_err());
        let status = result.unwrap_err();
        assert_eq!(status.code(), tonic::Code::Unauthenticated);
        assert!(status.message().contains("No JWT claims found"));
    }

    #[test]
    fn test_jwt_claims_present() {
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

        let mut request = Request::new(());
        request.extensions_mut().insert(claims.clone());

        let result = request.jwt_claims();
        assert!(result.is_ok());

        let extracted_claims = result.unwrap();
        assert_eq!(extracted_claims.user_id, user_id);
        assert_eq!(extracted_claims.email, "test@example.com");
    }

    #[test]
    fn test_require_ownership_success() {
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

        let mut request = Request::new(());
        request.extensions_mut().insert(claims);

        let result = request.require_ownership(&user_id);
        assert!(result.is_ok());
    }

    #[test]
    fn test_require_ownership_failure() {
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

        let mut request = Request::new(());
        request.extensions_mut().insert(claims);

        // Try with different user ID
        let other_user_id = Uuid::new_v4();
        let result = request.require_ownership(&other_user_id);

        assert!(result.is_err());
        let status = result.unwrap_err();
        assert_eq!(status.code(), tonic::Code::PermissionDenied);
    }

    #[test]
    fn test_require_access_token_success() {
        let claims = JwtClaims {
            user_id: Uuid::new_v4(),
            email: "test@example.com".to_string(),
            username: "testuser".to_string(),
            token_type: "access".to_string(),
            iat: 0,
            exp: 0,
            jti: None,
        };

        let mut request = Request::new(());
        request.extensions_mut().insert(claims);

        let result = request.require_access_token();
        assert!(result.is_ok());
    }

    #[test]
    fn test_require_access_token_failure_refresh_token() {
        let claims = JwtClaims {
            user_id: Uuid::new_v4(),
            email: "test@example.com".to_string(),
            username: "testuser".to_string(),
            token_type: "refresh".to_string(),
            iat: 0,
            exp: 0,
            jti: None,
        };

        let mut request = Request::new(());
        request.extensions_mut().insert(claims);

        let result = request.require_access_token();

        assert!(result.is_err());
        let status = result.unwrap_err();
        assert_eq!(status.code(), tonic::Code::PermissionDenied);
        assert!(status.message().contains("Access token required"));
    }
}
