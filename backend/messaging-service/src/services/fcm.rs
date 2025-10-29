use fcm::{Client, MessageBuilder, NotificationBuilder};
use std::sync::Arc;
use tracing::{error, info};

use crate::error::AppError;

use super::push::PushProvider;

/// FCM (Firebase Cloud Messaging) push notification provider
#[derive(Clone)]
pub struct FcmPush {
    client: Arc<Client>,
}

impl FcmPush {
    /// Creates a new FCM push provider with the given API key
    pub fn new(_api_key: String) -> Result<Self, AppError> {
        let client = Client::new();

        // Store API key in client for later use
        // Note: fcm crate v0.9 expects API key to be passed in send calls
        Ok(Self {
            client: Arc::new(client),
        })
    }

    /// Internal helper to build and send FCM notification
    async fn send_internal(
        &self,
        api_key: &str,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), AppError> {
        // Build notification payload
        let mut notification_builder = NotificationBuilder::new();
        notification_builder
            .title(&title)
            .body(&body)
            .sound("default");

        // Store badge string to extend lifetime
        let badge_str = badge.map(|b| b.to_string());
        if let Some(ref badge_value) = badge_str {
            notification_builder.badge(badge_value);
        }

        let notification = notification_builder.finalize();

        // Build message
        let mut message_builder = MessageBuilder::new(api_key, &device_token);
        message_builder.notification(notification);

        let message = message_builder.finalize();

        // Send via FCM
        match self.client.send(message).await {
            Ok(response) => {
                info!(
                    "FCM notification sent successfully to token {} (message_id: {:?})",
                    &device_token[..8], // Log only first 8 chars for privacy
                    response.message_id
                );
                Ok(())
            }
            Err(e) => {
                error!("FCM send failed for token {}: {}", &device_token[..8], e);
                Err(AppError::Config(format!("FCM send failed: {}", e)))
            }
        }
    }
}

#[async_trait::async_trait]
impl PushProvider for FcmPush {
    async fn send(
        &self,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), AppError> {
        // In production, FCM API key should come from config
        // For now, we'll expect it to be set via environment variable at runtime
        let api_key = std::env::var("FCM_API_KEY")
            .map_err(|_| AppError::Config("FCM_API_KEY not set".to_string()))?;

        self.send_internal(&api_key, device_token, title, body, badge)
            .await
    }
}

/// Configuration for FCM provider
#[derive(Debug, Clone)]
pub struct FcmConfig {
    pub api_key: String,
}

impl FcmConfig {
    /// Loads FCM config from environment variables
    pub fn from_env() -> Result<Self, AppError> {
        let api_key = std::env::var("FCM_API_KEY")
            .map_err(|_| AppError::Config("FCM_API_KEY not set".to_string()))?;

        if api_key.trim().is_empty() {
            return Err(AppError::Config("FCM_API_KEY is empty".to_string()));
        }

        Ok(Self { api_key })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fcm_config_validation() {
        // Test empty API key
        std::env::remove_var("FCM_API_KEY");
        assert!(FcmConfig::from_env().is_err());

        // Test valid API key
        std::env::set_var("FCM_API_KEY", "test_api_key_123");
        let config = FcmConfig::from_env();
        assert!(config.is_ok());
        assert_eq!(config.unwrap().api_key, "test_api_key_123");
    }
}
