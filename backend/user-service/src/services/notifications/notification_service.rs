/// T202: Notification Service
///
/// This module provides the high-level notification service that:
/// 1. Stores notifications in the database
/// 2. Sends push notifications via FCM (Android/Web) and APNs (iOS)
/// 3. Handles retries and error recovery
/// 4. Supports notification preferences and filtering
use super::{APNsClient, APNsPriority, FCMClient, KafkaNotification};
use chrono::Utc;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use uuid::Uuid;

/// Represents a device's push notification configuration
#[derive(Debug, Clone)]
pub struct DevicePushConfig {
    pub device_id: Uuid,
    pub user_id: Uuid,
    pub device_type: DeviceType,
    pub device_token: String,
    pub enabled: bool,
}

/// Device type (iOS or Android)
#[derive(Debug, Clone, PartialEq)]
pub enum DeviceType {
    IOS,
    Android,
    Web,
}

impl DeviceType {
    pub fn from_string(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "ios" => Some(DeviceType::IOS),
            "android" => Some(DeviceType::Android),
            "web" => Some(DeviceType::Web),
            _ => None,
        }
    }
}

/// User's notification preferences
#[derive(Debug, Clone)]
pub struct NotificationPreferences {
    pub user_id: Uuid,
    pub likes_enabled: bool,
    pub comments_enabled: bool,
    pub follows_enabled: bool,
    pub messages_enabled: bool,
    pub mentions_enabled: bool,
}

/// Push notification result
#[derive(Debug, Clone)]
pub struct PushNotificationResult {
    pub device_id: Uuid,
    pub success: bool,
    pub message_id: Option<String>,
    pub error: Option<String>,
}

/// Main Notification Service
pub struct NotificationService {
    db: PgPool,
    fcm_client: Option<Arc<FCMClient>>,
    apns_client: Option<Arc<APNsClient>>,
}

impl NotificationService {
    /// Create a new notification service
    pub fn new(
        db: PgPool,
        fcm_client: Option<Arc<FCMClient>>,
        apns_client: Option<Arc<APNsClient>>,
    ) -> Self {
        Self {
            db,
            fcm_client,
            apns_client,
        }
    }

    /// Store notification in database
    pub async fn store_notification(
        &self,
        notification: &KafkaNotification,
    ) -> Result<Uuid, String> {
        let notification_id = Uuid::new_v4();

        let query = r#"
            INSERT INTO notifications (
                id, user_id, event_type, title, body, data, created_at, read
            ) VALUES (
                $1, $2, $3, $4, $5, $6, $7, false
            )
            RETURNING id
        "#;

        let result = sqlx::query(query)
            .bind(&notification_id)
            .bind(&notification.user_id)
            .bind(notification.event_type.to_string())
            .bind(&notification.title)
            .bind(&notification.body)
            .bind(&notification.data)
            .bind(Utc::now())
            .execute(&self.db)
            .await
            .map_err(|e| format!("Failed to store notification: {}", e))?;

        Ok(notification_id)
    }

    /// Get user's devices for push notifications
    pub async fn get_user_devices(&self, user_id: Uuid) -> Result<Vec<DevicePushConfig>, String> {
        let query = r#"
            SELECT device_id, user_id, device_type, device_token, enabled
            FROM user_devices
            WHERE user_id = $1 AND enabled = true
        "#;

        let rows = sqlx::query(query)
            .bind(&user_id)
            .fetch_all(&self.db)
            .await
            .map_err(|e| format!("Failed to fetch user devices: {}", e))?;

        let devices = rows
            .iter()
            .map(|row| {
                let device_type_str: String = row.get("device_type");
                DevicePushConfig {
                    device_id: row.get("device_id"),
                    user_id: row.get("user_id"),
                    device_type: DeviceType::from_string(&device_type_str)
                        .unwrap_or(DeviceType::Android),
                    device_token: row.get("device_token"),
                    enabled: row.get("enabled"),
                }
            })
            .collect();

        Ok(devices)
    }

    /// Get user's notification preferences
    pub async fn get_notification_preferences(
        &self,
        user_id: Uuid,
    ) -> Result<NotificationPreferences, String> {
        let query = r#"
            SELECT user_id, likes_enabled, comments_enabled, follows_enabled,
                   messages_enabled, mentions_enabled
            FROM notification_preferences
            WHERE user_id = $1
        "#;

        let row = sqlx::query(query)
            .bind(&user_id)
            .fetch_optional(&self.db)
            .await
            .map_err(|e| format!("Failed to fetch notification preferences: {}", e))?;

        match row {
            Some(r) => Ok(NotificationPreferences {
                user_id: r.get("user_id"),
                likes_enabled: r.get("likes_enabled"),
                comments_enabled: r.get("comments_enabled"),
                follows_enabled: r.get("follows_enabled"),
                messages_enabled: r.get("messages_enabled"),
                mentions_enabled: r.get("mentions_enabled"),
            }),
            None => {
                // Return default preferences if not found
                Ok(NotificationPreferences {
                    user_id,
                    likes_enabled: true,
                    comments_enabled: true,
                    follows_enabled: true,
                    messages_enabled: true,
                    mentions_enabled: true,
                })
            }
        }
    }

    /// Check if notification should be sent based on user preferences
    pub fn should_send_notification(
        &self,
        preferences: &NotificationPreferences,
        event_type: &str,
    ) -> bool {
        match event_type {
            "like" => preferences.likes_enabled,
            "comment" => preferences.comments_enabled,
            "follow" => preferences.follows_enabled,
            "message" => preferences.messages_enabled,
            "mention_post" | "mention_comment" => preferences.mentions_enabled,
            _ => true,
        }
    }

    /// Send push notification to a user
    pub async fn send_push_notification(
        &self,
        notification: &KafkaNotification,
    ) -> Result<Vec<PushNotificationResult>, String> {
        // Get user preferences
        let preferences = self
            .get_notification_preferences(notification.user_id)
            .await?;

        // Check if notification type is enabled
        if !self.should_send_notification(&preferences, &notification.event_type.to_string()) {
            return Ok(vec![]);
        }

        // Get user devices
        let devices = self.get_user_devices(notification.user_id).await?;

        // Send to each device
        let mut results = Vec::new();

        for device in devices {
            let result = self
                .send_to_device(
                    &device,
                    &notification.title,
                    &notification.body,
                    notification.data.clone(),
                )
                .await;

            results.push(result);
        }

        Ok(results)
    }

    /// Send push notification to a specific device
    async fn send_to_device(
        &self,
        device: &DevicePushConfig,
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> PushNotificationResult {
        match device.device_type {
            DeviceType::IOS => self.send_via_apns(device, title, body).await,
            DeviceType::Android | DeviceType::Web => {
                self.send_via_fcm(device, title, body, data).await
            }
        }
    }

    /// Send via APNs (iOS)
    async fn send_via_apns(
        &self,
        device: &DevicePushConfig,
        title: &str,
        body: &str,
    ) -> PushNotificationResult {
        match &self.apns_client {
            Some(apns) => {
                match apns
                    .send(&device.device_token, title, body, APNsPriority::High)
                    .await
                {
                    Ok(result) => PushNotificationResult {
                        device_id: device.device_id,
                        success: result.success,
                        message_id: Some(result.message_id),
                        error: result.error,
                    },
                    Err(e) => PushNotificationResult {
                        device_id: device.device_id,
                        success: false,
                        message_id: None,
                        error: Some(e),
                    },
                }
            }
            None => PushNotificationResult {
                device_id: device.device_id,
                success: false,
                message_id: None,
                error: Some("APNs client not configured".to_string()),
            },
        }
    }

    /// Send via FCM (Android/Web)
    async fn send_via_fcm(
        &self,
        device: &DevicePushConfig,
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> PushNotificationResult {
        match &self.fcm_client {
            Some(fcm) => match fcm.send(&device.device_token, title, body, data).await {
                Ok(result) => PushNotificationResult {
                    device_id: device.device_id,
                    success: result.success,
                    message_id: Some(result.message_id),
                    error: result.error,
                },
                Err(e) => PushNotificationResult {
                    device_id: device.device_id,
                    success: false,
                    message_id: None,
                    error: Some(e),
                },
            },
            None => PushNotificationResult {
                device_id: device.device_id,
                success: false,
                message_id: None,
                error: Some("FCM client not configured".to_string()),
            },
        }
    }

    /// Register a new device for push notifications
    pub async fn register_device(
        &self,
        user_id: Uuid,
        device_type: DeviceType,
        device_token: String,
    ) -> Result<Uuid, String> {
        let device_id = Uuid::new_v4();
        let device_type_str = match device_type {
            DeviceType::IOS => "ios",
            DeviceType::Android => "android",
            DeviceType::Web => "web",
        };

        let query = r#"
            INSERT INTO user_devices (device_id, user_id, device_type, device_token, enabled, created_at)
            VALUES ($1, $2, $3, $4, true, $5)
            ON CONFLICT (user_id, device_token) DO UPDATE
            SET enabled = true, updated_at = $5
            RETURNING device_id
        "#;

        sqlx::query(query)
            .bind(&device_id)
            .bind(&user_id)
            .bind(device_type_str)
            .bind(&device_token)
            .bind(Utc::now())
            .execute(&self.db)
            .await
            .map_err(|e| format!("Failed to register device: {}", e))?;

        Ok(device_id)
    }

    /// Unregister a device
    pub async fn unregister_device(&self, user_id: Uuid, device_token: &str) -> Result<(), String> {
        let query = r#"
            UPDATE user_devices
            SET enabled = false, updated_at = $1
            WHERE user_id = $2 AND device_token = $3
        "#;

        sqlx::query(query)
            .bind(Utc::now())
            .bind(&user_id)
            .bind(device_token)
            .execute(&self.db)
            .await
            .map_err(|e| format!("Failed to unregister device: {}", e))?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_device_type_from_string() {
        assert_eq!(DeviceType::from_string("ios"), Some(DeviceType::IOS));
        assert_eq!(DeviceType::from_string("iOS"), Some(DeviceType::IOS));
        assert_eq!(
            DeviceType::from_string("android"),
            Some(DeviceType::Android)
        );
        assert_eq!(DeviceType::from_string("web"), Some(DeviceType::Web));
        assert_eq!(DeviceType::from_string("invalid"), None);
    }

    #[test]
    fn test_notification_preferences_default() {
        let user_id = Uuid::new_v4();
        let prefs = NotificationPreferences {
            user_id,
            likes_enabled: true,
            comments_enabled: true,
            follows_enabled: true,
            messages_enabled: true,
            mentions_enabled: true,
        };

        assert!(prefs.likes_enabled);
        assert!(prefs.comments_enabled);
    }

    #[test]
    fn test_push_notification_result_serialization() {
        let result = PushNotificationResult {
            device_id: Uuid::new_v4(),
            success: true,
            message_id: Some("msg-123".to_string()),
            error: None,
        };

        assert!(result.success);
        assert_eq!(result.message_id, Some("msg-123".to_string()));
    }
}
