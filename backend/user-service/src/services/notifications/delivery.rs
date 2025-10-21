//! Notification delivery service for multi-channel dispatch

use crate::services::notifications::models::{
    Notification, DeliveryChannel, DeliveryStatus, NotificationEvent,
};
use serde_json::json;
use tracing::{info, warn};

/// Result of delivery attempt
#[derive(Debug, Clone)]
pub struct DeliveryResult {
    pub channel: DeliveryChannel,
    pub status: DeliveryStatus,
    pub message_id: Option<String>,
    pub error: Option<String>,
}

/// Service for delivering notifications
pub struct DeliveryService {
    /// FCM API key for Android push
    fcm_key: Option<String>,
    /// APNs certificate for iOS push
    apns_cert: Option<String>,
    /// SMTP configuration for email
    smtp_config: Option<SmtpConfig>,
}

#[derive(Debug, Clone)]
pub struct SmtpConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    pub from_email: String,
}

impl DeliveryService {
    /// Create new delivery service
    pub fn new(
        fcm_key: Option<String>,
        apns_cert: Option<String>,
        smtp_config: Option<SmtpConfig>,
    ) -> Self {
        Self {
            fcm_key,
            apns_cert,
            smtp_config,
        }
    }

    /// Deliver notification through all enabled channels
    pub async fn deliver(
        &self,
        notification: &Notification,
        channels: &[DeliveryChannel],
    ) -> Vec<DeliveryResult> {
        let mut results = Vec::new();

        for channel in channels {
            let result = match channel {
                DeliveryChannel::FCM => self.deliver_fcm(notification).await,
                DeliveryChannel::APNs => self.deliver_apns(notification).await,
                DeliveryChannel::Email => self.deliver_email(notification).await,
                DeliveryChannel::InApp => self.deliver_in_app(notification).await,
            };

            results.push(result);
        }

        results
    }

    /// Deliver via Firebase Cloud Messaging
    async fn deliver_fcm(&self, notification: &Notification) -> DeliveryResult {
        match &self.fcm_key {
            Some(key) => {
                info!("Delivering FCM notification to user: {}", notification.user_id);

                // In production, call FCM API
                // For now, simulate successful delivery
                DeliveryResult {
                    channel: DeliveryChannel::FCM,
                    status: DeliveryStatus::Sent,
                    message_id: Some(format!("fcm-{}", uuid::Uuid::new_v4())),
                    error: None,
                }
            }
            None => {
                warn!("FCM not configured, skipping delivery");
                DeliveryResult {
                    channel: DeliveryChannel::FCM,
                    status: DeliveryStatus::Abandoned,
                    message_id: None,
                    error: Some("FCM not configured".to_string()),
                }
            }
        }
    }

    /// Deliver via Apple Push Notification
    async fn deliver_apns(&self, notification: &Notification) -> DeliveryResult {
        match &self.apns_cert {
            Some(_cert) => {
                info!("Delivering APNs notification to user: {}", notification.user_id);

                // In production, call APNs API
                // For now, simulate successful delivery
                DeliveryResult {
                    channel: DeliveryChannel::APNs,
                    status: DeliveryStatus::Sent,
                    message_id: Some(format!("apns-{}", uuid::Uuid::new_v4())),
                    error: None,
                }
            }
            None => {
                warn!("APNs not configured, skipping delivery");
                DeliveryResult {
                    channel: DeliveryChannel::APNs,
                    status: DeliveryStatus::Abandoned,
                    message_id: None,
                    error: Some("APNs not configured".to_string()),
                }
            }
        }
    }

    /// Deliver via Email
    async fn deliver_email(&self, notification: &Notification) -> DeliveryResult {
        match &self.smtp_config {
            Some(smtp) => {
                info!(
                    "Delivering email notification to user: {} via {}",
                    notification.user_id, smtp.host
                );

                // In production, send via SMTP
                // For now, simulate successful delivery
                DeliveryResult {
                    channel: DeliveryChannel::Email,
                    status: DeliveryStatus::Sent,
                    message_id: Some(format!("email-{}", uuid::Uuid::new_v4())),
                    error: None,
                }
            }
            None => {
                warn!("SMTP not configured, skipping email delivery");
                DeliveryResult {
                    channel: DeliveryChannel::Email,
                    status: DeliveryStatus::Abandoned,
                    message_id: None,
                    error: Some("SMTP not configured".to_string()),
                }
            }
        }
    }

    /// Deliver via In-App (WebSocket)
    async fn deliver_in_app(&self, notification: &Notification) -> DeliveryResult {
        info!(
            "Queuing in-app notification for user: {} (WebSocket)",
            notification.user_id
        );

        // In production, send to WebSocket handlers or queue for delivery
        // For now, mark as sent immediately
        DeliveryResult {
            channel: DeliveryChannel::InApp,
            status: DeliveryStatus::Sent,
            message_id: Some(format!("inapp-{}", uuid::Uuid::new_v4())),
            error: None,
        }
    }

    /// Check if a channel is available
    pub fn is_channel_available(&self, channel: &DeliveryChannel) -> bool {
        match channel {
            DeliveryChannel::FCM => self.fcm_key.is_some(),
            DeliveryChannel::APNs => self.apns_cert.is_some(),
            DeliveryChannel::Email => self.smtp_config.is_some(),
            DeliveryChannel::InApp => true, // Always available
        }
    }

    /// Get available channels
    pub fn available_channels(&self) -> Vec<DeliveryChannel> {
        let mut channels = vec![DeliveryChannel::InApp]; // Always available

        if self.fcm_key.is_some() {
            channels.push(DeliveryChannel::FCM);
        }
        if self.apns_cert.is_some() {
            channels.push(DeliveryChannel::APNs);
        }
        if self.smtp_config.is_some() {
            channels.push(DeliveryChannel::Email);
        }

        channels
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use uuid::Uuid;

    #[tokio::test]
    async fn test_delivery_service_creation() {
        let service = DeliveryService::new(None, None, None);
        let channels = service.available_channels();
        assert!(channels.contains(&DeliveryChannel::InApp));
        assert!(!channels.contains(&DeliveryChannel::FCM));
    }

    #[tokio::test]
    async fn test_delivery_with_fcm_key() {
        let service = DeliveryService::new(Some("fcm-key".to_string()), None, None);
        assert!(service.is_channel_available(&DeliveryChannel::FCM));
        assert!(!service.is_channel_available(&DeliveryChannel::APNs));
    }

    #[tokio::test]
    async fn test_deliver_notification() {
        let service = DeliveryService::new(Some("fcm-key".to_string()), None, None);

        let notification = Notification {
            id: 1,
            user_id: Uuid::new_v4(),
            notification_type: "like".to_string(),
            title: "You got a like!".to_string(),
            message: "Someone liked your post".to_string(),
            related_user_id: None,
            related_post_id: None,
            related_entity_id: None,
            read: false,
            read_at: None,
            dismissed: false,
            dismissed_at: None,
            push_sent: false,
            email_sent: false,
            in_app_created: false,
            device_platform: None,
            created_at: Utc::now(),
            delivered_at: None,
            expires_at: Utc::now(),
        };

        let results = service
            .deliver(
                &notification,
                &[DeliveryChannel::FCM, DeliveryChannel::InApp],
            )
            .await;

        assert_eq!(results.len(), 2);
        assert_eq!(results[0].status, DeliveryStatus::Sent);
        assert_eq!(results[1].status, DeliveryStatus::Sent);
    }

    #[tokio::test]
    async fn test_deliver_without_fcm_configured() {
        let service = DeliveryService::new(None, None, None);

        let notification = Notification {
            id: 1,
            user_id: Uuid::new_v4(),
            notification_type: "comment".to_string(),
            title: "New comment".to_string(),
            message: "Someone commented on your post".to_string(),
            related_user_id: None,
            related_post_id: None,
            related_entity_id: None,
            read: false,
            read_at: None,
            dismissed: false,
            dismissed_at: None,
            push_sent: false,
            email_sent: false,
            in_app_created: false,
            device_platform: None,
            created_at: Utc::now(),
            delivered_at: None,
            expires_at: Utc::now(),
        };

        let results = service
            .deliver(&notification, &[DeliveryChannel::FCM])
            .await;

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].status, DeliveryStatus::Abandoned);
    }
}
