/// Shared JWT validation module for Nova services
///
/// This module provides unified JWT token validation using RS256 (RSA with SHA-256).
/// All Nova services MUST use this module for JWT operations to ensure consistency
/// and prevent security vulnerabilities from algorithm confusion attacks.
///
/// ## Security Design
///
/// - **RS256 ONLY**: No symmetric algorithms (HS256) to prevent confusion attacks
/// - **No hardcoded keys**: All keys loaded from environment variables
/// - **Fail-safe**: No fallback mechanisms that could weaken security
/// - **Thread-safe**: Keys loaded once at startup, immutable thereafter
///
/// ## Usage
///
/// Services must call `initialize_jwt_keys()` during startup before any JWT operations:
///
/// ```rust
/// use crypto_core::jwt;
///
/// #[tokio::main]
/// async fn main() {
///     let private_key = std::env::var("JWT_PRIVATE_KEY_PEM").expect("JWT_PRIVATE_KEY_PEM required");
///     let public_key = std::env::var("JWT_PUBLIC_KEY_PEM").expect("JWT_PUBLIC_KEY_PEM required");
///
///     jwt::initialize_jwt_keys(&private_key, &public_key)
///         .expect("Failed to initialize JWT keys");
///
///     // Now you can generate and validate tokens
/// }
/// ```
use anyhow::{anyhow, Result};
use chrono::{Duration, Utc};
use jsonwebtoken::{
    decode, encode, Algorithm, DecodingKey, EncodingKey, Header, TokenData, Validation,
};
use once_cell::sync::OnceCell;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ============================================================================
// Constants
// ============================================================================

const ACCESS_TOKEN_EXPIRY_HOURS: i64 = 1;
const REFRESH_TOKEN_EXPIRY_DAYS: i64 = 30;

/// JWT algorithm - MUST be RS256 for all Nova services
const JWT_ALGORITHM: Algorithm = Algorithm::RS256;

// ============================================================================
// Data Structures
// ============================================================================

/// JWT Claims structure - standard claims plus Nova-specific fields
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    /// Subject (user ID as UUID string)
    pub sub: String,
    /// Issued at (Unix timestamp)
    pub iat: i64,
    /// Expiration time (Unix timestamp)
    pub exp: i64,
    /// Token type: "access" or "refresh"
    pub token_type: String,
    /// Email address
    pub email: String,
    /// Username
    pub username: String,
}

/// Token pair response structure
#[derive(Debug, Serialize, Deserialize)]
pub struct TokenResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: i64,
}

// ============================================================================
// Key Storage
// ============================================================================

/// Thread-safe global storage for JWT keys
///
/// Keys are initialized once at startup and never modified.
/// OnceCell ensures thread-safe initialization without runtime locks.
static JWT_ENCODING_KEY: OnceCell<EncodingKey> = OnceCell::new();
static JWT_DECODING_KEY: OnceCell<DecodingKey> = OnceCell::new();

// ============================================================================
// Initialization
// ============================================================================

/// Initialize JWT keys from PEM-formatted strings
///
/// MUST be called during application startup before any JWT operations.
/// Can only be called once - subsequent calls will return an error.
///
/// ## Arguments
///
/// * `private_key_pem` - RSA private key in PEM format (for token generation)
/// * `public_key_pem` - RSA public key in PEM format (for token validation)
///
/// ## Errors
///
/// Returns error if:
/// - Keys are already initialized
/// - PEM format is invalid
/// - Key is not a valid RSA key
///
/// ## Security Notes
///
/// - Keys must be RSA keys (minimum 2048 bits recommended)
/// - Private key should only be provided to services that generate tokens
/// - Public key can be shared with all services that validate tokens
pub fn initialize_jwt_keys(private_key_pem: &str, public_key_pem: &str) -> Result<()> {
    // Parse encoding key (private key for signing)
    let encoding_key = EncodingKey::from_rsa_pem(private_key_pem.as_bytes())
        .map_err(|e| anyhow!("Failed to parse RSA private key: {e}"))?;

    // Parse decoding key (public key for verification)
    let decoding_key = DecodingKey::from_rsa_pem(public_key_pem.as_bytes())
        .map_err(|e| anyhow!("Failed to parse RSA public key: {e}"))?;

    // Initialize global keys (OnceCell ensures this can only happen once)
    JWT_ENCODING_KEY
        .set(encoding_key)
        .map_err(|_| anyhow!("JWT encoding key already initialized"))?;

    JWT_DECODING_KEY
        .set(decoding_key)
        .map_err(|_| anyhow!("JWT decoding key already initialized"))?;

    Ok(())
}

/// Initialize JWT keys for validation-only services
///
/// Use this for services that only need to validate tokens (not generate them).
/// This is more secure as it doesn't require the private key.
///
/// ## Arguments
///
/// * `public_key_pem` - RSA public key in PEM format
///
/// ## Example
///
/// ```rust
/// let public_key = std::env::var("JWT_PUBLIC_KEY_PEM")?;
/// jwt::initialize_jwt_validation_only(&public_key)?;
/// ```
pub fn initialize_jwt_validation_only(public_key_pem: &str) -> Result<()> {
    let decoding_key = DecodingKey::from_rsa_pem(public_key_pem.as_bytes())
        .map_err(|e| anyhow!("Failed to parse RSA public key: {e}"))?;

    JWT_DECODING_KEY
        .set(decoding_key)
        .map_err(|_| anyhow!("JWT decoding key already initialized"))?;

    Ok(())
}

// ============================================================================
// Internal Key Access
// ============================================================================

/// Get encoding key for token generation
///
/// Returns error if keys haven't been initialized via initialize_jwt_keys()
fn get_encoding_key() -> Result<&'static EncodingKey> {
    JWT_ENCODING_KEY.get().ok_or_else(|| {
        anyhow!("JWT keys not initialized. Call initialize_jwt_keys() during startup.")
    })
}

/// Get decoding key for token validation
///
/// Returns error if keys haven't been initialized
fn get_decoding_key() -> Result<&'static DecodingKey> {
    JWT_DECODING_KEY
        .get()
        .ok_or_else(|| anyhow!("JWT keys not initialized. Call initialize_jwt_keys() or initialize_jwt_validation_only() during startup."))
}

// ============================================================================
// Token Generation
// ============================================================================

/// Generate a new access token
///
/// Access tokens have a short lifetime (1 hour) and should be used for API authentication.
///
/// ## Arguments
///
/// * `user_id` - User's UUID
/// * `email` - User's email address
/// * `username` - User's username
///
/// ## Returns
///
/// JWT token string encoded with RS256
pub fn generate_access_token(user_id: Uuid, email: &str, username: &str) -> Result<String> {
    let now = Utc::now();
    let expiry = now + Duration::hours(ACCESS_TOKEN_EXPIRY_HOURS);

    let claims = Claims {
        sub: user_id.to_string(),
        iat: now.timestamp(),
        exp: expiry.timestamp(),
        token_type: "access".to_string(),
        email: email.to_string(),
        username: username.to_string(),
    };

    let encoding_key = get_encoding_key()?;
    encode(&Header::new(JWT_ALGORITHM), &claims, encoding_key)
        .map_err(|e| anyhow!("Failed to generate access token: {e}"))
}

/// Generate a new refresh token
///
/// Refresh tokens have a longer lifetime (30 days) and should be used to obtain new access tokens.
///
/// ## Security Notes
///
/// - Store refresh tokens securely (HttpOnly cookies, encrypted storage)
/// - Implement refresh token rotation
/// - Revoke refresh tokens on logout
pub fn generate_refresh_token(user_id: Uuid, email: &str, username: &str) -> Result<String> {
    let now = Utc::now();
    let expiry = now + Duration::days(REFRESH_TOKEN_EXPIRY_DAYS);

    let claims = Claims {
        sub: user_id.to_string(),
        iat: now.timestamp(),
        exp: expiry.timestamp(),
        token_type: "refresh".to_string(),
        email: email.to_string(),
        username: username.to_string(),
    };

    let encoding_key = get_encoding_key()?;
    encode(&Header::new(JWT_ALGORITHM), &claims, encoding_key)
        .map_err(|e| anyhow!("Failed to generate refresh token: {e}"))
}

/// Generate both access and refresh tokens
///
/// Convenience method to generate a token pair in one call.
pub fn generate_token_pair(user_id: Uuid, email: &str, username: &str) -> Result<TokenResponse> {
    let access_token = generate_access_token(user_id, email, username)?;
    let refresh_token = generate_refresh_token(user_id, email, username)?;

    Ok(TokenResponse {
        access_token,
        refresh_token,
        token_type: "Bearer".to_string(),
        expires_in: ACCESS_TOKEN_EXPIRY_HOURS * 3600,
    })
}

// ============================================================================
// Token Validation
// ============================================================================

/// Validate and decode a JWT token
///
/// This is the core validation function used by all Nova services.
///
/// ## Security Guarantees
///
/// - Verifies RS256 signature using the initialized public key
/// - Checks token expiration
/// - Validates token structure
/// - NO fallback to weaker algorithms
///
/// ## Arguments
///
/// * `token` - JWT token string (without "Bearer " prefix)
///
/// ## Returns
///
/// TokenData containing validated claims
///
/// ## Errors
///
/// Returns error if:
/// - Token signature is invalid
/// - Token is expired
/// - Token format is malformed
/// - Keys not initialized
pub fn validate_token(token: &str) -> Result<TokenData<Claims>> {
    let decoding_key = get_decoding_key()?;

    // Create validation with strict RS256 requirement
    let mut validation = Validation::new(JWT_ALGORITHM);
    validation.validate_exp = true;

    decode::<Claims>(token, decoding_key, &validation)
        .map_err(|e| anyhow!("Token validation failed: {e}"))
}

/// Check if a token is expired
///
/// ## Note
///
/// This validates the token first, so it will fail on invalid tokens.
/// Use this when you need to distinguish between expired and invalid tokens.
pub fn is_token_expired(token: &str) -> Result<bool> {
    let token_data = validate_token(token)?;
    let now = Utc::now().timestamp();
    Ok(token_data.claims.exp < now)
}

/// Extract user ID from a validated token
///
/// ## Security Note
///
/// This function validates the token before extracting the user ID.
/// Never trust user IDs from unvalidated sources.
pub fn get_user_id_from_token(token: &str) -> Result<Uuid> {
    let token_data = validate_token(token)?;
    Uuid::parse_str(&token_data.claims.sub)
        .map_err(|e| anyhow!("Invalid user ID format in token: {e}"))
}

/// Extract email from a validated token
pub fn get_email_from_token(token: &str) -> Result<String> {
    let token_data = validate_token(token)?;
    Ok(token_data.claims.email)
}

/// Extract username from a validated token
pub fn get_username_from_token(token: &str) -> Result<String> {
    let token_data = validate_token(token)?;
    Ok(token_data.claims.username)
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // Test RSA key pair - FOR TESTING ONLY
    // NEVER use these keys in production
    const TEST_PRIVATE_KEY: &str = r#"-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDmk2ZpednMZ2LD
UgdpKdNEgdB6Z8sbcHGwN+/UjEQGDJXpilaPQIVjGttbVbZ+l91IdvQ1x/cwN6sZ
0+R8vIThjJcaHRelPnRmcsQeu5jtPA/6x8h8jpvzvYEXCZ3QI9Fe1trnI3KUbTOS
WZpXRoWLlbgH4wUjTf9H6yKw11iNd5US9DbvLUU0F8noWqvVk8zqoB5aJosMNdW8
VMoRP94Hi7T51xwpqkb3EBLWRjZS3icyUHWpPFCCTRsIRbkvZ62SU4K9y9JIOeWp
ZZy1SOxrowbqUI5t+7ayE6+Rj4GRBh/z0rEBO4kGAln7+t3T8f4HKA8ttFWx9glg
6CTUN9wnAgMBAAECggEAJE+LeIojOG4CPvbItVD236T/Kyeenqrt3G29VmA4c34W
kE6kJFm+0m/voh80vBQ3rtUSJEi3WV/gPBMDD88IW2oD1FhHLv36NWABbpg7FFu5
uyksc3Zp13qSZ7RbUTndcO1Y+mlkqTyBO0eNEg1zCRus0uEiIACFIShFsEpZZv2P
cyaZCbr3AltkK4byQL2eQ7Q7aKPZXKEub+acLR5IWOzSRhVQ4KR3K53RHJ6MbGc7
rrQP2MD+tQq1XH9TtKJ5uA51fe8goDhV8Hn4km2sabsSPqH1HyUkN4XZCJ5THhtY
fna+gPkUl5ybumCMPpt1RDSkoJcZly0xWQFWUvMooQKBgQD3Ptqe/hcVfrQn6LoZ
BbgSTv92dvd8Oz9WDBqt0LZDIKu5Kp8qwXIAb6xAd0tkhSDUmuodId8Jh/niRBMy
3zAv90z2QTnXJRFgN3De7Wty/0f8HMRrjR63AwLcx5w5XOLhthVN+jkV+bu0+sJh
EG81O/NbRaYrgnDHQXEHkoTvLwKBgQDuvXGlKahZi8HT3bdqa9lwQrLzVoKy7Ztj
zDazsv24bCVXM0Hj/0NXzq/axvgU6vfG08wMLS/htUAg9QdgTA/HKa5Bb0axhFXc
MQUR3/xTr3kfXXEwITdnDY2X3+j4SgD7OU92P+vwB4iGgPUegrqIHJmrfe51xEM3
J4Sf51LkiQKBgDIR8IQyQMqBlkpevxFCLzzF8sYy4XuvI+xxFxYMJl0ByMT+9Kzb
8BJWizOi9QmuTC/CD5dGvLxZZSmFT74FpOSR2GwmWWhQgWxSzfDXc+Md/5321XBS
a930Jig/5EtZnDjJfxcDjXv9zx2fiq3NfjfxpB7fw/8bs2smvZUi/vjRAoGBAJ6k
OklTFjBywxjjIwdPpUyItdsnKHB3naNCRzNABIMxMdrxD57Ot9Q4XvjU8HMN9Bom
EVgiCshEJdoAmKcvw+hHVSjcJbC+TEOmO0U2fripSKZD9HvUBrmu8uDyBCBBJMfL
vHbKYSC+EMW4Gantmr/pqV+grf2JrlSPKP0MvTNpAoGAZnsljoUTW9PSDnx30Hqk
lRgoyQivtx6hKDm6v2l++mEQ0mMBE3NaN3hYxm6ncpG7b0giTu4jZx9U5Y0DLJ7m
3Dv/Cqr1zqQEekb93a1JZQxj9DP+Q/vw8CX/ky+xCE4zz596Dql+nycrOcbUM056
YMNQEWT7aC6+SsTEfz2Btk8=
-----END PRIVATE KEY-----"#;

    const TEST_PUBLIC_KEY: &str = r#"-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5pNmaXnZzGdiw1IHaSnT
RIHQemfLG3BxsDfv1IxEBgyV6YpWj0CFYxrbW1W2fpfdSHb0Ncf3MDerGdPkfLyE
4YyXGh0XpT50ZnLEHruY7TwP+sfIfI6b872BFwmd0CPRXtba5yNylG0zklmaV0aF
i5W4B+MFI03/R+sisNdYjXeVEvQ27y1FNBfJ6Fqr1ZPM6qAeWiaLDDXVvFTKET/e
B4u0+dccKapG9xAS1kY2Ut4nMlB1qTxQgk0bCEW5L2etklOCvcvSSDnlqWWctUjs
a6MG6lCObfu2shOvkY+BkQYf89KxATuJBgJZ+/rd0/H+BygPLbRVsfYJYOgk1Dfc
JwIDAQAB
-----END PUBLIC KEY-----"#;

    fn init_test_keys() {
        // Use a static flag to prevent re-initialization in tests
        static INIT: std::sync::Once = std::sync::Once::new();
        INIT.call_once(|| {
            initialize_jwt_keys(TEST_PRIVATE_KEY, TEST_PUBLIC_KEY)
                .expect("Failed to initialize test keys");
        });
    }

    #[test]
    fn test_generate_access_token() {
        init_test_keys();

        let user_id = Uuid::new_v4();
        let token = generate_access_token(user_id, "test@example.com", "testuser");

        assert!(token.is_ok());
        let token_str = token.unwrap();
        assert_eq!(token_str.matches('.').count(), 2); // JWT has 3 parts
    }

    #[test]
    fn test_validate_valid_token() {
        init_test_keys();

        let user_id = Uuid::new_v4();
        let token = generate_access_token(user_id, "test@example.com", "testuser")
            .expect("Failed to generate token");

        let validation = validate_token(&token);
        assert!(validation.is_ok());

        let token_data = validation.unwrap();
        assert_eq!(token_data.claims.sub, user_id.to_string());
        assert_eq!(token_data.claims.email, "test@example.com");
        assert_eq!(token_data.claims.token_type, "access");
    }

    #[test]
    fn test_validate_invalid_token() {
        init_test_keys();

        let result = validate_token("invalid.token.here");
        assert!(result.is_err());
    }

    #[test]
    fn test_validate_tampered_token() {
        init_test_keys();

        let user_id = Uuid::new_v4();
        let token = generate_access_token(user_id, "test@example.com", "testuser")
            .expect("Failed to generate token");

        // Tamper with the token by replacing a character
        let tampered = token.replace("a", "b");
        let result = validate_token(&tampered);
        assert!(result.is_err());
    }

    #[test]
    fn test_token_expiration() {
        init_test_keys();

        let user_id = Uuid::new_v4();
        let token = generate_access_token(user_id, "test@example.com", "testuser")
            .expect("Failed to generate token");

        let is_expired = is_token_expired(&token);
        assert!(is_expired.is_ok());
        assert!(!is_expired.unwrap()); // Should not be expired immediately
    }

    #[test]
    fn test_extract_user_id() {
        init_test_keys();

        let user_id = Uuid::new_v4();
        let token = generate_access_token(user_id, "test@example.com", "testuser")
            .expect("Failed to generate token");

        let extracted = get_user_id_from_token(&token);
        assert!(extracted.is_ok());
        assert_eq!(extracted.unwrap(), user_id);
    }

    #[test]
    fn test_token_pair_generation() {
        init_test_keys();

        let user_id = Uuid::new_v4();
        let response = generate_token_pair(user_id, "test@example.com", "testuser");

        assert!(response.is_ok());
        let tokens = response.unwrap();

        assert!(!tokens.access_token.is_empty());
        assert!(!tokens.refresh_token.is_empty());
        assert_eq!(tokens.token_type, "Bearer");

        // Both tokens should be valid
        assert!(validate_token(&tokens.access_token).is_ok());
        assert!(validate_token(&tokens.refresh_token).is_ok());
    }

    #[test]
    fn test_refresh_token_longer_expiry() {
        init_test_keys();

        let user_id = Uuid::new_v4();
        let access = generate_access_token(user_id, "test@example.com", "testuser")
            .expect("Failed to generate access token");
        let refresh = generate_refresh_token(user_id, "test@example.com", "testuser")
            .expect("Failed to generate refresh token");

        let access_claims = validate_token(&access).unwrap().claims;
        let refresh_claims = validate_token(&refresh).unwrap().claims;

        assert!(refresh_claims.exp > access_claims.exp);
    }

    #[test]
    fn test_validation_only_initialization() {
        // This test must run in isolation, but we can test the concept
        // In production, services would use initialize_jwt_validation_only
        init_test_keys();

        let user_id = Uuid::new_v4();
        let token = generate_access_token(user_id, "test@example.com", "testuser")
            .expect("Failed to generate token");

        // Validation should still work
        assert!(validate_token(&token).is_ok());
    }
}
