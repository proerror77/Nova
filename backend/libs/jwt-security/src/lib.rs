//! JWT Security Library with Secret Rotation and Validation
//!
//! **Security Features**:
//! - RSA key pair rotation with versioning
//! - Secret strength validation (minimum 32 bytes entropy)
//! - JWT ID (jti) for replay attack prevention
//! - Token blacklist using Redis
//! - Refresh token rotation
//!
//! **CVSS 9.8 Mitigation**: Replaces hardcoded secrets with environment-based RSA keys

use anyhow::{anyhow, Context, Result};
use chrono::{Duration, Utc};
use jsonwebtoken::{
    decode, encode, Algorithm, DecodingKey, EncodingKey, Header, TokenData, Validation,
};
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info, warn};
use uuid::Uuid;
use zeroize::Zeroize;

pub mod secret_validation;
pub mod token_blacklist;

pub use secret_validation::{validate_secret_strength, SecretStrength};
pub use token_blacklist::TokenBlacklist;

const DEFAULT_VALIDATION_LEEWAY: u64 = 30; // 30 seconds clock skew tolerance
const MAX_IAT_FUTURE_SKEW_SECS: i64 = 300; // 5 minutes max future iat
const ACCESS_TOKEN_EXPIRY_HOURS: i64 = 1;
const REFRESH_TOKEN_EXPIRY_DAYS: i64 = 30;

/// JWT Claims structure with security enhancements
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    /// Subject (user ID)
    pub sub: String,
    /// Issued at (Unix timestamp)
    pub iat: i64,
    /// Expiration time (Unix timestamp)
    pub exp: i64,
    /// Not before timestamp
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nbf: Option<i64>,
    /// Token type: "access" or "refresh"
    pub token_type: String,
    /// Email address
    pub email: String,
    /// Username
    pub username: String,
    /// JWT ID (unique token identifier) - **REQUIRED for replay protection**
    pub jti: String,
    /// Key version for rotation support
    #[serde(default)]
    pub key_version: u32,
}

/// JWT key pair with versioning
#[derive(Clone)]
struct KeyPair {
    encoding: EncodingKey,
    decoding: DecodingKey,
    version: u32,
}

impl Drop for KeyPair {
    fn drop(&mut self) {
        // Note: jsonwebtoken doesn't expose secret zeroing
        // This is a placeholder for future improvements
        info!(version = self.version, "Dropping JWT key pair");
    }
}

/// JWT Security Manager with key rotation support
pub struct JwtSecurityManager {
    /// Current active key pair
    current_key: Arc<RwLock<KeyPair>>,
    /// Previous key pairs for validation (supports rotation)
    old_keys: Arc<RwLock<Vec<KeyPair>>>,
    /// Token blacklist for revocation
    blacklist: Arc<TokenBlacklist>,
}

impl JwtSecurityManager {
    /// Initialize JWT manager with RSA key pair from environment
    ///
    /// **Environment Variables**:
    /// - `JWT_PRIVATE_KEY`: RSA private key in PEM format (REQUIRED)
    /// - `JWT_PUBLIC_KEY`: RSA public key in PEM format (REQUIRED)
    /// - `JWT_KEY_VERSION`: Current key version (default: 1)
    ///
    /// **Security**: Keys MUST be loaded from secure storage (Kubernetes Secrets, Vault)
    pub async fn from_env(redis_manager: ConnectionManager) -> Result<Self> {
        let private_key_pem = std::env::var("JWT_PRIVATE_KEY")
            .context("JWT_PRIVATE_KEY environment variable not set - CRITICAL SECURITY ISSUE")?;

        let public_key_pem = std::env::var("JWT_PUBLIC_KEY")
            .context("JWT_PUBLIC_KEY environment variable not set - CRITICAL SECURITY ISSUE")?;

        let key_version = std::env::var("JWT_KEY_VERSION")
            .ok()
            .and_then(|v| v.parse::<u32>().ok())
            .unwrap_or(1);

        Self::new(&private_key_pem, &public_key_pem, key_version, redis_manager).await
    }

    /// Create new JWT security manager with explicit keys
    pub async fn new(
        private_key_pem: &str,
        public_key_pem: &str,
        version: u32,
        redis_manager: ConnectionManager,
    ) -> Result<Self> {
        // Validate key strength (basic check)
        if private_key_pem.len() < 256 {
            return Err(anyhow!(
                "Private key too short - minimum 256 characters required"
            ));
        }

        let encoding_key = EncodingKey::from_rsa_pem(private_key_pem.as_bytes())
            .context("Failed to parse RSA private key - invalid PEM format")?;

        let decoding_key = DecodingKey::from_rsa_pem(public_key_pem.as_bytes())
            .context("Failed to parse RSA public key - invalid PEM format")?;

        let key_pair = KeyPair {
            encoding: encoding_key,
            decoding: decoding_key,
            version,
        };

        info!(
            key_version = version,
            "JWT security manager initialized with RS256"
        );

        Ok(Self {
            current_key: Arc::new(RwLock::new(key_pair)),
            old_keys: Arc::new(RwLock::new(Vec::new())),
            blacklist: Arc::new(TokenBlacklist::new(redis_manager)),
        })
    }

    /// Rotate to new key pair (for zero-downtime key rotation)
    pub async fn rotate_keys(
        &self,
        new_private_key: &str,
        new_public_key: &str,
        new_version: u32,
    ) -> Result<()> {
        let new_encoding = EncodingKey::from_rsa_pem(new_private_key.as_bytes())
            .context("Failed to parse new private key")?;

        let new_decoding = DecodingKey::from_rsa_pem(new_public_key.as_bytes())
            .context("Failed to parse new public key")?;

        let new_key = KeyPair {
            encoding: new_encoding,
            decoding: new_decoding,
            version: new_version,
        };

        // Move current key to old keys
        let mut current = self.current_key.write().await;
        let mut old = self.old_keys.write().await;

        let old_key = current.clone();
        old.push(old_key);

        // Keep only last 3 key versions
        if old.len() > 3 {
            old.remove(0);
        }

        *current = new_key;

        info!(
            old_version = current.version,
            new_version = new_version,
            "JWT key rotation completed"
        );

        Ok(())
    }

    /// Generate access token (1 hour expiry)
    pub async fn generate_access_token(
        &self,
        user_id: Uuid,
        email: &str,
        username: &str,
    ) -> Result<String> {
        self.generate_token(user_id, email, username, "access", ACCESS_TOKEN_EXPIRY_HOURS)
            .await
    }

    /// Generate refresh token (30 day expiry)
    pub async fn generate_refresh_token(
        &self,
        user_id: Uuid,
        email: &str,
        username: &str,
    ) -> Result<String> {
        self.generate_token(
            user_id,
            email,
            username,
            "refresh",
            REFRESH_TOKEN_EXPIRY_DAYS * 24,
        )
        .await
    }

    /// Internal token generation
    async fn generate_token(
        &self,
        user_id: Uuid,
        email: &str,
        username: &str,
        token_type: &str,
        expiry_hours: i64,
    ) -> Result<String> {
        let now = Utc::now();
        let key = self.current_key.read().await;

        let claims = Claims {
            sub: user_id.to_string(),
            iat: now.timestamp(),
            exp: (now + Duration::hours(expiry_hours)).timestamp(),
            nbf: Some(now.timestamp()),
            token_type: token_type.to_string(),
            email: email.to_string(),
            username: username.to_string(),
            jti: Uuid::new_v4().to_string(), // ✅ Unique ID for replay prevention
            key_version: key.version,
        };

        encode(&Header::new(Algorithm::RS256), &claims, &key.encoding)
            .context("Failed to encode JWT token")
    }

    /// Validate and decode token with comprehensive security checks
    pub async fn validate_token(&self, token: &str) -> Result<TokenData<Claims>> {
        // 1. Check if token is blacklisted
        if self.blacklist.is_blacklisted(token).await? {
            return Err(anyhow!("Token has been revoked"));
        }

        // 2. Try current key first (hot path)
        let current_key = self.current_key.read().await;
        let mut validation = Validation::new(Algorithm::RS256);
        validation.validate_exp = true;
        validation.validate_nbf = true;
        validation.leeway = DEFAULT_VALIDATION_LEEWAY;

        match decode::<Claims>(token, &current_key.decoding, &validation) {
            Ok(token_data) => {
                self.validate_claims(&token_data.claims)?;
                return Ok(token_data);
            }
            Err(e) => {
                // Try old keys (during rotation period)
                let old_keys = self.old_keys.read().await;
                for old_key in old_keys.iter() {
                    if let Ok(token_data) = decode::<Claims>(token, &old_key.decoding, &validation)
                    {
                        self.validate_claims(&token_data.claims)?;
                        warn!(
                            old_version = old_key.version,
                            "Token validated with old key - consider key rotation"
                        );
                        return Ok(token_data);
                    }
                }

                // All keys failed
                return Err(anyhow!("Token validation failed: {}", e));
            }
        }
    }

    /// Validate claims for security issues
    fn validate_claims(&self, claims: &Claims) -> Result<()> {
        // 1. JTI must exist and be non-empty
        if claims.jti.trim().is_empty() {
            return Err(anyhow!("Missing jti claim - replay attack risk"));
        }

        // 2. IAT must not be in future (beyond clock skew)
        let now = Utc::now().timestamp();
        if claims.iat > now + MAX_IAT_FUTURE_SKEW_SECS {
            return Err(anyhow!(
                "Token issued in future - possible clock skew or tampering"
            ));
        }

        // 3. Token type must be valid
        if claims.token_type != "access" && claims.token_type != "refresh" {
            return Err(anyhow!("Invalid token type: {}", claims.token_type));
        }

        Ok(())
    }

    /// Revoke token (add to blacklist)
    pub async fn revoke_token(&self, token: &str) -> Result<()> {
        let token_data = self.validate_token(token).await?;
        let ttl = (token_data.claims.exp - Utc::now().timestamp()) as usize;

        self.blacklist
            .add_to_blacklist(token, &token_data.claims.jti, ttl)
            .await?;

        info!(jti = %token_data.claims.jti, "Token revoked successfully");
        Ok(())
    }

    /// Get user ID from token
    pub async fn get_user_id(&self, token: &str) -> Result<Uuid> {
        let token_data = self.validate_token(token).await?;
        Uuid::parse_str(&token_data.claims.sub)
            .context("Invalid user ID in token - malformed UUID")
    }

    /// Refresh access token using refresh token (with rotation)
    pub async fn refresh_access_token(&self, refresh_token: &str) -> Result<(String, String)> {
        // 1. Validate refresh token
        let token_data = self.validate_token(refresh_token).await?;

        if token_data.claims.token_type != "refresh" {
            return Err(anyhow!("Invalid token type - expected refresh token"));
        }

        let user_id = Uuid::parse_str(&token_data.claims.sub)?;

        // 2. Revoke old refresh token (rotation)
        self.revoke_token(refresh_token).await?;

        // 3. Generate new tokens
        let new_access = self
            .generate_access_token(
                user_id,
                &token_data.claims.email,
                &token_data.claims.username,
            )
            .await?;

        let new_refresh = self
            .generate_refresh_token(
                user_id,
                &token_data.claims.email,
                &token_data.claims.username,
            )
            .await?;

        info!(
            user_id = %user_id,
            "Refresh token rotated successfully"
        );

        Ok((new_access, new_refresh))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use redis::Client;

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

    async fn setup_test_manager() -> JwtSecurityManager {
        let client = Client::open("redis://127.0.0.1:6379").unwrap();
        let manager = ConnectionManager::new(client).await.unwrap();
        JwtSecurityManager::new(TEST_PRIVATE_KEY, TEST_PUBLIC_KEY, 1, manager)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn test_generate_and_validate_token() {
        let manager = setup_test_manager().await;
        let user_id = Uuid::new_v4();

        let token = manager
            .generate_access_token(user_id, "test@example.com", "testuser")
            .await
            .unwrap();

        let validated = manager.validate_token(&token).await.unwrap();
        assert_eq!(validated.claims.sub, user_id.to_string());
        assert_eq!(validated.claims.email, "test@example.com");
        assert!(!validated.claims.jti.is_empty());
    }

    #[tokio::test]
    async fn test_token_revocation() {
        let manager = setup_test_manager().await;
        let user_id = Uuid::new_v4();

        let token = manager
            .generate_access_token(user_id, "test@example.com", "testuser")
            .await
            .unwrap();

        // Token should be valid
        assert!(manager.validate_token(&token).await.is_ok());

        // Revoke token
        manager.revoke_token(&token).await.unwrap();

        // Token should now be invalid
        assert!(manager.validate_token(&token).await.is_err());
    }

    #[tokio::test]
    async fn test_refresh_token_rotation() {
        let manager = setup_test_manager().await;
        let user_id = Uuid::new_v4();

        let refresh_token = manager
            .generate_refresh_token(user_id, "test@example.com", "testuser")
            .await
            .unwrap();

        // Refresh should return new tokens
        let (new_access, new_refresh) = manager
            .refresh_access_token(&refresh_token)
            .await
            .unwrap();

        assert!(!new_access.is_empty());
        assert!(!new_refresh.is_empty());
        assert_ne!(refresh_token, new_refresh);

        // Old refresh token should be revoked
        assert!(manager.validate_token(&refresh_token).await.is_err());
    }
}
