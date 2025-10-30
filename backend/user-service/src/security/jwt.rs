use anyhow::{anyhow, Result};
/// JWT token generation and validation using RS256 (RSA with SHA-256)
/// Access tokens: 1-hour expiry
/// Refresh tokens: 30-day expiry
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, TokenData, Validation};
use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

const ACCESS_TOKEN_EXPIRY_HOURS: i64 = 1;
const REFRESH_TOKEN_EXPIRY_DAYS: i64 = 30;

/// JWT Claims structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    /// Subject (user ID)
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

/// Access token response
#[derive(Debug, Serialize, Deserialize)]
pub struct TokenResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: i64,
}

use std::sync::RwLock;

// Thread-safe mutable storage for JWT keys loaded from environment
lazy_static! {
    static ref JWT_KEYS: RwLock<Option<(EncodingKey, DecodingKey)>> = RwLock::new(None);
}

/// Initialize JWT keys from PEM-formatted strings
/// Must be called during application startup before any JWT operations
pub fn initialize_keys(private_key_pem: &str, public_key_pem: &str) -> Result<()> {
    let encoding_key = EncodingKey::from_rsa_pem(private_key_pem.as_bytes())
        .map_err(|e| anyhow!("Failed to load private key from environment: {}", e))?;

    let decoding_key = DecodingKey::from_rsa_pem(public_key_pem.as_bytes())
        .map_err(|e| anyhow!("Failed to load public key from environment: {}", e))?;

    let mut keys = JWT_KEYS
        .write()
        .map_err(|e| anyhow!("Failed to acquire write lock on JWT keys: {}", e))?;
    *keys = Some((encoding_key, decoding_key));

    Ok(())
}

/// Get the encoding key for token generation
fn get_encoding_key() -> Result<EncodingKey> {
    let keys = JWT_KEYS
        .read()
        .map_err(|e| anyhow!("Failed to acquire read lock on JWT keys: {}", e))?;

    keys.as_ref()
        .map(|(enc, _)| enc.clone())
        .ok_or_else(|| anyhow!("JWT keys not initialized. Call initialize_keys() during startup"))
}

/// Get the decoding key for token validation
fn get_decoding_key() -> Result<DecodingKey> {
    let keys = JWT_KEYS
        .read()
        .map_err(|e| anyhow!("Failed to acquire read lock on JWT keys: {}", e))?;

    keys.as_ref()
        .map(|(_, dec)| dec.clone())
        .ok_or_else(|| anyhow!("JWT keys not initialized. Call initialize_keys() during startup"))
}

/// Generate a new access token
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
    encode(
        &Header::new(jsonwebtoken::Algorithm::RS256),
        &claims,
        &encoding_key,
    )
    .map_err(|e| anyhow!("Failed to generate access token: {}", e))
}

/// Generate a new refresh token
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
    encode(
        &Header::new(jsonwebtoken::Algorithm::RS256),
        &claims,
        &encoding_key,
    )
    .map_err(|e| anyhow!("Failed to generate refresh token: {}", e))
}

/// Generate both access and refresh tokens
pub fn generate_token_pair(user_id: Uuid, email: &str, username: &str) -> Result<TokenResponse> {
    let access_token = generate_access_token(user_id, email, username)?;
    let refresh_token = generate_refresh_token(user_id, email, username)?;

    Ok(TokenResponse {
        access_token,
        refresh_token,
        token_type: "Bearer".to_string(),
        expires_in: ACCESS_TOKEN_EXPIRY_HOURS * 3600, // Convert to seconds
    })
}

/// Validate and decode a token
pub fn validate_token(token: &str) -> Result<TokenData<Claims>> {
    let decoding_key = get_decoding_key()?;
    decode::<Claims>(
        token,
        &decoding_key,
        &Validation::new(jsonwebtoken::Algorithm::RS256),
    )
    .map_err(|e| anyhow!("Token validation failed: {}", e))
}

/// Check if a token is expired
pub fn is_token_expired(token: &str) -> Result<bool> {
    let token_data = validate_token(token)?;
    let now = Utc::now().timestamp();
    Ok(token_data.claims.exp < now)
}

/// Extract user ID from token
pub fn get_user_id_from_token(token: &str) -> Result<Uuid> {
    let token_data = validate_token(token)?;
    Uuid::parse_str(&token_data.claims.sub).map_err(|e| anyhow!("Invalid user ID in token: {}", e))
}

/// Extract email from token
pub fn get_email_from_token(token: &str) -> Result<String> {
    let token_data = validate_token(token)?;
    Ok(token_data.claims.email)
}

/// JWKS (JSON Web Key Set) structure for OAuth 2.0 authorization server metadata
#[derive(Debug, Serialize)]
pub struct JWKSKey {
    pub kty: String,  // Key type: "RSA"
    pub alg: String,  // Algorithm: "RS256"
    pub kid: String,  // Key ID
    pub use_: String, // Use: "sig" (signing)
    pub n: String,    // RSA modulus (base64)
    pub e: String,    // RSA public exponent (base64)
}

#[derive(Debug, Serialize)]
pub struct JWKS {
    pub keys: Vec<JWKSKey>,
}

/// Get JWKS for JWT key distribution (for verification by external services)
///
/// # Arguments
/// * `pool` - Database connection pool (deprecated, not used)
/// * `_grace_period_days` - Days to keep old keys active after rotation (deprecated)
///
/// # Returns
/// Error - JWKS endpoint moved to auth-service
#[deprecated(since = "0.2.0", note = "JWKS endpoint moved to auth-service (port 8084)")]
pub async fn get_jwks(_pool: &sqlx::PgPool, _grace_period_days: i64) -> Result<JWKS> {
    // DEPRECATED: This function has been moved to auth-service
    // Call auth-service's /.well-known/jwks.json endpoint instead
    Err(anyhow!(
        "JWKS endpoint has been moved to auth-service. Use auth-service's /.well-known/jwks.json endpoint"
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Test RSA key pair - DO NOT USE IN PRODUCTION
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

    // Initialize JWT keys for testing
    fn init_test_keys() {
        let _ = initialize_keys(TEST_PRIVATE_KEY, TEST_PUBLIC_KEY);
    }

    #[test]
    fn test_generate_access_token() {
        init_test_keys();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let token = generate_access_token(user_id, email, username);
        assert!(token.is_ok());

        let token_str = token.unwrap();
        assert!(!token_str.is_empty());
        // JWT tokens have 3 parts separated by dots
        assert_eq!(token_str.matches('.').count(), 2);
    }

    #[test]
    fn test_generate_refresh_token() {
        init_test_keys();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let token = generate_refresh_token(user_id, email, username);
        assert!(token.is_ok());

        let token_str = token.unwrap();
        assert!(!token_str.is_empty());
    }

    #[test]
    fn test_generate_token_pair() {
        init_test_keys();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let response = generate_token_pair(user_id, email, username);
        assert!(response.is_ok());

        let tokens = response.unwrap();
        assert!(!tokens.access_token.is_empty());
        assert!(!tokens.refresh_token.is_empty());
        assert_eq!(tokens.token_type, "Bearer");
        assert_eq!(tokens.expires_in, 3600); // 1 hour in seconds
    }

    #[test]
    fn test_validate_valid_token() {
        init_test_keys();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let token =
            generate_access_token(user_id, email, username).expect("Failed to generate token");

        let validation = validate_token(&token);
        assert!(validation.is_ok());

        let token_data = validation.unwrap();
        assert_eq!(token_data.claims.sub, user_id.to_string());
        assert_eq!(token_data.claims.email, email);
        assert_eq!(token_data.claims.username, username);
        assert_eq!(token_data.claims.token_type, "access");
    }

    #[test]
    fn test_validate_invalid_token() {
        init_test_keys();
        let invalid_token = "not.a.valid.token";
        let result = validate_token(invalid_token);
        assert!(result.is_err());
    }

    #[test]
    fn test_validate_corrupted_token() {
        init_test_keys();
        let corrupted_token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.corrupted.signature";
        let result = validate_token(corrupted_token);
        assert!(result.is_err());
    }

    #[test]
    fn test_is_token_expired() {
        init_test_keys();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let token =
            generate_access_token(user_id, email, username).expect("Failed to generate token");

        let is_expired = is_token_expired(&token);
        assert!(is_expired.is_ok());
        assert!(!is_expired.unwrap()); // Token should not be expired immediately
    }

    #[test]
    fn test_get_user_id_from_token() {
        init_test_keys();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let token =
            generate_access_token(user_id, email, username).expect("Failed to generate token");

        let extracted_id = get_user_id_from_token(&token);
        assert!(extracted_id.is_ok());
        assert_eq!(extracted_id.unwrap(), user_id);
    }

    #[test]
    fn test_get_email_from_token() {
        init_test_keys();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let token =
            generate_access_token(user_id, email, username).expect("Failed to generate token");

        let extracted_email = get_email_from_token(&token);
        assert!(extracted_email.is_ok());
        assert_eq!(extracted_email.unwrap(), email);
    }

    #[test]
    fn test_access_token_has_correct_expiry() {
        init_test_keys();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let token =
            generate_access_token(user_id, email, username).expect("Failed to generate token");

        let token_data = validate_token(&token).expect("Failed to validate token");
        let now = Utc::now().timestamp();
        let expected_expiry = now + (ACCESS_TOKEN_EXPIRY_HOURS * 3600);

        // Allow 1 second tolerance for execution time
        assert!(token_data.claims.exp >= expected_expiry - 1);
        assert!(token_data.claims.exp <= expected_expiry + 1);
    }

    #[test]
    fn test_refresh_token_has_longer_expiry() {
        init_test_keys();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let access_token = generate_access_token(user_id, email, username)
            .expect("Failed to generate access token");
        let refresh_token = generate_refresh_token(user_id, email, username)
            .expect("Failed to generate refresh token");

        let access_claims = validate_token(&access_token)
            .expect("Failed to validate access token")
            .claims;
        let refresh_claims = validate_token(&refresh_token)
            .expect("Failed to validate refresh token")
            .claims;

        // Refresh token should expire later than access token
        assert!(refresh_claims.exp > access_claims.exp);
    }

    #[test]
    fn test_token_contains_all_required_claims() {
        init_test_keys();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let token =
            generate_access_token(user_id, email, username).expect("Failed to generate token");

        let token_data = validate_token(&token).expect("Failed to validate token");
        let claims = token_data.claims;

        // Verify all required claims are present
        assert!(!claims.sub.is_empty());
        assert!(claims.iat > 0);
        assert!(claims.exp > claims.iat);
        assert_eq!(claims.token_type, "access");
        assert_eq!(claims.email, email);
        assert_eq!(claims.username, username);
    }
}
