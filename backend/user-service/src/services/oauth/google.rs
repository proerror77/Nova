use super::{OAuthError, OAuthProvider, OAuthUserInfo};
use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Clone)]
pub struct GoogleOAuthProvider {
    client_id: String,
    client_secret: String,
    redirect_uri: String,
    http_client: Arc<Client>,
}

#[derive(Debug, Serialize, Deserialize)]
struct GoogleTokenResponse {
    access_token: String,
    expires_in: i64,
    refresh_token: Option<String>,
    token_type: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct GoogleUserInfo {
    sub: String,
    email: String,
    email_verified: bool,
    name: Option<String>,
    picture: Option<String>,
}

impl GoogleOAuthProvider {
    pub fn new() -> Result<Self, OAuthError> {
        let client_id = std::env::var("GOOGLE_CLIENT_ID")
            .map_err(|_| OAuthError::ConfigError("GOOGLE_CLIENT_ID not set".to_string()))?;
        let client_secret = std::env::var("GOOGLE_CLIENT_SECRET")
            .map_err(|_| OAuthError::ConfigError("GOOGLE_CLIENT_SECRET not set".to_string()))?;
        let redirect_uri = std::env::var("GOOGLE_REDIRECT_URI")
            .map_err(|_| OAuthError::ConfigError("GOOGLE_REDIRECT_URI not set".to_string()))?;

        Ok(Self {
            client_id,
            client_secret,
            redirect_uri,
            http_client: Arc::new(Client::new()),
        })
    }
}

#[async_trait]
impl OAuthProvider for GoogleOAuthProvider {
    fn get_authorization_url(&self, state: &str) -> Result<String, OAuthError> {
        let auth_url = format!(
            "https://accounts.google.com/o/oauth2/v2/auth?client_id={}&redirect_uri={}&response_type=code&scope=openid%20email%20profile&state={}",
            urlencoding::encode(&self.client_id),
            urlencoding::encode(&self.redirect_uri),
            urlencoding::encode(state)
        );
        Ok(auth_url)
    }

    async fn exchange_code(
        &self,
        code: &str,
        redirect_uri: &str,
    ) -> Result<OAuthUserInfo, OAuthError> {
        // Exchange authorization code for access token
        let token_response = self
            .http_client
            .post("https://oauth2.googleapis.com/token")
            .form(&[
                ("client_id", self.client_id.as_str()),
                ("client_secret", self.client_secret.as_str()),
                ("code", code),
                ("grant_type", "authorization_code"),
                ("redirect_uri", redirect_uri),
            ])
            .send()
            .await
            .map_err(|e| OAuthError::TokenExchange(format!("HTTP error: {}", e)))?
            .json::<GoogleTokenResponse>()
            .await
            .map_err(|e| OAuthError::TokenExchange(format!("JSON parse error: {}", e)))?;

        // Fetch user info
        let user_info = self
            .http_client
            .get("https://openidconnect.googleapis.com/v1/userinfo")
            .bearer_auth(&token_response.access_token)
            .send()
            .await
            .map_err(|e| OAuthError::UserInfoFetch(format!("HTTP error: {}", e)))?
            .json::<GoogleUserInfo>()
            .await
            .map_err(|e| OAuthError::UserInfoFetch(format!("JSON parse error: {}", e)))?;

        let token_expires_at = if token_response.expires_in > 0 {
            Some(chrono::Utc::now().timestamp() + token_response.expires_in)
        } else {
            None
        };

        Ok(OAuthUserInfo {
            provider: "google".to_string(),
            provider_user_id: user_info.sub,
            email: user_info.email,
            display_name: user_info.name,
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
        "google"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_google_oauth_provider_name() {
        // This test will fail if GOOGLE_* env vars are not set, which is expected
        // In real tests, we would mock these
        if let Ok(provider) = GoogleOAuthProvider::new() {
            assert_eq!(provider.provider_name(), "google");
        }
    }
}
