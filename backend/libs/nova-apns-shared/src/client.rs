use std::fs::File;
use std::sync::Arc;

use a2::{
    Client, ClientConfig, DefaultNotificationBuilder, Endpoint, NotificationBuilder,
    NotificationOptions, Priority,
};
use tokio::sync::Mutex;
use tracing::{error, info};

use crate::config::ApnsConfig;

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
    /// * `cfg` - APNs configuration containing certificate path, bundle ID, etc.
    ///
    /// # Returns
    /// `Ok(ApnsPush)` if initialization succeeds, `Err(ApnsError)` if certificate loading fails
    pub fn new(cfg: &ApnsConfig) -> Result<Self, ApnsError> {
        let mut file = File::open(&cfg.certificate_path)
            .map_err(|e| ApnsError::StartServer(format!("failed to open certificate file: {e}")))?;

        let password = cfg.certificate_passphrase.as_deref().unwrap_or("");

        let endpoint = if cfg.is_production {
            Endpoint::Production
        } else {
            Endpoint::Sandbox
        };

        let client_config = ClientConfig::new(endpoint);

        let client = Client::certificate(&mut file, password, client_config).map_err(|e| {
            ApnsError::StartServer(format!("failed to initialize APNs client: {e}"))
        })?;

        info!(
            "Initialized APNs client for bundle_id={}, production={}",
            cfg.bundle_id, cfg.is_production
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
    fn test_apns_config_production_flag() {
        let cfg = ApnsConfig {
            certificate_path: "/path/to/cert.p12".to_string(),
            certificate_passphrase: Some("password".to_string()),
            bundle_id: "com.example.app".to_string(),
            is_production: true,
        };

        assert_eq!(cfg.is_production, true);
        assert_eq!(cfg.bundle_id, "com.example.app");
    }

    #[test]
    fn test_apns_config_endpoint() {
        let prod_cfg = ApnsConfig {
            certificate_path: "/path/to/cert.p12".to_string(),
            certificate_passphrase: None,
            bundle_id: "com.example.app".to_string(),
            is_production: true,
        };

        let dev_cfg = ApnsConfig {
            certificate_path: "/path/to/cert.p12".to_string(),
            certificate_passphrase: None,
            bundle_id: "com.example.app".to_string(),
            is_production: false,
        };

        assert_eq!(prod_cfg.endpoint(), "api.push.apple.com");
        assert_eq!(dev_cfg.endpoint(), "api.sandbox.push.apple.com");
    }
}
