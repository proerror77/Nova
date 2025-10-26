use super::{OAuthError, OAuthProvider, OAuthUserInfo};
use crate::services::oauth::jwks_cache::JWKSCache;
use async_trait::async_trait;
use jsonwebtoken::{decode, decode_header, jwk::JwkSet, Algorithm, DecodingKey, Validation};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Clone)]
pub struct AppleOAuthProvider {
    team_id: String,
    client_id: String,
    key_id: String,
    private_key: String,
    redirect_uri: String,
    http_client: Arc<Client>,
    jwks_cache: Option<Arc<JWKSCache>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct AppleTokenResponse {
    access_token: String,
    expires_in: i64,
    refresh_token: Option<String>,
    token_type: String,
    id_token: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AppleUserInfo {
    pub sub: String,
    pub email: String,
    pub email_verified: Option<bool>,
    #[serde(default)]
    pub is_private_email: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct AppleIdTokenClaims {
    iss: String,
    aud: String,
    sub: String,
    exp: i64,
    iat: i64,
    email: Option<String>,
    email_verified: Option<String>,
}

impl AppleOAuthProvider {
    pub fn new() -> Result<Self, OAuthError> {
        let team_id = std::env::var("APPLE_TEAM_ID")
            .map_err(|_| OAuthError::ConfigError("APPLE_TEAM_ID not set".to_string()))?;
        let client_id = std::env::var("APPLE_CLIENT_ID")
            .map_err(|_| OAuthError::ConfigError("APPLE_CLIENT_ID not set".to_string()))?;
        let key_id = std::env::var("APPLE_KEY_ID")
            .map_err(|_| OAuthError::ConfigError("APPLE_KEY_ID not set".to_string()))?;
        let private_key = std::env::var("APPLE_PRIVATE_KEY")
            .map_err(|_| OAuthError::ConfigError("APPLE_PRIVATE_KEY not set".to_string()))?;
        let redirect_uri = std::env::var("APPLE_REDIRECT_URI")
            .map_err(|_| OAuthError::ConfigError("APPLE_REDIRECT_URI not set".to_string()))?;

        Ok(Self {
            team_id,
            client_id,
            key_id,
            private_key,
            redirect_uri,
            http_client: Arc::new(Client::new()),
            jwks_cache: None,
        })
    }

    /// Set the JWKS cache for optimized token verification
    pub fn with_jwks_cache(mut self, cache: Arc<JWKSCache>) -> Self {
        self.jwks_cache = Some(cache);
        self
    }

    /// Generate Apple client secret (JWT signed with private key)
    /// This is required for server-side OAuth flow with Apple
    fn generate_client_secret(&self) -> Result<String, OAuthError> {
        use jsonwebtoken::{encode, EncodingKey, Header};
        use serde_json::json;

        let now = chrono::Utc::now().timestamp();
        let expiration = now + 3600; // 1 hour

        let claims = json!({
            "iss": self.team_id,
            "aud": "https://appleid.apple.com",
            "sub": self.client_id,
            "iat": now,
            "exp": expiration,
        });

        let key = EncodingKey::from_rsa_pem(self.private_key.as_bytes())
            .map_err(|e| OAuthError::ConfigError(format!("Invalid private key: {}", e)))?;

        encode(&Header::new(jsonwebtoken::Algorithm::RS256), &claims, &key)
            .map_err(|e| OAuthError::ConfigError(format!("Failed to encode JWT: {}", e)))
    }

    /// Fetch Apple's public JWKS (with optional caching)
    async fn fetch_apple_jwks(&self) -> Result<JwkSet, OAuthError> {
        if let Some(cache) = &self.jwks_cache {
            // Create a closure that fetches raw JWKS JSON for caching
            let fetch_fn = async {
                self.http_client
                    .get("https://appleid.apple.com/auth/keys")
                    .send()
                    .await
                    .map_err(|e| format!("Failed to fetch Apple keys: {}", e))?
                    .json::<serde_json::Value>()
                    .await
                    .map_err(|e| format!("Failed to parse Apple keys: {}", e))
                    .and_then(|json| {
                        // Convert raw JSON to our JWKS format for caching
                        let keys = json
                            .get("keys")
                            .and_then(|k| k.as_array())
                            .map(|arr| {
                                arr.iter()
                                    .filter_map(|key_obj| {
                                        use crate::services::oauth::jwks_cache::JWKSKey;
                                        Some(JWKSKey {
                                            kty: key_obj.get("kty")?.as_str()?.to_string(),
                                            use_: key_obj
                                                .get("use")
                                                .and_then(|v| v.as_str())
                                                .map(String::from),
                                            alg: key_obj
                                                .get("alg")
                                                .and_then(|v| v.as_str())
                                                .map(String::from),
                                            kid: key_obj.get("kid")?.as_str()?.to_string(),
                                            n: key_obj
                                                .get("n")
                                                .and_then(|v| v.as_str())
                                                .map(String::from),
                                            e: key_obj
                                                .get("e")
                                                .and_then(|v| v.as_str())
                                                .map(String::from),
                                            x5c: None,
                                            x5t: None,
                                            x5t_s256: None,
                                        })
                                    })
                                    .collect()
                            })
                            .unwrap_or_default();
                        Ok(crate::services::oauth::jwks_cache::JWKS { keys })
                    })
            };

            // Fetch from cache (or source if not cached)
            let cached_jwks = cache
                .get_jwks("apple", fetch_fn)
                .await
                .map_err(|e| OAuthError::NetworkError(format!("JWKS cache error: {}", e)))?;

            // Convert cached JWKS back to JwkSet format for JWT validation
            let jwk_vec: Vec<serde_json::Value> = cached_jwks
                .keys
                .into_iter()
                .map(|key| {
                    serde_json::json!({
                        "kty": key.kty,
                        "use": key.use_,
                        "alg": key.alg,
                        "kid": key.kid,
                        "n": key.n,
                        "e": key.e,
                        "x5c": key.x5c,
                        "x5t": key.x5t,
                        "x5t#S256": key.x5t_s256,
                    })
                })
                .collect();

            serde_json::from_value::<JwkSet>(serde_json::json!({ "keys": jwk_vec })).map_err(|e| {
                OAuthError::NetworkError(format!("Failed to convert cached JWKS: {}", e))
            })
        } else {
            // Fetch directly without caching
            self.fetch_apple_jwks_direct().await
        }
    }

    /// Fetch Apple's JWKS directly from the endpoint (no caching)
    async fn fetch_apple_jwks_direct(&self) -> Result<JwkSet, OAuthError> {
        self.http_client
            .get("https://appleid.apple.com/auth/keys")
            .send()
            .await
            .map_err(|e| OAuthError::NetworkError(format!("Failed to fetch Apple keys: {}", e)))?
            .json::<JwkSet>()
            .await
            .map_err(|e| OAuthError::NetworkError(format!("Failed to parse Apple keys: {}", e)))
    }

    /// Verify Apple ID token and extract user information
    /// Fetches Apple's public keys from https://appleid.apple.com/auth/keys
    /// and validates the JWT signature (uses cache if available)
    pub async fn verify_apple_token(&self, id_token: &str) -> Result<AppleUserInfo, OAuthError> {
        // Fetch Apple's public keys (with optional caching)
        let jwks = self.fetch_apple_jwks().await?;

        // Decode JWT header to get key ID
        let header = decode_header(id_token)
            .map_err(|e| OAuthError::InvalidAuthCode(format!("Invalid JWT header: {}", e)))?;

        let kid = header
            .kid
            .ok_or_else(|| OAuthError::InvalidAuthCode("Missing kid in JWT header".to_string()))?;

        // Find matching key
        let jwk = jwks
            .keys
            .iter()
            .find(|k| k.common.key_id.as_ref() == Some(&kid))
            .ok_or_else(|| OAuthError::InvalidAuthCode("Key not found in JWKS".to_string()))?;

        // Create decoding key from JWK
        let decoding_key = DecodingKey::from_jwk(jwk)
            .map_err(|e| OAuthError::InvalidAuthCode(format!("Invalid JWK: {}", e)))?;

        // Validate token
        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_audience(&[&self.client_id]);
        validation.set_issuer(&["https://appleid.apple.com"]);

        let token_data = decode::<AppleIdTokenClaims>(id_token, &decoding_key, &validation)
            .map_err(|e| OAuthError::InvalidAuthCode(format!("JWT validation failed: {}", e)))?;

        // Extract user info from claims
        Ok(AppleUserInfo {
            sub: token_data.claims.sub,
            email: token_data.claims.email.unwrap_or_default(),
            email_verified: token_data
                .claims
                .email_verified
                .and_then(|v| v.parse().ok()),
            is_private_email: false,
        })
    }
}

#[async_trait]
impl OAuthProvider for AppleOAuthProvider {
    fn get_authorization_url(&self, state: &str) -> Result<String, OAuthError> {
        let auth_url = format!(
            "https://appleid.apple.com/auth/authorize?client_id={}&redirect_uri={}&response_type=code&scope=openid%20email&response_mode=form_post&state={}",
            urlencoding::encode(&self.client_id),
            urlencoding::encode(&self.redirect_uri),
            urlencoding::encode(state)
        );
        Ok(auth_url)
    }

    async fn exchange_code(
        &self,
        code: &str,
        _redirect_uri: &str,
    ) -> Result<OAuthUserInfo, OAuthError> {
        let client_secret = self.generate_client_secret()?;

        // Exchange authorization code for access token
        let token_response = self
            .http_client
            .post("https://appleid.apple.com/auth/token")
            .form(&[
                ("client_id", self.client_id.as_str()),
                ("client_secret", client_secret.as_str()),
                ("code", code),
                ("grant_type", "authorization_code"),
            ])
            .send()
            .await
            .map_err(|e| OAuthError::TokenExchange(format!("HTTP error: {}", e)))?
            .json::<AppleTokenResponse>()
            .await
            .map_err(|e| OAuthError::TokenExchange(format!("JSON parse error: {}", e)))?;

        let token_expires_at = if token_response.expires_in > 0 {
            Some(chrono::Utc::now().timestamp() + token_response.expires_in)
        } else {
            None
        };

        // Verify and decode ID token to get user info
        let user_info = if let Some(id_token) = &token_response.id_token {
            self.verify_apple_token(id_token).await?
        } else {
            return Err(OAuthError::TokenExchange(
                "No id_token in response".to_string(),
            ));
        };

        Ok(OAuthUserInfo {
            provider: "apple".to_string(),
            provider_user_id: user_info.sub,
            email: user_info.email,
            display_name: None,
            access_token: token_response.access_token,
            refresh_token: token_response.refresh_token,
            token_expires_at,
        })
    }

    fn verify_state(&self, state: &str) -> Result<(), OAuthError> {
        if state.is_empty() {
            return Err(OAuthError::InvalidState);
        }
        Ok(())
    }

    fn provider_name(&self) -> &str {
        "apple"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_apple_oauth_provider_name() {
        if let Ok(provider) = AppleOAuthProvider::new() {
            assert_eq!(provider.provider_name(), "apple");
        }
    }
}
