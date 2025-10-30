/// Configuration management
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server_host: String,
    pub server_port: u16,
    pub database_url: String,
    pub redis_url: String,
    pub jwt_private_key_pem: String,
    pub jwt_public_key_pem: String,
    pub oauth_providers: OAuthConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct OAuthConfig {
    pub google_client_id: Option<String>,
    pub google_client_secret: Option<String>,
    pub apple_team_id: Option<String>,
    pub apple_key_id: Option<String>,
    pub apple_private_key: Option<String>,
    pub facebook_app_id: Option<String>,
    pub facebook_app_secret: Option<String>,
    pub wechat_app_id: Option<String>,
    pub wechat_app_secret: Option<String>,
}

impl Config {
    pub fn from_env() -> Result<Self, envy::Error> {
        envy::from_env()
    }
}
