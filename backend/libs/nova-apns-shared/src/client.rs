use std::fs::File;
use std::io::{Cursor, Read};
use std::sync::Arc;

use a2::{
    Client, ClientConfig, DefaultNotificationBuilder, Endpoint, NotificationBuilder,
    NotificationOptions, Priority,
};
use tokio::sync::Mutex;
use tracing::{error, info};

use crate::config::{ApnsAuthMode, ApnsConfig};

/// Error type for APNs operations
#[derive(Debug)]
pub enum ApnsError {
    StartServer(String),
    Internal,
    Config(String),
}

impl std::fmt::Display for ApnsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ApnsError::StartServer(msg) => write!(f, "Failed to start APNs server: {}", msg),
            ApnsError::Internal => write!(f, "Internal APNs error"),
            ApnsError::Config(msg) => write!(f, "APNs configuration error: {}", msg),
        }
    }
}

impl std::error::Error for ApnsError {}

/// Trait for push notification providers
#[async_trait::async_trait]
pub trait PushProvider: Send + Sync {
    /// Sends a push notification to a device
    ///
    /// # Arguments
    /// * `device_token` - Device token (APNs device token or FCM registration token)
    /// * `title` - Notification title
    /// * `body` - Notification body text
    /// * `badge` - Optional badge count to display on app icon
    ///
    /// # Returns
    /// `Ok(())` if notification was sent successfully, `Err(ApnsError)` otherwise
    async fn send(
        &self,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), ApnsError>;
}

// Re-export PushProvider type for services that need a trait object
pub type DynPushProvider = Box<dyn PushProvider>;

/// Apple Push Notification Service (APNs) provider
#[derive(Clone)]
pub struct ApnsPush {
    inner: Arc<Mutex<Client>>,
    topic: String,
    is_production: bool,
}

impl ApnsPush {
    /// Creates a new APNs push provider
    ///
    /// # Arguments
    /// * `cfg` - APNs configuration containing authentication credentials, bundle ID, etc.
    ///
    /// # Returns
    /// `Ok(ApnsPush)` if initialization succeeds, `Err(ApnsError)` if credentials loading fails
    pub fn new(cfg: &ApnsConfig) -> Result<Self, ApnsError> {
        let endpoint = if cfg.is_production {
            Endpoint::Production
        } else {
            Endpoint::Sandbox
        };

        let client_config = ClientConfig::new(endpoint);

        let client = match &cfg.auth_mode {
            ApnsAuthMode::Certificate { path, passphrase } => {
                let mut file = File::open(path).map_err(|e| {
                    ApnsError::StartServer(format!("failed to open certificate file: {e}"))
                })?;
                let password = passphrase.as_deref().unwrap_or("");

                Client::certificate(&mut file, password, client_config).map_err(|e| {
                    ApnsError::StartServer(format!(
                        "failed to initialize APNs client with certificate: {e}"
                    ))
                })?
            }
            ApnsAuthMode::Token {
                key_path,
                key_id,
                team_id,
            } => {
                let mut file = File::open(key_path).map_err(|e| {
                    ApnsError::StartServer(format!("failed to open .p8 key file: {e}"))
                })?;
                let mut key_pem = Vec::new();
                file.read_to_end(&mut key_pem).map_err(|e| {
                    ApnsError::StartServer(format!("failed to read .p8 key file: {e}"))
                })?;

                let mut key_reader = Cursor::new(key_pem);
                Client::token(&mut key_reader, key_id, team_id, client_config).map_err(|e| {
                    ApnsError::StartServer(format!(
                        "failed to initialize APNs client with JWT token: {e}"
                    ))
                })?
            }
        };

        let auth_type = match &cfg.auth_mode {
            ApnsAuthMode::Certificate { .. } => "certificate (.p12)",
            ApnsAuthMode::Token { .. } => "token (.p8 JWT)",
        };

        info!(
            "Initialized APNs client for bundle_id={}, production={}, auth={}",
            cfg.bundle_id, cfg.is_production, auth_type
        );

        Ok(Self {
            inner: Arc::new(Mutex::new(client)),
            topic: cfg.bundle_id.clone(),
            is_production: cfg.is_production,
        })
    }

    /// Legacy method for sending alerts (kept for backward compatibility)
    #[deprecated(note = "Use the PushProvider trait method instead")]
    pub async fn send_alert(
        &self,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), ApnsError> {
        self.send(device_token, title, body, badge).await
    }
}

#[async_trait::async_trait]
impl PushProvider for ApnsPush {
    async fn send(
        &self,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), ApnsError> {
        let device_token_prefix = device_token.chars().take(8).collect::<String>();

        let mut builder = DefaultNotificationBuilder::new()
            .set_title(&title)
            .set_body(&body)
            .set_sound("default");

        if let Some(badge_count) = badge {
            builder = builder.set_badge(badge_count);
        }

        let options = NotificationOptions {
            apns_topic: Some(&self.topic),
            apns_priority: Some(Priority::High),
            ..Default::default()
        };

        let payload = builder.build(&device_token, options);

        let client = self.inner.lock().await;

        match client.send(payload).await {
            Ok(response) => {
                info!(
                    "APNs notification sent successfully to token {} (apns_id: {:?})",
                    device_token_prefix, response.apns_id
                );
                Ok(())
            }
            Err(e) => {
                error!("APNs send failed for token {}: {}", device_token_prefix, e);
                Err(ApnsError::Config(format!("APNs send failed: {e}")))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_apns_config_certificate_production_flag() {
        let cfg = ApnsConfig::new(
            "/path/to/cert.p12".to_string(),
            "com.example.app".to_string(),
            true,
        );

        assert_eq!(cfg.is_production, true);
        assert_eq!(cfg.bundle_id, "com.example.app");
    }

    #[test]
    fn test_apns_config_token_auth() {
        let cfg = ApnsConfig::with_token(
            "/path/to/key.p8".to_string(),
            "KEY123".to_string(),
            "TEAM456".to_string(),
            "com.example.app".to_string(),
            false,
        );

        assert_eq!(cfg.is_production, false);
        assert_eq!(cfg.bundle_id, "com.example.app");
        match cfg.auth_mode {
            ApnsAuthMode::Token {
                key_id, team_id, ..
            } => {
                assert_eq!(key_id, "KEY123");
                assert_eq!(team_id, "TEAM456");
            }
            _ => panic!("Expected Token auth mode"),
        }
    }

    #[test]
    fn test_apns_config_endpoint() {
        let prod_cfg = ApnsConfig::new(
            "/path/to/cert.p12".to_string(),
            "com.example.app".to_string(),
            true,
        );

        let dev_cfg = ApnsConfig::new(
            "/path/to/cert.p12".to_string(),
            "com.example.app".to_string(),
            false,
        );

        assert_eq!(prod_cfg.endpoint(), "api.push.apple.com");
        assert_eq!(dev_cfg.endpoint(), "api.sandbox.push.apple.com");
    }
}
