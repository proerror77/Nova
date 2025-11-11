// Re-export APNs types from shared library (internal use only)
pub use nova_apns_shared::{
    client::ApnsError, ApnsPush as NovaApnsPush, PushProvider as NovaPushProvider,
};

use crate::{config::ApnsConfig, error::AppError};
use async_trait::async_trait;

/// Local PushProvider trait that uses AppError for consistency across the service
/// This trait abstracts both APNs and FCM providers with a unified error type
#[async_trait]
pub trait PushProvider: Send + Sync {
    /// Send a push notification
    async fn send(
        &self,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), AppError>;
}

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

/// Implement local PushProvider trait for ApnsPush
/// This provides a unified interface with AppError for both APNs and FCM
#[async_trait]
impl PushProvider for ApnsPush {
    async fn send(
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
