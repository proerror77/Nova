// Re-export APNs types from shared library
pub use nova_apns_shared::{ApnsPush as NovaApnsPush, PushProvider, ApnsError};

use crate::{config::ApnsConfig, error::AppError};

/// Wrapper around nova-apns-shared ApnsPush that converts ApnsError to AppError
#[derive(Clone)]
pub struct ApnsPush(NovaApnsPush);

impl ApnsPush {
    /// Creates a new APNs push provider
    pub fn new(cfg: &ApnsConfig) -> Result<Self, AppError> {
        NovaApnsPush::new(cfg)
            .map(ApnsPush)
            .map_err(|e| AppError::Config(e.to_string()))
    }

    /// Legacy method for sending alerts (kept for backward compatibility)
    #[deprecated(note = "Use the PushProvider trait directly")]
    pub async fn send_alert(
        &self,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), AppError> {
        self.0
            .send(device_token, title, body, badge)
            .await
            .map_err(|e| AppError::Config(e.to_string()))
    }

    /// Send notification using underlying provider
    pub async fn send(
        &self,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), AppError> {
        self.0
            .send(device_token, title, body, badge)
            .await
            .map_err(|e| AppError::Config(e.to_string()))
    }
}
