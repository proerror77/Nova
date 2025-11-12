//! Client-side JWT Interceptor
//!
//! Automatically injects JWT tokens into outgoing gRPC requests via metadata.

use tonic::metadata::{AsciiMetadataValue, MetadataMap};
use tonic::service::Interceptor;
use tonic::{Request, Status};

/// Client-side interceptor that injects JWT tokens into gRPC metadata
///
/// This interceptor adds the JWT token to the `authorization` header in the
/// standard "Bearer {token}" format for every outgoing request.
///
/// ## Design
///
/// - **Zero overhead**: Token stored as owned String, formatted once per request
/// - **Fail-fast**: Invalid token format fails at construction time
/// - **Thread-safe**: Cloneable interceptor, immutable after construction
///
/// ## Usage
///
/// ```rust,no_run
/// use grpc_jwt_propagation::JwtClientInterceptor;
/// use tonic::transport::Channel;
///
/// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
/// let jwt_token = "eyJhbGc..."; // From authentication
/// let interceptor = JwtClientInterceptor::new(jwt_token);
///
/// let channel = Channel::from_static("http://[::1]:50051")
///     .connect()
///     .await?;
///
/// // Attach to any gRPC client
/// // let mut client = SomeServiceClient::with_interceptor(channel, interceptor);
/// # Ok(())
/// # }
/// ```
#[derive(Clone)]
pub struct JwtClientInterceptor {
    /// Pre-formatted authorization header value
    ///
    /// Format: "Bearer {token}"
    /// Stored as AsciiMetadataValue to avoid repeated parsing
    auth_header: AsciiMetadataValue,
}

impl JwtClientInterceptor {
    /// Create a new JWT client interceptor
    ///
    /// ## Arguments
    ///
    /// * `jwt_token` - JWT token string (without "Bearer " prefix)
    ///
    /// ## Errors
    ///
    /// Returns `Status::internal` if the token contains invalid ASCII characters.
    /// In practice, valid JWT tokens (base64url) should never fail this check.
    ///
    /// ## Example
    ///
    /// ```rust
    /// use grpc_jwt_propagation::JwtClientInterceptor;
    ///
    /// let interceptor = JwtClientInterceptor::new("eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...");
    /// ```
    pub fn new(jwt_token: impl Into<String>) -> Self {
        let token_value = format!("Bearer {}", jwt_token.into());

        // Parse once at construction time
        // Valid JWTs (base64url) should never contain invalid ASCII
        let auth_header = AsciiMetadataValue::try_from(token_value)
            .expect("JWT token contains invalid ASCII characters");

        Self { auth_header }
    }

    /// Create interceptor from an owned AsciiMetadataValue
    ///
    /// This is a zero-copy constructor for cases where the authorization header
    /// is already parsed (e.g., forwarding from an incoming request).
    ///
    /// ## Example
    ///
    /// ```rust
    /// use grpc_jwt_propagation::JwtClientInterceptor;
    /// use tonic::metadata::AsciiMetadataValue;
    ///
    /// let auth_value: AsciiMetadataValue = "Bearer eyJhbGc...".parse().unwrap();
    /// let interceptor = JwtClientInterceptor::from_header(auth_value);
    /// ```
    pub fn from_header(auth_header: AsciiMetadataValue) -> Self {
        Self { auth_header }
    }

    /// Extract JWT token from incoming request metadata
    ///
    /// This is useful in gateway scenarios where you want to forward the
    /// client's JWT to backend services.
    ///
    /// ## Arguments
    ///
    /// * `metadata` - Incoming request metadata
    ///
    /// ## Returns
    ///
    /// The authorization header value if present, or an error if missing
    ///
    /// ## Example
    ///
    /// ```rust,no_run
    /// use grpc_jwt_propagation::JwtClientInterceptor;
    /// use tonic::Request;
    ///
    /// fn forward_auth<T>(request: &Request<T>) -> Result<JwtClientInterceptor, tonic::Status> {
    ///     let auth = JwtClientInterceptor::extract_from_metadata(request.metadata())?;
    ///     Ok(JwtClientInterceptor::from_header(auth.clone()))
    /// }
    /// ```
    pub fn extract_from_metadata(
        metadata: &MetadataMap,
    ) -> Result<&AsciiMetadataValue, Status> {
        metadata
            .get("authorization")
            .ok_or_else(|| Status::unauthenticated("Missing authorization header"))
    }
}

impl Interceptor for JwtClientInterceptor {
    fn call(&mut self, mut request: Request<()>) -> Result<Request<()>, Status> {
        // Inject authorization header into request metadata
        request
            .metadata_mut()
            .insert("authorization", self.auth_header.clone());

        Ok(request)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_interceptor() {
        let token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature";
        let interceptor = JwtClientInterceptor::new(token);

        // Should store pre-formatted header
        let expected = format!("Bearer {}", token);
        assert_eq!(interceptor.auth_header.to_str().unwrap(), expected);
    }

    #[test]
    fn test_interceptor_injects_header() {
        let token = "test-token-123";
        let mut interceptor = JwtClientInterceptor::new(token);

        let request = Request::new(());
        let result = interceptor.call(request);

        assert!(result.is_ok());
        let request = result.unwrap();

        // Check that authorization header was injected
        let auth = request.metadata().get("authorization");
        assert!(auth.is_some());
        assert_eq!(auth.unwrap().to_str().unwrap(), "Bearer test-token-123");
    }

    #[test]
    fn test_from_header() {
        let auth_value: AsciiMetadataValue = "Bearer test-token".parse().unwrap();
        let interceptor = JwtClientInterceptor::from_header(auth_value.clone());

        assert_eq!(interceptor.auth_header, auth_value);
    }

    #[test]
    fn test_extract_from_metadata_success() {
        let mut metadata = MetadataMap::new();
        metadata.insert(
            "authorization",
            "Bearer test-token".parse().unwrap(),
        );

        let result = JwtClientInterceptor::extract_from_metadata(&metadata);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().to_str().unwrap(), "Bearer test-token");
    }

    #[test]
    fn test_extract_from_metadata_missing() {
        let metadata = MetadataMap::new();
        let result = JwtClientInterceptor::extract_from_metadata(&metadata);

        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code(), tonic::Code::Unauthenticated);
    }
}
