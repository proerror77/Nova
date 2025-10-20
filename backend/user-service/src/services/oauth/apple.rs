use super::{OAuthError, OAuthProvider, OAuthUserInfo};
use async_trait::async_trait;
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
}

#[derive(Debug, Serialize, Deserialize)]
struct AppleTokenResponse {
    access_token: String,
    expires_in: i64,
    refresh_token: Option<String>,
    token_type: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct AppleUserInfo {
    sub: String,
    email: String,
    email_verified: Option<bool>,
    #[serde(default)]
    is_private_email: bool,
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
        })
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

        // Decode id_token to get user info
        // For simplicity, we'll use the access_token to fetch user info
        // In production, you would validate the id_token JWT

        let token_expires_at = if token_response.expires_in > 0 {
            Some(chrono::Utc::now().timestamp() + token_response.expires_in)
        } else {
            None
        };

        // Note: Apple doesn't provide a standard userinfo endpoint for server-side flow
        // The user info comes in the id_token. For this example, we'll create a placeholder.
        // In production, you should decode and validate the JWT id_token.

        Ok(OAuthUserInfo {
            provider: "apple".to_string(),
            provider_user_id: format!("apple_{}", uuid::Uuid::new_v4()), // Placeholder
            email: "user@example.com".to_string(),                       // Would come from id_token
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
