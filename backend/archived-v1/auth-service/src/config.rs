/// Configuration management
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server_host: String,
    pub server_port: u16,
    pub database_url: String,
    pub redis_url: String,
    #[serde(default)]
    pub oauth: OAuthConfig,
    #[serde(default)]
    pub email: EmailConfig,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct OAuthConfig {
    pub google_client_id: Option<String>,
    pub google_client_secret: Option<String>,
    pub google_redirect_uri: Option<String>,
    pub apple_team_id: Option<String>,
    pub apple_client_id: Option<String>,
    pub apple_key_id: Option<String>,
    pub apple_private_key: Option<String>,
    pub apple_redirect_uri: Option<String>,
    pub facebook_app_id: Option<String>,
    pub facebook_app_secret: Option<String>,
    pub facebook_redirect_uri: Option<String>,
    pub wechat_app_id: Option<String>,
    pub wechat_app_secret: Option<String>,
    pub wechat_redirect_uri: Option<String>,
    #[serde(default = "default_oauth_scope")]
    pub default_scope: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EmailConfig {
    #[serde(default = "default_smtp_host")]
    pub smtp_host: String,
    #[serde(default = "default_smtp_port")]
    pub smtp_port: u16,
    #[serde(default)]
    pub smtp_username: Option<String>,
    #[serde(default)]
    pub smtp_password: Option<String>,
    #[serde(default = "default_smtp_from")]
    pub smtp_from: String,
    #[serde(default = "default_use_starttls")]
    pub use_starttls: bool,
    #[serde(default)]
    pub verification_base_url: Option<String>,
    #[serde(default)]
    pub password_reset_base_url: Option<String>,
}

impl Config {
    pub fn from_env() -> Result<Self, envy::Error> {
        envy::from_env()
    }
}

impl Default for EmailConfig {
    fn default() -> Self {
        Self {
            smtp_host: default_smtp_host(),
            smtp_port: default_smtp_port(),
            smtp_username: None,
            smtp_password: None,
            smtp_from: default_smtp_from(),
            use_starttls: default_use_starttls(),
            verification_base_url: None,
            password_reset_base_url: None,
        }
    }
}

fn default_smtp_host() -> String {
    "localhost".to_string()
}

fn default_smtp_port() -> u16 {
    1025
}

fn default_smtp_from() -> String {
    "noreply@nova.dev".to_string()
}

fn default_use_starttls() -> bool {
    false
}

fn default_oauth_scope() -> String {
    "email profile".to_string()
}
