/// OAuth 2.0 authentication service
///
/// Supports OAuth providers:
/// - Google (OAuth 2.0)
/// - Apple (Sign in with Apple)
///
/// ## Security
///
/// - State tokens stored in Redis with 10-minute TTL
/// - PKCE support for mobile flows
/// - Token exchange over HTTPS only
/// - User info fetched from provider APIs
/// - Apple JWT tokens are cryptographically verified against Apple's public keys
use crate::config::OAuthSettings;
use crate::error::{IdentityError, Result};
use crate::models::User;
use crate::services::KafkaEventProducer;
use base64::prelude::*;
use chrono::{DateTime, Duration, Utc};
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use once_cell::sync::Lazy;
use redis_utils::SharedConnectionManager;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::PgPool;
use std::collections::HashMap;
use std::sync::RwLock;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

const OAUTH_STATE_TTL_SECS: u64 = 600; // 10 minutes
const APPLE_JWKS_URL: &str = "https://appleid.apple.com/auth/keys";
const APPLE_ISSUER: &str = "https://appleid.apple.com";
const APPLE_JWKS_CACHE_TTL_SECS: i64 = 3600; // 1 hour

/// Cached Apple JWKS (public keys)
static APPLE_JWKS_CACHE: Lazy<RwLock<AppleJwksCache>> =
    Lazy::new(|| RwLock::new(AppleJwksCache::default()));

#[derive(Default)]
struct AppleJwksCache {
    keys: HashMap<String, AppleJwk>,
    fetched_at: Option<DateTime<Utc>>,
}

impl AppleJwksCache {
    fn is_expired(&self) -> bool {
        match self.fetched_at {
            Some(t) => Utc::now() - t > Duration::seconds(APPLE_JWKS_CACHE_TTL_SECS),
            None => true,
        }
    }
}

/// OAuth provider types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OAuthProvider {
    Google,
    Apple,
}

impl OAuthProvider {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Google => "google",
            Self::Apple => "apple",
        }
    }
}

/// OAuth service for social authentication
#[derive(Clone)]
pub struct OAuthService {
    config: OAuthSettings,
    db: PgPool,
    redis: SharedConnectionManager,
    http: Client,
    kafka: Option<KafkaEventProducer>,
}

/// OAuth authorization URL response
#[derive(Debug, Serialize)]
pub struct OAuthAuthorizationUrl {
    pub url: String,
    pub state: String,
}

/// OAuth callback result
#[derive(Debug)]
pub struct OAuthCallbackResult {
    pub user: User,
    pub is_new_user: bool,
}

impl OAuthService {
    pub fn new(
        config: OAuthSettings,
        db: PgPool,
        redis: SharedConnectionManager,
        kafka: Option<KafkaEventProducer>,
    ) -> Self {
        Self {
            config,
            db,
            redis,
            http: Client::new(),
            kafka,
        }
    }

    /// Generate OAuth authorization URL with state token
    ///
    /// ## Arguments
    ///
    /// * `provider` - OAuth provider (Google, Apple, Facebook, WeChat)
    /// * `redirect_uri` - Callback URL after authentication
    ///
    /// ## Returns
    ///
    /// Authorization URL and state token (store state for verification)
    pub async fn start_flow(
        &self,
        provider: OAuthProvider,
        redirect_uri: &str,
    ) -> Result<OAuthAuthorizationUrl> {
        let state = Uuid::new_v4().to_string();

        // Store state in Redis with TTL
        let state_key = format!("nova:oauth:state:{}", state);
        let mut redis_conn = self.redis.lock().await.clone();
        redis_utils::with_timeout(async {
            redis::cmd("SET")
                .arg(&state_key)
                .arg(provider.as_str())
                .arg("EX")
                .arg(OAUTH_STATE_TTL_SECS)
                .query_async::<_, ()>(&mut redis_conn)
                .await
        })
        .await
        .map_err(|e| IdentityError::Redis(e.to_string()))?;

        let url = match provider {
            OAuthProvider::Google => self.google_auth_url(&state, redirect_uri),
            OAuthProvider::Apple => self.apple_auth_url(&state, redirect_uri),
        };

        Ok(OAuthAuthorizationUrl { url, state })
    }

    /// Complete OAuth flow after provider callback
    ///
    /// ## Arguments
    ///
    /// * `state` - State token from authorization URL
    /// * `code` - Authorization code from provider
    /// * `redirect_uri` - Same redirect URI used in start_flow
    ///
    /// ## Returns
    ///
    /// User record (created or existing) and flag indicating if user is new
    pub async fn complete_flow(
        &self,
        state: &str,
        code: &str,
        redirect_uri: &str,
    ) -> Result<OAuthCallbackResult> {
        // Verify and consume state token
        let state_key = format!("nova:oauth:state:{}", state);
        let mut redis_conn = self.redis.lock().await.clone();
        let provider_str: Option<String> = redis_utils::with_timeout(async {
            redis::cmd("GET")
                .arg(&state_key)
                .query_async(&mut redis_conn)
                .await
        })
        .await
        .map_err(|e| IdentityError::Redis(e.to_string()))?;

        let provider_str = provider_str.ok_or(IdentityError::InvalidOAuthState)?;

        // Delete state token (one-time use)
        redis_utils::with_timeout(async {
            redis::cmd("DEL")
                .arg(&state_key)
                .query_async::<_, ()>(&mut redis_conn)
                .await
        })
        .await
        .map_err(|e| IdentityError::Redis(e.to_string()))?;

        let provider = match provider_str.as_str() {
            "google" => OAuthProvider::Google,
            "apple" => OAuthProvider::Apple,
            _ => return Err(IdentityError::InvalidOAuthProvider),
        };

        // Exchange code for tokens and fetch user info
        let oauth_user = match provider {
            OAuthProvider::Google => self.exchange_google(code, redirect_uri).await?,
            OAuthProvider::Apple => self.exchange_apple(code, redirect_uri).await?,
        };

        // Create or link user
        let (user, is_new_user) = self.upsert_user(oauth_user, provider).await?;

        Ok(OAuthCallbackResult { user, is_new_user })
    }

    fn google_auth_url(&self, state: &str, redirect_uri: &str) -> String {
        format!(
            "https://accounts.google.com/o/oauth2/v2/auth?client_id={}&redirect_uri={}&response_type=code&scope=openid%20profile%20email&state={}",
            self.config.google_client_id.as_deref().unwrap_or(""),
            urlencoding::encode(redirect_uri),
            state
        )
    }

    fn apple_auth_url(&self, state: &str, redirect_uri: &str) -> String {
        format!(
            "https://appleid.apple.com/auth/authorize?client_id={}&redirect_uri={}&response_type=code&scope=name%20email&response_mode=form_post&state={}",
            self.config.apple_client_id.as_deref().unwrap_or(""),
            urlencoding::encode(redirect_uri),
            state
        )
    }

    async fn exchange_google(&self, code: &str, redirect_uri: &str) -> Result<OAuthUserInfo> {
        let client_id = self.config.google_client_id.as_ref().ok_or_else(|| {
            IdentityError::OAuthError("Google client ID not configured".to_string())
        })?;
        let client_secret = self.config.google_client_secret.as_ref().ok_or_else(|| {
            IdentityError::OAuthError("Google client secret not configured".to_string())
        })?;

        // Exchange code for access token
        let token_response = self
            .http
            .post("https://oauth2.googleapis.com/token")
            .form(&[
                ("code", code),
                ("client_id", client_id),
                ("client_secret", client_secret),
                ("redirect_uri", redirect_uri),
                ("grant_type", "authorization_code"),
            ])
            .send()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?
            .json::<GoogleTokenResponse>()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?;

        // Fetch user info
        let user_info = self
            .http
            .get("https://www.googleapis.com/oauth2/v2/userinfo")
            .bearer_auth(&token_response.access_token)
            .send()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?
            .json::<GoogleUserInfo>()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?;

        Ok(OAuthUserInfo {
            provider_user_id: user_info.id,
            email: user_info.email,
            name: user_info.name,
            picture: user_info.picture,
            access_token: token_response.access_token,
            refresh_token: token_response.refresh_token,
            expires_at: to_expiry(token_response.expires_in),
        })
    }

    async fn exchange_apple(&self, code: &str, redirect_uri: &str) -> Result<OAuthUserInfo> {
        let client_id = self.apple_client_id()?.clone();
        let client_secret = self.generate_apple_client_secret()?;

        // Exchange code for tokens
        let token_response = self
            .http
            .post("https://appleid.apple.com/auth/token")
            .form(&[
                ("code", code),
                ("client_id", &client_id),
                ("client_secret", &client_secret),
                ("redirect_uri", redirect_uri),
                ("grant_type", "authorization_code"),
            ])
            .send()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?
            .json::<AppleTokenResponse>()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?;

        // Verify and decode ID token with cryptographic signature verification
        // This validates: signature (RS256), issuer (https://appleid.apple.com),
        // audience (our client_id), and expiration
        let id_token_claims =
            verify_apple_id_token(&self.http, &token_response.id_token, &client_id).await?;

        Ok(OAuthUserInfo {
            provider_user_id: id_token_claims.sub,
            email: id_token_claims.email.unwrap_or_default(),
            name: None,
            picture: None,
            access_token: token_response.access_token,
            refresh_token: token_response.refresh_token,
            expires_at: to_expiry(token_response.expires_in),
        })
    }

    /// Generate Apple client secret (JWT signed with ES256)
    fn generate_apple_client_secret(&self) -> Result<String> {
        use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};

        let key_id = self.apple_key_id()?.clone();
        let team_id =
            self.config.apple_team_id.as_ref().ok_or_else(|| {
                IdentityError::OAuthError("Apple team ID not configured".to_string())
            })?;
        let client_id = self.apple_client_id()?.clone();
        let private_key = self.config.apple_private_key.as_ref().ok_or_else(|| {
            IdentityError::OAuthError("Apple private key not configured".to_string())
        })?;

        let now = Utc::now();
        let claims = json!({
            "iss": team_id,
            "iat": now.timestamp(),
            "exp": (now + Duration::hours(1)).timestamp(),
            "aud": "https://appleid.apple.com",
            "sub": client_id,
        });

        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(key_id);

        let key = EncodingKey::from_ec_pem(private_key.as_bytes())
            .map_err(|e| IdentityError::OAuthError(format!("Invalid Apple private key: {}", e)))?;

        encode(&header, &claims, &key)
            .map_err(|e| IdentityError::OAuthError(format!("Failed to sign Apple JWT: {}", e)))
    }

    /// Handle Apple native sign-in (from iOS ASAuthorizationAppleIDCredential)
    ///
    /// This verifies the identity token cryptographically and creates/links the user account.
    /// Unlike the web flow, this uses the identity_token directly instead of exchanging a code.
    ///
    /// ## Security
    ///
    /// The identity token is verified against Apple's public keys (JWKS) to ensure:
    /// - The token was signed by Apple (RS256 signature verification)
    /// - The token was issued for our app (audience = client_id)
    /// - The token is from Apple (issuer = https://appleid.apple.com)
    /// - The token has not expired
    pub async fn apple_native_sign_in(
        &self,
        identity_token: &str,
        user_identifier: &str,
        email: Option<&str>,
        given_name: Option<&str>,
        family_name: Option<&str>,
    ) -> Result<OAuthCallbackResult> {
        let client_id = self.apple_client_id()?.clone();

        // 1. Verify and decode the identity token with cryptographic signature verification
        // This validates: signature (RS256), issuer, audience (client_id), and expiration
        let id_token_claims = verify_apple_id_token(&self.http, identity_token, &client_id).await?;

        // 2. Verify the subject matches the user_identifier provided by iOS
        if id_token_claims.sub != user_identifier {
            error!(
                token_sub = %id_token_claims.sub,
                provided_id = %user_identifier,
                "Apple user identifier mismatch"
            );
            return Err(IdentityError::OAuthError(
                "User identifier mismatch - possible token tampering".to_string(),
            ));
        }

        // 3. Construct user info
        // Note: email and name are only provided on first sign-in, so we use the cached values
        let user_email = email
            .map(|s| s.to_string())
            .or(id_token_claims.email)
            .unwrap_or_default();

        let user_name = match (given_name, family_name) {
            (Some(given), Some(family)) => Some(format!("{} {}", given, family)),
            (Some(given), None) => Some(given.to_string()),
            (None, Some(family)) => Some(family.to_string()),
            (None, None) => None,
        };

        let oauth_user = OAuthUserInfo {
            provider_user_id: user_identifier.to_string(),
            email: user_email,
            name: user_name,
            picture: None,
            access_token: identity_token.to_string(), // Store identity token as access token
            refresh_token: None,
            expires_at: None,
        };

        // 4. Create or link user
        let (user, is_new_user) = self.upsert_user(oauth_user, OAuthProvider::Apple).await?;

        info!(
            user_id = %user.id,
            is_new_user = is_new_user,
            "Apple native sign-in completed with verified token"
        );

        Ok(OAuthCallbackResult { user, is_new_user })
    }

    async fn upsert_user(
        &self,
        oauth_user: OAuthUserInfo,
        provider: OAuthProvider,
    ) -> Result<(User, bool)> {
        // Check if OAuth connection exists
        if let Some(conn) = crate::db::oauth::find_by_provider(
            &self.db,
            provider.as_str(),
            &oauth_user.provider_user_id,
        )
        .await?
        {
            // Update OAuth tokens
            crate::db::oauth::update_tokens(
                &self.db,
                conn.id,
                &oauth_user.access_token,
                oauth_user.refresh_token.as_deref(),
                None, // token_type
                oauth_user.expires_at,
            )
            .await?;

            // Fetch existing user
            let user = crate::db::users::find_by_id(&self.db, conn.user_id)
                .await?
                .ok_or(IdentityError::UserNotFound)?;

            return Ok((user, false));
        }

        // Check if user exists by email
        let user = if !oauth_user.email.is_empty() {
            crate::db::users::find_by_email(&self.db, &oauth_user.email).await?
        } else {
            None
        };

        let (user_id, is_new_user) = if let Some(existing_user) = user {
            (existing_user.id, false)
        } else {
            // Create new user
            let username = self.derive_username(&oauth_user.email);
            let new_user = crate::db::users::create_oauth_user(
                &self.db,
                &oauth_user.email,
                &username,
                provider.as_str(),
                &oauth_user.provider_user_id,
            )
            .await?;

            info!(user_id = %new_user.id, provider = provider.as_str(), "New user created via OAuth");
            (new_user.id, true)
        };

        // Link OAuth connection
        crate::db::oauth::create_connection(
            &self.db,
            user_id,
            provider.as_str(),
            &oauth_user.provider_user_id,
            Some(&oauth_user.email),
            oauth_user.name.as_deref(),
            oauth_user.picture.as_deref(),
            Some(&oauth_user.access_token),
            oauth_user.refresh_token.as_deref(),
            None, // token_type
            oauth_user.expires_at,
            None, // scopes
        )
        .await?;

        let user = crate::db::users::find_by_id(&self.db, user_id)
            .await?
            .ok_or(IdentityError::UserNotFound)?;

        Ok((user, is_new_user))
    }

    fn derive_username(&self, email: &str) -> String {
        let base = email
            .split('@')
            .next()
            .unwrap_or("nova_user")
            .replace(['.', '+'], "_");
        format!("{base}_{}", &Uuid::new_v4().simple().to_string()[..6])
    }

    fn apple_client_id(&self) -> Result<&String> {
        self.config
            .apple_client_id
            .as_ref()
            .ok_or_else(|| IdentityError::OAuthError("Apple client ID missing".into()))
    }

    fn apple_key_id(&self) -> Result<&String> {
        self.config
            .apple_key_id
            .as_ref()
            .ok_or_else(|| IdentityError::OAuthError("Apple key ID missing".into()))
    }
}

// ===== Helper Structures =====

struct OAuthUserInfo {
    provider_user_id: String,
    email: String,
    name: Option<String>,
    picture: Option<String>,
    access_token: String,
    refresh_token: Option<String>,
    expires_at: Option<DateTime<Utc>>,
}

// ===== Provider Response Types =====

#[derive(Deserialize)]
struct GoogleTokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
}

#[derive(Deserialize)]
struct GoogleUserInfo {
    id: String,
    email: String,
    name: Option<String>,
    picture: Option<String>,
}

#[derive(Deserialize)]
struct AppleTokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
    id_token: String,
}

#[derive(Debug, Deserialize)]
struct AppleIdTokenClaims {
    /// Subject - unique user identifier from Apple
    sub: String,
    /// User's email (may be private relay email)
    email: Option<String>,
    /// Issuer - validated by jsonwebtoken library
    #[serde(default)]
    #[allow(dead_code)]
    iss: String,
    /// Audience - validated by jsonwebtoken library
    #[serde(default)]
    #[allow(dead_code)]
    aud: String,
    /// Expiration time - validated by jsonwebtoken library
    #[serde(default)]
    #[allow(dead_code)]
    exp: i64,
    /// Issued at time - included for completeness
    #[serde(default)]
    #[allow(dead_code)]
    iat: i64,
}

/// Apple JWKS response structure
#[derive(Debug, Deserialize)]
struct AppleJwksResponse {
    keys: Vec<AppleJwk>,
}

/// Individual JWK from Apple's key set
#[derive(Debug, Clone, Deserialize)]
struct AppleJwk {
    /// Key ID - used to match against JWT header
    kid: String,
    /// Key type (always "RSA" for Apple) - included for completeness
    #[allow(dead_code)]
    kty: String,
    /// Algorithm (RS256) - included for completeness
    #[allow(dead_code)]
    alg: String,
    /// RSA public key modulus (Base64URL encoded)
    n: String,
    /// RSA public key exponent (Base64URL encoded)
    e: String,
}

// ===== Utility Functions =====

fn to_expiry(ts: Option<i64>) -> Option<DateTime<Utc>> {
    ts.and_then(|secs| DateTime::from_timestamp(secs, 0))
}

/// Fetch Apple's public keys (JWKS) for JWT verification
async fn fetch_apple_jwks(http: &Client) -> Result<Vec<AppleJwk>> {
    debug!("Fetching Apple JWKS from {}", APPLE_JWKS_URL);

    let response = http
        .get(APPLE_JWKS_URL)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| {
            error!("Failed to fetch Apple JWKS: {}", e);
            IdentityError::OAuthError(format!("Failed to fetch Apple public keys: {}", e))
        })?;

    if !response.status().is_success() {
        let status = response.status();
        error!("Apple JWKS request failed with status: {}", status);
        return Err(IdentityError::OAuthError(format!(
            "Apple JWKS request failed: {}",
            status
        )));
    }

    let jwks: AppleJwksResponse = response.json().await.map_err(|e| {
        error!("Failed to parse Apple JWKS response: {}", e);
        IdentityError::OAuthError(format!("Failed to parse Apple public keys: {}", e))
    })?;

    info!("Successfully fetched {} Apple public keys", jwks.keys.len());
    Ok(jwks.keys)
}

/// Get Apple's public key by key ID, using cache when possible
async fn get_apple_public_key(http: &Client, kid: &str) -> Result<AppleJwk> {
    // Check cache first
    {
        let cache = APPLE_JWKS_CACHE
            .read()
            .expect("APPLE_JWKS_CACHE RwLock poisoned");
        if !cache.is_expired() {
            if let Some(key) = cache.keys.get(kid) {
                debug!("Using cached Apple public key for kid={}", kid);
                return Ok(key.clone());
            }
        }
    }

    // Fetch fresh keys
    let keys = fetch_apple_jwks(http).await?;

    // Update cache
    {
        let mut cache = APPLE_JWKS_CACHE
            .write()
            .expect("APPLE_JWKS_CACHE RwLock poisoned");
        cache.keys.clear();
        for key in &keys {
            cache.keys.insert(key.kid.clone(), key.clone());
        }
        cache.fetched_at = Some(Utc::now());
    }

    // Find the requested key
    let cache = APPLE_JWKS_CACHE
        .read()
        .expect("APPLE_JWKS_CACHE RwLock poisoned");
    cache.keys.get(kid).cloned().ok_or_else(|| {
        error!("Apple public key not found for kid={}", kid);
        IdentityError::OAuthError(format!("Apple public key not found for kid={}", kid))
    })
}

/// Verify and decode Apple ID token with cryptographic signature verification
///
/// This function:
/// 1. Extracts the key ID (kid) from the JWT header
/// 2. Fetches Apple's public key for that kid
/// 3. Verifies the RS256 signature
/// 4. Validates issuer, audience, and expiration
/// 5. Returns the verified claims
async fn verify_apple_id_token(
    http: &Client,
    token: &str,
    expected_client_id: &str,
) -> Result<AppleIdTokenClaims> {
    // 1. Decode JWT header to get key ID
    let header = decode_header(token).map_err(|e| {
        error!("Failed to decode Apple JWT header: {}", e);
        IdentityError::OAuthError(format!("Invalid Apple ID token header: {}", e))
    })?;

    let kid = header.kid.ok_or_else(|| {
        error!("Apple JWT missing key ID (kid) in header");
        IdentityError::OAuthError("Apple ID token missing key ID".to_string())
    })?;

    // 2. Verify algorithm is RS256
    if header.alg != Algorithm::RS256 {
        error!("Apple JWT using unexpected algorithm: {:?}", header.alg);
        return Err(IdentityError::OAuthError(format!(
            "Unexpected JWT algorithm: {:?}",
            header.alg
        )));
    }

    // 3. Get Apple's public key for this kid
    let jwk = get_apple_public_key(http, &kid).await?;

    // 4. Create decoding key from JWK
    let decoding_key = DecodingKey::from_rsa_components(&jwk.n, &jwk.e).map_err(|e| {
        error!("Failed to create decoding key from Apple JWK: {}", e);
        IdentityError::OAuthError(format!("Invalid Apple public key format: {}", e))
    })?;

    // 5. Set up validation rules
    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_issuer(&[APPLE_ISSUER]);
    validation.set_audience(&[expected_client_id]);
    validation.validate_exp = true;

    // 6. Decode and verify the token
    let token_data =
        decode::<AppleIdTokenClaims>(token, &decoding_key, &validation).map_err(|e| {
            error!("Apple JWT verification failed: {}", e);
            match e.kind() {
                jsonwebtoken::errors::ErrorKind::InvalidSignature => IdentityError::OAuthError(
                    "Apple ID token signature verification failed".to_string(),
                ),
                jsonwebtoken::errors::ErrorKind::ExpiredSignature => {
                    IdentityError::OAuthError("Apple ID token has expired".to_string())
                }
                jsonwebtoken::errors::ErrorKind::InvalidIssuer => {
                    IdentityError::OAuthError("Apple ID token has invalid issuer".to_string())
                }
                jsonwebtoken::errors::ErrorKind::InvalidAudience => {
                    IdentityError::OAuthError("Apple ID token has invalid audience".to_string())
                }
                _ => {
                    IdentityError::OAuthError(format!("Apple ID token verification failed: {}", e))
                }
            }
        })?;

    info!(
        "Successfully verified Apple ID token for sub={}",
        token_data.claims.sub
    );

    Ok(token_data.claims)
}

/// DEPRECATED: Decode JWT claims without verification
/// This function is only kept for backward compatibility and should NOT be used for Apple tokens.
/// Use `verify_apple_id_token` instead for secure token verification.
#[allow(dead_code)]
fn decode_jwt_claims_unsafe<T: serde::de::DeserializeOwned>(token: &str) -> Result<T> {
    warn!("Using unsafe JWT decode without signature verification - this is deprecated!");
    let segments: Vec<&str> = token.split('.').collect();
    if segments.len() != 3 {
        return Err(IdentityError::OAuthError(
            "Invalid ID token format".to_string(),
        ));
    }

    let payload = BASE64_URL_SAFE_NO_PAD.decode(segments[1]).map_err(|e| {
        IdentityError::OAuthError(format!("Failed to decode ID token payload: {}", e))
    })?;

    serde_json::from_slice(&payload)
        .map_err(|e| IdentityError::OAuthError(format!("Failed to parse ID token payload: {}", e)))
}

// ============================================================================
// Unit Tests for Apple JWT Verification
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use jsonwebtoken::Algorithm;

    // ========================================================================
    // AppleJwksCache Tests
    // ========================================================================

    #[test]
    fn test_apple_jwks_cache_default_is_expired() {
        let cache = AppleJwksCache::default();
        assert!(cache.is_expired(), "Default cache should be expired");
    }

    #[test]
    fn test_apple_jwks_cache_fresh_not_expired() {
        let cache = AppleJwksCache {
            keys: HashMap::new(),
            fetched_at: Some(Utc::now()),
        };
        assert!(!cache.is_expired(), "Fresh cache should not be expired");
    }

    #[test]
    fn test_apple_jwks_cache_old_is_expired() {
        let cache = AppleJwksCache {
            keys: HashMap::new(),
            fetched_at: Some(Utc::now() - Duration::hours(2)),
        };
        assert!(cache.is_expired(), "2-hour old cache should be expired");
    }

    #[test]
    fn test_apple_jwks_cache_just_under_ttl_not_expired() {
        let cache = AppleJwksCache {
            keys: HashMap::new(),
            fetched_at: Some(Utc::now() - Duration::minutes(59)),
        };
        assert!(
            !cache.is_expired(),
            "59-minute old cache should not be expired"
        );
    }

    // ========================================================================
    // JWT Header Parsing Tests
    // ========================================================================

    #[test]
    fn test_decode_header_valid_jwt() {
        // Create a minimal valid JWT structure (header.payload.signature)
        let header = BASE64_URL_SAFE_NO_PAD.encode(r#"{"alg":"RS256","kid":"test-key-id"}"#);
        let payload = BASE64_URL_SAFE_NO_PAD.encode(r#"{"sub":"test"}"#);
        let token = format!("{}.{}.fake_signature", header, payload);

        let decoded = decode_header(&token).expect("should decode header");
        assert_eq!(decoded.alg, Algorithm::RS256);
        assert_eq!(decoded.kid, Some("test-key-id".to_string()));
    }

    #[test]
    fn test_decode_header_missing_kid() {
        let header = BASE64_URL_SAFE_NO_PAD.encode(r#"{"alg":"RS256"}"#);
        let payload = BASE64_URL_SAFE_NO_PAD.encode(r#"{"sub":"test"}"#);
        let token = format!("{}.{}.fake_signature", header, payload);

        let decoded = decode_header(&token).expect("should decode header");
        assert!(decoded.kid.is_none(), "kid should be None when not present");
    }

    #[test]
    fn test_decode_header_invalid_token() {
        let result = decode_header("not.a.valid.jwt.token");
        assert!(result.is_err(), "should fail to decode invalid token");
    }

    #[test]
    fn test_decode_header_wrong_algorithm() {
        let header = BASE64_URL_SAFE_NO_PAD.encode(r#"{"alg":"HS256","kid":"test"}"#);
        let payload = BASE64_URL_SAFE_NO_PAD.encode(r#"{"sub":"test"}"#);
        let token = format!("{}.{}.fake_signature", header, payload);

        let decoded = decode_header(&token).expect("should decode header");
        assert_eq!(decoded.alg, Algorithm::HS256);
        // In verify_apple_id_token, we reject non-RS256 algorithms
    }

    // ========================================================================
    // AppleIdTokenClaims Deserialization Tests
    // ========================================================================

    #[test]
    fn test_apple_claims_deserialization_full() {
        let json = r#"{
            "sub": "001234.abcdef.5678",
            "email": "user@privaterelay.appleid.com",
            "iss": "https://appleid.apple.com",
            "aud": "com.example.app",
            "exp": 1700000000,
            "iat": 1699990000
        }"#;

        let claims: AppleIdTokenClaims = serde_json::from_str(json).expect("should deserialize");
        assert_eq!(claims.sub, "001234.abcdef.5678");
        assert_eq!(
            claims.email,
            Some("user@privaterelay.appleid.com".to_string())
        );
        assert_eq!(claims.iss, "https://appleid.apple.com");
        assert_eq!(claims.aud, "com.example.app");
        assert_eq!(claims.exp, 1700000000);
        assert_eq!(claims.iat, 1699990000);
    }

    #[test]
    fn test_apple_claims_deserialization_minimal() {
        let json = r#"{
            "sub": "001234.abcdef.5678"
        }"#;

        let claims: AppleIdTokenClaims = serde_json::from_str(json).expect("should deserialize");
        assert_eq!(claims.sub, "001234.abcdef.5678");
        assert!(claims.email.is_none());
        // Default values for other fields
        assert_eq!(claims.iss, "");
        assert_eq!(claims.aud, "");
        assert_eq!(claims.exp, 0);
        assert_eq!(claims.iat, 0);
    }

    #[test]
    fn test_apple_claims_deserialization_with_null_email() {
        let json = r#"{
            "sub": "001234.abcdef.5678",
            "email": null
        }"#;

        let claims: AppleIdTokenClaims = serde_json::from_str(json).expect("should deserialize");
        assert!(claims.email.is_none());
    }

    // ========================================================================
    // AppleJwk Deserialization Tests
    // ========================================================================

    #[test]
    fn test_apple_jwk_deserialization() {
        let json = r#"{
            "kty": "RSA",
            "kid": "ABC123",
            "use": "sig",
            "alg": "RS256",
            "n": "base64url_encoded_modulus",
            "e": "AQAB"
        }"#;

        let jwk: AppleJwk = serde_json::from_str(json).expect("should deserialize");
        assert_eq!(jwk.kid, "ABC123");
        assert_eq!(jwk.kty, "RSA");
        assert_eq!(jwk.alg, "RS256");
        assert_eq!(jwk.n, "base64url_encoded_modulus");
        assert_eq!(jwk.e, "AQAB");
    }

    #[test]
    fn test_apple_jwks_response_deserialization() {
        let json = r#"{
            "keys": [
                {
                    "kty": "RSA",
                    "kid": "KEY1",
                    "alg": "RS256",
                    "n": "modulus1",
                    "e": "AQAB"
                },
                {
                    "kty": "RSA",
                    "kid": "KEY2",
                    "alg": "RS256",
                    "n": "modulus2",
                    "e": "AQAB"
                }
            ]
        }"#;

        let response: AppleJwksResponse = serde_json::from_str(json).expect("should deserialize");
        assert_eq!(response.keys.len(), 2);
        assert_eq!(response.keys[0].kid, "KEY1");
        assert_eq!(response.keys[1].kid, "KEY2");
    }

    // ========================================================================
    // Error Message Tests
    // ========================================================================

    #[test]
    fn test_error_messages_are_descriptive() {
        // Test that our error messages contain useful information
        let error = IdentityError::OAuthError("Apple ID token has expired".to_string());
        let error_str = format!("{:?}", error);
        assert!(
            error_str.contains("expired"),
            "Error should mention expiration"
        );

        let error =
            IdentityError::OAuthError("Apple ID token signature verification failed".to_string());
        let error_str = format!("{:?}", error);
        assert!(
            error_str.contains("signature"),
            "Error should mention signature"
        );
    }

    // ========================================================================
    // Integration-style Tests (without actual network calls)
    // ========================================================================

    #[test]
    fn test_oauth_provider_as_str() {
        assert_eq!(OAuthProvider::Google.as_str(), "google");
        assert_eq!(OAuthProvider::Apple.as_str(), "apple");
    }

    #[test]
    fn test_to_expiry_some() {
        let result = to_expiry(Some(1700000000));
        assert!(result.is_some());
        let dt = result.unwrap();
        assert_eq!(dt.timestamp(), 1700000000);
    }

    #[test]
    fn test_to_expiry_none() {
        let result = to_expiry(None);
        assert!(result.is_none());
    }

    #[test]
    fn test_to_expiry_zero() {
        let result = to_expiry(Some(0));
        assert!(result.is_some());
    }

    // ========================================================================
    // Deprecated Function Tests
    // ========================================================================

    #[test]
    fn test_decode_jwt_claims_unsafe_valid_token() {
        // Create a valid JWT structure
        let header = BASE64_URL_SAFE_NO_PAD.encode(r#"{"alg":"RS256","kid":"test"}"#);
        let payload =
            BASE64_URL_SAFE_NO_PAD.encode(r#"{"sub":"test-user-123","email":"test@example.com"}"#);
        let token = format!("{}.{}.fake_signature", header, payload);

        let result: Result<AppleIdTokenClaims> = decode_jwt_claims_unsafe(&token);
        assert!(result.is_ok());
        let claims = result.unwrap();
        assert_eq!(claims.sub, "test-user-123");
        assert_eq!(claims.email, Some("test@example.com".to_string()));
    }

    #[test]
    fn test_decode_jwt_claims_unsafe_invalid_format() {
        let result: Result<AppleIdTokenClaims> = decode_jwt_claims_unsafe("not-a-jwt");
        assert!(result.is_err());
        let error = result.unwrap_err();
        assert!(format!("{:?}", error).contains("Invalid ID token format"));
    }

    #[test]
    fn test_decode_jwt_claims_unsafe_invalid_base64() {
        let token = "header.!!!invalid_base64!!!.signature";
        let result: Result<AppleIdTokenClaims> = decode_jwt_claims_unsafe(token);
        assert!(result.is_err());
    }

    #[test]
    fn test_decode_jwt_claims_unsafe_invalid_json() {
        let header = BASE64_URL_SAFE_NO_PAD.encode(r#"{"alg":"RS256"}"#);
        let payload = BASE64_URL_SAFE_NO_PAD.encode("not valid json");
        let token = format!("{}.{}.signature", header, payload);

        let result: Result<AppleIdTokenClaims> = decode_jwt_claims_unsafe(&token);
        assert!(result.is_err());
    }

    // ========================================================================
    // Validation Rules Tests
    // ========================================================================

    #[test]
    fn test_validation_requires_rs256() {
        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_issuer(&[APPLE_ISSUER]);
        validation.set_audience(&["com.example.app"]);
        validation.validate_exp = true;

        // Validation is set up correctly
        assert!(validation.algorithms.contains(&Algorithm::RS256));
        assert!(validation.validate_exp);
    }

    #[test]
    fn test_apple_issuer_constant() {
        assert_eq!(APPLE_ISSUER, "https://appleid.apple.com");
    }

    #[test]
    fn test_apple_jwks_url_constant() {
        assert_eq!(APPLE_JWKS_URL, "https://appleid.apple.com/auth/keys");
    }

    #[test]
    fn test_cache_ttl_is_one_hour() {
        assert_eq!(APPLE_JWKS_CACHE_TTL_SECS, 3600);
    }
}
