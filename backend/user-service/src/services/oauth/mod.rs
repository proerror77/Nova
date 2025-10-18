use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use thiserror::Error;

pub mod apple;
pub mod facebook;
pub mod google;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthUserInfo {
    /// OAuth provider (apple, google, facebook)
    pub provider: String,
    /// Provider-specific user ID
    pub provider_user_id: String,
    /// User's email from provider
    pub email: String,
    /// User's display name from provider
    pub display_name: Option<String>,
    /// Access token from provider
    pub access_token: String,
    /// Refresh token (if available)
    pub refresh_token: Option<String>,
    /// Token expiration (if available)
    pub token_expires_at: Option<i64>,
}

#[derive(Debug, Error)]
pub enum OAuthError {
    #[error("Invalid authorization code: {0}")]
    InvalidAuthCode(String),

    #[error("Failed to exchange token: {0}")]
    TokenExchange(String),

    #[error("Failed to fetch user info: {0}")]
    UserInfoFetch(String),

    #[error("Network error: {0}")]
    NetworkError(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),

    #[error("Invalid state parameter")]
    InvalidState,

    #[error("Provider error: {0}")]
    ProviderError(String),
}

#[async_trait]
pub trait OAuthProvider: Send + Sync {
    /// Get authorization URL for the OAuth provider
    fn get_authorization_url(&self, state: &str) -> Result<String, OAuthError>;

    /// Exchange authorization code for tokens
    async fn exchange_code(
        &self,
        code: &str,
        redirect_uri: &str,
    ) -> Result<OAuthUserInfo, OAuthError>;

    /// Verify and parse OAuth state parameter
    fn verify_state(&self, state: &str) -> Result<(), OAuthError>;

    /// Get provider name
    fn provider_name(&self) -> &str;
}

/// Factory for creating OAuth provider instances
pub struct OAuthProviderFactory;

impl OAuthProviderFactory {
    /// Create OAuth provider by name
    pub fn create(provider: &str) -> Result<Box<dyn OAuthProvider>, OAuthError> {
        match provider.to_lowercase().as_str() {
            "apple" => Ok(Box::new(apple::AppleOAuthProvider::new()?)),
            "google" => Ok(Box::new(google::GoogleOAuthProvider::new()?)),
            "facebook" => Ok(Box::new(facebook::FacebookOAuthProvider::new()?)),
            _ => Err(OAuthError::ConfigError(format!(
                "Unknown OAuth provider: {}",
                provider
            ))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_oauth_error_display() {
        let err = OAuthError::InvalidAuthCode("test".to_string());
        assert!(err.to_string().contains("Invalid authorization code"));
    }

    #[test]
    fn test_oauth_user_info_serialize() {
        let user_info = OAuthUserInfo {
            provider: "google".to_string(),
            provider_user_id: "123456".to_string(),
            email: "test@example.com".to_string(),
            display_name: Some("Test User".to_string()),
            access_token: "token".to_string(),
            refresh_token: None,
            token_expires_at: None,
        };

        let json = serde_json::to_string(&user_info).unwrap();
        assert!(json.contains("google"));
        assert!(json.contains("test@example.com"));
    }
}
