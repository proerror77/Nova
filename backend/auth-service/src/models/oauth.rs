use chrono::{DateTime, Utc};
/// OAuth models
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum OAuthProvider {
    #[serde(rename = "google")]
    Google,
    #[serde(rename = "apple")]
    Apple,
    #[serde(rename = "facebook")]
    Facebook,
    #[serde(rename = "wechat")]
    WeChat,
}

impl OAuthProvider {
    pub fn as_str(&self) -> &'static str {
        match self {
            OAuthProvider::Google => "google",
            OAuthProvider::Apple => "apple",
            OAuthProvider::Facebook => "facebook",
            OAuthProvider::WeChat => "wechat",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "google" => Some(OAuthProvider::Google),
            "apple" => Some(OAuthProvider::Apple),
            "facebook" => Some(OAuthProvider::Facebook),
            "wechat" => Some(OAuthProvider::WeChat),
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct OAuthUserInfo {
    pub provider: String,
    pub provider_user_id: String,
    pub email: String,
    pub name: Option<String>,
    pub picture_url: Option<String>,
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub token_expires_at: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct StartOAuthFlowRequest {
    pub provider: String,
    pub redirect_uri: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct StartOAuthFlowResponse {
    pub auth_url: String,
    pub state: String,
}

#[derive(Debug, Deserialize)]
pub struct CompleteOAuthFlowRequest {
    pub provider: String,
    pub code: String,
    pub state: String,
}

/// OAuth connection record in database
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct OAuthConnection {
    pub id: Uuid,
    pub user_id: Uuid,
    pub provider: String,
    pub provider_user_id: String,
    pub email: Option<String>,
    pub name: Option<String>,
    pub picture_url: Option<String>,
    pub access_token_encrypted: Option<String>,
    pub refresh_token_encrypted: Option<String>,
    pub token_type: Option<String>,
    pub expires_at: Option<DateTime<Utc>>,
    pub scopes: Option<String>,
    pub raw_data: Option<serde_json::Value>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl OAuthConnection {
    /// Check if token needs refresh
    pub fn needs_refresh(&self) -> bool {
        if let Some(expires_at) = self.expires_at {
            // Consider it expired if less than 5 minutes remaining
            expires_at < Utc::now() + chrono::Duration::minutes(5)
        } else {
            false
        }
    }
}
