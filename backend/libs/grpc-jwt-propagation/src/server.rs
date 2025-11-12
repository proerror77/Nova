//! Server-side JWT Interceptor
//!
//! Extracts and validates JWT tokens from incoming gRPC requests,
//! storing the validated claims in request extensions.

use crate::claims::JwtClaims;
use tonic::service::Interceptor;
use tonic::{Request, Status};
use tracing::{debug, warn};

/// Server-side interceptor that validates JWT tokens and extracts claims
///
/// This interceptor:
/// 1. Extracts the `authorization` header from gRPC metadata
/// 2. Validates the JWT token using crypto-core
/// 3. Parses the claims into JwtClaims
/// 4. Stores claims in request extensions for handler access
///
/// ## Design
///
/// - **Fail-fast**: Any validation error returns `Status::unauthenticated`
/// - **Zero tolerance**: Missing/invalid/expired tokens all fail the same way
/// - **Structured logging**: Validation failures logged at WARN level
/// - **No bypass**: Every request goes through the same validation path
///
/// ## Security
///
/// - Uses crypto-core's RS256-only validation (no algorithm confusion)
/// - Checks token expiration automatically
/// - Validates token structure and signature
/// - Logs failures for audit trail
///
/// ## Usage
///
/// ```rust,no_run
/// use grpc_jwt_propagation::JwtServerInterceptor;
/// use tonic::transport::Server;
///
/// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
/// // In main.rs before starting server
/// let public_key = std::env::var("JWT_PUBLIC_KEY_PEM")?;
/// crypto_core::jwt::initialize_jwt_validation_only(&public_key)?;
///
/// // Attach interceptor to service
/// // let service = MyServiceServer::with_interceptor(
/// //     MyService,
/// //     JwtServerInterceptor,
/// // );
/// # Ok(())
/// # }
/// ```
#[derive(Clone, Copy)]
pub struct JwtServerInterceptor;

impl JwtServerInterceptor {
    /// Extract and validate JWT token from request metadata
    ///
    /// This is the core validation logic:
    /// 1. Extract authorization header
    /// 2. Strip "Bearer " prefix
    /// 3. Validate token signature and expiration
    /// 4. Parse claims into JwtClaims
    ///
    /// ## Errors
    ///
    /// Returns `Status::unauthenticated` if:
    /// - Authorization header is missing
    /// - Authorization header format is invalid (not "Bearer {token}")
    /// - Token signature is invalid
    /// - Token is expired
    /// - Token structure is malformed
    fn extract_and_validate_jwt(metadata: &tonic::metadata::MetadataMap) -> Result<JwtClaims, Status> {
        // 1. Extract authorization header
        let auth_header = metadata
            .get("authorization")
            .ok_or_else(|| {
                warn!("Missing authorization header");
                Status::unauthenticated("Missing authorization header")
            })?;

        // 2. Convert to string
        let auth_str = auth_header.to_str().map_err(|e| {
            warn!("Invalid authorization header encoding: {}", e);
            Status::unauthenticated("Invalid authorization header")
        })?;

        // 3. Strip "Bearer " prefix
        let token = auth_str.strip_prefix("Bearer ").ok_or_else(|| {
            warn!("Invalid authorization format (expected 'Bearer <token>')");
            Status::unauthenticated("Invalid authorization format")
        })?;

        debug!("Validating JWT token");

        // 4. Validate token using crypto-core
        let token_data = crypto_core::jwt::validate_token(token).map_err(|e| {
            warn!("JWT validation failed: {}", e);
            Status::unauthenticated(format!("JWT validation failed: {}", e))
        })?;

        // 5. Convert to JwtClaims
        let claims = JwtClaims::from_validated_claims(&token_data.claims).map_err(|e| {
            warn!("Failed to parse JWT claims: {}", e);
            Status::internal(format!("Failed to parse JWT claims: {}", e))
        })?;

        debug!(
            user_id = %claims.user_id,
            email = %claims.email,
            "JWT validated successfully"
        );

        Ok(claims)
    }
}

impl Interceptor for JwtServerInterceptor {
    fn call(&mut self, mut request: Request<()>) -> Result<Request<()>, Status> {
        // Extract and validate JWT
        let claims = Self::extract_and_validate_jwt(request.metadata())?;

        // Store claims in request extensions for handler access
        request.extensions_mut().insert(claims);

        Ok(request)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tonic::metadata::{MetadataMap, MetadataValue};

    // Initialize JWT keys for testing
    fn init_test_keys() {
        static INIT: std::sync::Once = std::sync::Once::new();
        INIT.call_once(|| {
            // Test RSA key pair (same as crypto-core tests)
            const TEST_PRIVATE_KEY: &str = include_str!("../tests/test_private_key.pem");
            const TEST_PUBLIC_KEY: &str = include_str!("../tests/test_public_key.pem");

            crypto_core::jwt::initialize_jwt_keys(TEST_PRIVATE_KEY, TEST_PUBLIC_KEY)
                .expect("Failed to initialize test keys");
        });
    }

    #[test]
    fn test_extract_and_validate_missing_header() {
        init_test_keys();

        let metadata = MetadataMap::new();
        let result = JwtServerInterceptor::extract_and_validate_jwt(&metadata);

        assert!(result.is_err());
        let status = result.unwrap_err();
        assert_eq!(status.code(), tonic::Code::Unauthenticated);
        assert!(status.message().contains("Missing authorization header"));
    }

    #[test]
    fn test_extract_and_validate_invalid_format() {
        init_test_keys();

        let mut metadata = MetadataMap::new();
        metadata.insert("authorization", MetadataValue::from_static("InvalidFormat"));

        let result = JwtServerInterceptor::extract_and_validate_jwt(&metadata);

        assert!(result.is_err());
        let status = result.unwrap_err();
        assert_eq!(status.code(), tonic::Code::Unauthenticated);
        assert!(status.message().contains("Invalid authorization format"));
    }

    #[test]
    fn test_extract_and_validate_valid_token() {
        init_test_keys();

        // Generate a valid token
        let user_id = uuid::Uuid::new_v4();
        let token = crypto_core::jwt::generate_access_token(
            user_id,
            "test@example.com",
            "testuser",
        )
        .expect("Failed to generate token");

        // Create metadata with Bearer token
        let mut metadata = MetadataMap::new();
        let auth_value = format!("Bearer {}", token);
        metadata.insert(
            "authorization",
            auth_value.parse().unwrap(),
        );

        let result = JwtServerInterceptor::extract_and_validate_jwt(&metadata);

        assert!(result.is_ok());
        let claims = result.unwrap();
        assert_eq!(claims.user_id, user_id);
        assert_eq!(claims.email, "test@example.com");
        assert_eq!(claims.username, "testuser");
        assert_eq!(claims.token_type, "access");
    }

    #[test]
    fn test_extract_and_validate_tampered_token() {
        init_test_keys();

        let user_id = uuid::Uuid::new_v4();
        let token = crypto_core::jwt::generate_access_token(
            user_id,
            "test@example.com",
            "testuser",
        )
        .expect("Failed to generate token");

        // Tamper with token
        let tampered = token.replace("a", "b");

        let mut metadata = MetadataMap::new();
        let auth_value = format!("Bearer {}", tampered);
        metadata.insert(
            "authorization",
            auth_value.parse().unwrap(),
        );

        let result = JwtServerInterceptor::extract_and_validate_jwt(&metadata);

        assert!(result.is_err());
        let status = result.unwrap_err();
        assert_eq!(status.code(), tonic::Code::Unauthenticated);
    }

    #[test]
    fn test_interceptor_stores_claims_in_extensions() {
        init_test_keys();

        let user_id = uuid::Uuid::new_v4();
        let token = crypto_core::jwt::generate_access_token(
            user_id,
            "test@example.com",
            "testuser",
        )
        .expect("Failed to generate token");

        let mut request = Request::new(());
        let auth_value = format!("Bearer {}", token);
        request.metadata_mut().insert(
            "authorization",
            auth_value.parse().unwrap(),
        );

        let mut interceptor = JwtServerInterceptor;
        let result = interceptor.call(request);

        assert!(result.is_ok());
        let request = result.unwrap();

        // Check that claims were stored in extensions
        let claims = request.extensions().get::<JwtClaims>();
        assert!(claims.is_some());

        let claims = claims.unwrap();
        assert_eq!(claims.user_id, user_id);
        assert_eq!(claims.email, "test@example.com");
    }
}
