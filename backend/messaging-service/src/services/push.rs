use std::sync::{Arc, Mutex};

use apns2::{ApnsSync, NotificationBuilder, Priority};
use tokio::task;
use tracing::{error, info};

use crate::{config::ApnsConfig, error::AppError};

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
    /// `Ok(())` if notification was sent successfully, `Err(AppError)` otherwise
    async fn send(
        &self,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), AppError>;
}

/// Apple Push Notification Service (APNs) provider
#[derive(Clone)]
pub struct ApnsPush {
    inner: Arc<Mutex<ApnsSync>>,
    topic: String,
}

impl ApnsPush {
    /// Creates a new APNs push provider
    ///
    /// # Arguments
    /// * `cfg` - APNs configuration containing certificate path, bundle ID, etc.
    ///
    /// # Returns
    /// `Ok(ApnsPush)` if initialization succeeds, `Err(AppError)` if certificate loading fails
    pub fn new(cfg: &ApnsConfig) -> Result<Self, AppError> {
        let mut client = ApnsSync::with_certificate(
            &cfg.certificate_path,
            cfg.certificate_passphrase.clone(),
        )
        .map_err(|e| AppError::StartServer(format!("failed to initialize APNs client: {e}")))?;

        client.set_production(cfg.is_production);

        info!(
            "Initialized APNs client for bundle_id={}, production={}",
            cfg.bundle_id, cfg.is_production
        );

        Ok(Self {
            inner: Arc::new(Mutex::new(client)),
            topic: cfg.bundle_id.clone(),
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
    ) -> Result<(), AppError> {
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
    ) -> Result<(), AppError> {
        let topic = self.topic.clone();
        let client = self.inner.clone();

        // APNs client is synchronous, so we run it in a blocking task
        task::spawn_blocking(move || {
            // Extract token prefix before moving device_token
            let device_token_prefix = device_token.chars().take(8).collect::<String>();

            let mut builder = NotificationBuilder::new(topic, device_token);
            builder = builder.title(&title).body(&body).sound("default");

            if let Some(badge_count) = badge {
                builder = builder.badge(badge_count);
            }

            builder = builder.priority(Priority::High);

            let notification = builder.build();

            let guard = client.lock().map_err(|_| AppError::Internal)?;

            guard
                .send(notification)
                .map_err(|e| {
                    error!("APNs send failed for token {}: {}", device_token_prefix, e);
                    AppError::Config(format!("APNs send failed: {e}"))
                })
                .map(|apns_id| {
                    info!(
                        "APNs notification sent successfully to token {} (apns_id: {:?})",
                        device_token_prefix, apns_id
                    );
                })
        })
        .await
        .map_err(|_| AppError::Internal)?
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
}
