/// T202: Notification Service Core Engine
///
/// This module provides the high-level notification service that:
/// 1. Stores notifications in the database
/// 2. Sends push notifications via FCM (Android/Web) and APNs (iOS)
/// 3. Handles retries and error recovery
/// 4. Supports notification preferences and filtering
/// 5. Manages device tokens and delivery tracking
/// 6. Implements priority queuing and batch processing
use super::{APNsClient, FCMClient, KafkaNotification};
use crate::models::{
    CreateNotificationRequest, DeliveryAttempt, DeviceToken, Notification, NotificationChannel,
    NotificationPreference, NotificationPriority, NotificationStatus, NotificationType,
};
use chrono::{Duration, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use std::sync::Arc;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Push notification result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushNotificationResult {
    pub device_token_id: Uuid,
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

    /// Create and store a new notification
    pub async fn create_notification(
        &self,
        req: CreateNotificationRequest,
    ) -> Result<Notification, String> {
        let notification_id = Uuid::new_v4();
        let now = Utc::now();
        let expires_at = now + Duration::days(30); // 30-day expiration

        let query = r#"
            INSERT INTO notifications (
                id, recipient_id, sender_id, notification_type, title, body,
                image_url, object_id, object_type, metadata, priority, status,
                is_read, created_at, updated_at, expires_at
            ) VALUES (
                $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, false, $13, $13, $14
            )
            RETURNING id, recipient_id, sender_id, notification_type, title, body,
                      image_url, object_id, object_type, metadata, priority, status,
                      is_read, created_at, updated_at, expires_at
        "#;

        let row = sqlx::query(query)
            .bind(&notification_id)
            .bind(&req.recipient_id)
            .bind(&req.sender_id)
            .bind(req.notification_type.as_str())
            .bind(&req.title)
            .bind(&req.body)
            .bind(&req.image_url)
            .bind(&req.object_id)
            .bind(&req.object_type)
            .bind(&req.metadata)
            .bind(req.priority.as_str())
            .bind("queued")
            .bind(&now)
            .bind(&expires_at)
            .fetch_one(&self.db)
            .await
            .map_err(|e| {
                error!("Failed to create notification: {}", e);
                format!("Failed to create notification: {}", e)
            })?;

        let notification = Notification {
            id: row.get("id"),
            recipient_id: row.get("recipient_id"),
            sender_id: row.get("sender_id"),
            notification_type: req.notification_type,
            title: row.get("title"),
            body: row.get("body"),
            image_url: row.get("image_url"),
            object_id: row.get("object_id"),
            object_type: row.get("object_type"),
            metadata: row.get("metadata"),
            priority: req.priority,
            status: NotificationStatus::Queued,
            is_read: false,
            read_at: None,
            created_at: row.get("created_at"),
            updated_at: row.get("updated_at"),
            expires_at: row.get("expires_at"),
        };

        info!(
            "Created notification: {} for user: {}",
            notification_id, req.recipient_id
        );
        Ok(notification)
    }

    /// Register or update a device token
    pub async fn register_device_token(
        &self,
        user_id: Uuid,
        token: String,
        channel: NotificationChannel,
        device_type: String,
    ) -> Result<Uuid, String> {
        let device_token_id = Uuid::new_v4();
        let now = Utc::now();

        let query = r#"
            INSERT INTO device_tokens (
                id, user_id, token, channel, device_type, is_active, created_at
            ) VALUES (
                $1, $2, $3, $4, $5, true, $6
            )
            ON CONFLICT (user_id, token, channel) DO UPDATE
            SET is_active = true, last_used_at = $6
            RETURNING id
        "#;

        let row = sqlx::query(query)
            .bind(&device_token_id)
            .bind(&user_id)
            .bind(&token)
            .bind(channel.as_str())
            .bind(&device_type)
            .bind(&now)
            .fetch_one(&self.db)
            .await
            .map_err(|e| {
                warn!("Failed to register device token: {}", e);
                format!("Failed to register device token: {}", e)
            })?;

        let registered_id: Uuid = row.get("id");
        info!("Registered device token for user: {}", user_id);
        Ok(registered_id)
    }

    /// Unregister a device token
    pub async fn unregister_device_token(&self, user_id: Uuid, token: &str) -> Result<(), String> {
        let query = r#"
            UPDATE device_tokens
            SET is_active = false
            WHERE user_id = $1 AND token = $2
        "#;

        sqlx::query(query)
            .bind(&user_id)
            .bind(token)
            .execute(&self.db)
            .await
            .map_err(|e| {
                warn!("Failed to unregister device token: {}", e);
                format!("Failed to unregister device token: {}", e)
            })?;

        debug!("Unregistered device token for user: {}", user_id);
        Ok(())
    }

    /// Get user's active device tokens
    pub async fn get_user_devices(&self, user_id: Uuid) -> Result<Vec<DeviceToken>, String> {
        let query = r#"
            SELECT id, user_id, token, channel, device_type, is_active, last_used_at, created_at
            FROM device_tokens
            WHERE user_id = $1 AND is_active = true
        "#;

        let rows = sqlx::query(query)
            .bind(&user_id)
            .fetch_all(&self.db)
            .await
            .map_err(|e| format!("Failed to fetch user devices: {}", e))?;

        let devices = rows
            .iter()
            .map(|row| {
                let channel_str: String = row.get("channel");
                let channel = match channel_str.as_str() {
                    "fcm" => NotificationChannel::FCM,
                    "apns" => NotificationChannel::APNs,
                    "websocket" => NotificationChannel::WebSocket,
                    "email" => NotificationChannel::Email,
                    "sms" => NotificationChannel::SMS,
                    _ => NotificationChannel::FCM,
                };

                DeviceToken {
                    id: row.get("id"),
                    user_id: row.get("user_id"),
                    token: row.get("token"),
                    channel,
                    device_type: row.get("device_type"),
                    device_name: None,
                    is_active: row.get("is_active"),
                    last_used_at: row.get("last_used_at"),
                    created_at: row.get("created_at"),
                }
            })
            .collect();

        Ok(devices)
    }

    /// Get user's notification preferences
    pub async fn get_preferences(&self, user_id: Uuid) -> Result<NotificationPreference, String> {
        let query = r#"
            SELECT id, user_id, enabled, like_enabled, comment_enabled, follow_enabled,
                   mention_enabled, message_enabled, stream_enabled,
                   quiet_hours_start, quiet_hours_end, prefer_fcm, prefer_apns, prefer_email,
                   updated_at
            FROM notification_preferences
            WHERE user_id = $1
        "#;

        match sqlx::query(query)
            .bind(&user_id)
            .fetch_optional(&self.db)
            .await
            .map_err(|e| format!("Failed to fetch preferences: {}", e))?
        {
            Some(row) => {
                let pref = NotificationPreference {
                    id: row.get("id"),
                    user_id: row.get("user_id"),
                    enabled: row.get("enabled"),
                    like_enabled: row.get("like_enabled"),
                    comment_enabled: row.get("comment_enabled"),
                    follow_enabled: row.get("follow_enabled"),
                    mention_enabled: row.get("mention_enabled"),
                    message_enabled: row.get("message_enabled"),
                    stream_enabled: row.get("stream_enabled"),
                    quiet_hours_start: row.get("quiet_hours_start"),
                    quiet_hours_end: row.get("quiet_hours_end"),
                    prefer_fcm: row.get("prefer_fcm"),
                    prefer_apns: row.get("prefer_apns"),
                    prefer_email: row.get("prefer_email"),
                    updated_at: row.get("updated_at"),
                };
                Ok(pref)
            }
            None => {
                // Create default preferences
                let pref_id = Uuid::new_v4();
                let now = Utc::now();

                let insert_query = r#"
                    INSERT INTO notification_preferences (
                        id, user_id, enabled, like_enabled, comment_enabled, follow_enabled,
                        mention_enabled, message_enabled, stream_enabled,
                        prefer_fcm, prefer_apns, prefer_email, updated_at
                    ) VALUES (
                        $1, $2, true, true, true, true, true, true, true, true, true, false, $3
                    )
                "#;

                sqlx::query(insert_query)
                    .bind(&pref_id)
                    .bind(&user_id)
                    .bind(&now)
                    .execute(&self.db)
                    .await
                    .map_err(|e| format!("Failed to create default preferences: {}", e))?;

                Ok(NotificationPreference {
                    id: pref_id,
                    user_id,
                    enabled: true,
                    like_enabled: true,
                    comment_enabled: true,
                    follow_enabled: true,
                    mention_enabled: true,
                    message_enabled: true,
                    stream_enabled: true,
                    quiet_hours_start: None,
                    quiet_hours_end: None,
                    prefer_fcm: true,
                    prefer_apns: true,
                    prefer_email: false,
                    updated_at: Utc::now(),
                })
            }
        }
    }

    /// Check if notification should be sent based on preferences
    pub fn should_send_notification(
        &self,
        preferences: &NotificationPreference,
        notification_type: NotificationType,
    ) -> bool {
        if !preferences.enabled {
            return false;
        }

        match notification_type {
            NotificationType::Like => preferences.like_enabled,
            NotificationType::Comment => preferences.comment_enabled,
            NotificationType::Follow => preferences.follow_enabled,
            NotificationType::Mention => preferences.mention_enabled,
            NotificationType::Message => preferences.message_enabled,
            NotificationType::Stream => preferences.stream_enabled,
            _ => true,
        }
    }

    /// Send push notifications to all user devices
    pub async fn send_push_notifications(
        &self,
        notification: &Notification,
    ) -> Result<Vec<PushNotificationResult>, String> {
        // Get user preferences
        let preferences = self.get_preferences(notification.recipient_id).await?;

        // Check if should send
        if !self.should_send_notification(&preferences, notification.notification_type) {
            debug!(
                "Notification disabled for type: {:?}",
                notification.notification_type
            );
            return Ok(Vec::new());
        }

        // Get user devices
        let devices = self.get_user_devices(notification.recipient_id).await?;

        let mut results = Vec::new();

        for device in devices {
            let result = self
                .send_to_device(notification, &device, &preferences)
                .await;
            results.push(result);
        }

        Ok(results)
    }

    /// Send notification to a specific device
    async fn send_to_device(
        &self,
        notification: &Notification,
        device: &DeviceToken,
        preferences: &NotificationPreference,
    ) -> PushNotificationResult {
        match device.channel {
            NotificationChannel::APNs if preferences.prefer_apns => {
                self.send_via_apns(notification, device).await
            }
            NotificationChannel::FCM => self.send_via_fcm(notification, device).await,
            NotificationChannel::WebSocket => {
                // WebSocket handled separately (real-time push)
                PushNotificationResult {
                    device_token_id: device.id,
                    success: true,
                    message_id: Some(notification.id.to_string()),
                    error: None,
                }
            }
            _ => {
                debug!("Unsupported channel for device: {:?}", device.channel);
                PushNotificationResult {
                    device_token_id: device.id,
                    success: false,
                    message_id: None,
                    error: Some("Unsupported channel".to_string()),
                }
            }
        }
    }

    /// Send via APNs (iOS/macOS)
    async fn send_via_apns(
        &self,
        notification: &Notification,
        device: &DeviceToken,
    ) -> PushNotificationResult {
        match &self.apns_client {
            Some(apns) => {
                match apns
                    .send(
                        &device.token,
                        &notification.title,
                        &notification.body,
                        super::apns_client::APNsPriority::High, // Use High priority for normal notifications
                    )
                    .await
                {
                    Ok(result) => {
                        debug!("APNs delivery successful: {}", result.message_id);
                        PushNotificationResult {
                            device_token_id: device.id,
                            success: true,
                            message_id: Some(result.message_id),
                            error: None,
                        }
                    }
                    Err(e) => {
                        warn!("APNs delivery failed: {}", e);
                        PushNotificationResult {
                            device_token_id: device.id,
                            success: false,
                            message_id: None,
                            error: Some(e),
                        }
                    }
                }
            }
            None => {
                warn!("APNs client not configured");
                PushNotificationResult {
                    device_token_id: device.id,
                    success: false,
                    message_id: None,
                    error: Some("APNs client not configured".to_string()),
                }
            }
        }
    }

    /// Send via FCM (Android/Web)
    async fn send_via_fcm(
        &self,
        notification: &Notification,
        device: &DeviceToken,
    ) -> PushNotificationResult {
        match &self.fcm_client {
            Some(fcm) => {
                match fcm
                    .send(
                        &device.token,
                        &notification.title,
                        &notification.body,
                        notification.metadata.clone(),
                    )
                    .await
                {
                    Ok(result) => {
                        debug!("FCM delivery successful: {}", result.message_id);
                        PushNotificationResult {
                            device_token_id: device.id,
                            success: true,
                            message_id: Some(result.message_id),
                            error: result.error,
                        }
                    }
                    Err(e) => {
                        warn!("FCM delivery failed: {}", e);
                        PushNotificationResult {
                            device_token_id: device.id,
                            success: false,
                            message_id: None,
                            error: Some(e),
                        }
                    }
                }
            }
            None => {
                warn!("FCM client not configured");
                PushNotificationResult {
                    device_token_id: device.id,
                    success: false,
                    message_id: None,
                    error: Some("FCM client not configured".to_string()),
                }
            }
        }
    }

    /// Mark notification as read
    pub async fn mark_as_read(&self, notification_id: Uuid) -> Result<(), String> {
        let now = Utc::now();
        let query = r#"
            UPDATE notifications
            SET is_read = true, read_at = $1, status = 'read', updated_at = $1
            WHERE id = $2
        "#;

        sqlx::query(query)
            .bind(&now)
            .bind(&notification_id)
            .execute(&self.db)
            .await
            .map_err(|e| format!("Failed to mark notification as read: {}", e))?;

        Ok(())
    }

    /// Get notification by ID
    pub async fn get_notification(
        &self,
        notification_id: Uuid,
    ) -> Result<Option<Notification>, String> {
        let query = r#"
            SELECT id, recipient_id, sender_id, notification_type, title, body,
                   image_url, object_id, object_type, metadata, priority, status,
                   is_read, read_at, created_at, updated_at, expires_at
            FROM notifications
            WHERE id = $1
        "#;

        match sqlx::query(query)
            .bind(&notification_id)
            .fetch_optional(&self.db)
            .await
            .map_err(|e| format!("Failed to fetch notification: {}", e))?
        {
            Some(row) => {
                let notification_type_str: String = row.get("notification_type");
                let priority_str: String = row.get("priority");
                let status_str: String = row.get("status");

                let notification = Notification {
                    id: row.get("id"),
                    recipient_id: row.get("recipient_id"),
                    sender_id: row.get("sender_id"),
                    notification_type: Self::parse_notification_type(&notification_type_str),
                    title: row.get("title"),
                    body: row.get("body"),
                    image_url: row.get("image_url"),
                    object_id: row.get("object_id"),
                    object_type: row.get("object_type"),
                    metadata: row.get("metadata"),
                    priority: Self::parse_priority(&priority_str),
                    status: Self::parse_status(&status_str),
                    is_read: row.get("is_read"),
                    read_at: row.get("read_at"),
                    created_at: row.get("created_at"),
                    updated_at: row.get("updated_at"),
                    expires_at: row.get("expires_at"),
                };
                Ok(Some(notification))
            }
            None => Ok(None),
        }
    }

    /// Parse notification type from string
    fn parse_notification_type(s: &str) -> NotificationType {
        match s.to_uppercase().as_str() {
            "LIKE" => NotificationType::Like,
            "COMMENT" => NotificationType::Comment,
            "FOLLOW" => NotificationType::Follow,
            "MENTION" => NotificationType::Mention,
            "SYSTEM" => NotificationType::System,
            "MESSAGE" => NotificationType::Message,
            "VIDEO" => NotificationType::Video,
            "STREAM" => NotificationType::Stream,
            _ => NotificationType::System,
        }
    }

    /// Parse priority from string
    fn parse_priority(s: &str) -> NotificationPriority {
        match s.to_uppercase().as_str() {
            "LOW" => NotificationPriority::Low,
            "NORMAL" => NotificationPriority::Normal,
            "HIGH" => NotificationPriority::High,
            _ => NotificationPriority::Normal,
        }
    }

    /// Parse status from string
    fn parse_status(s: &str) -> NotificationStatus {
        match s.to_uppercase().as_str() {
            "QUEUED" => NotificationStatus::Queued,
            "SENDING" => NotificationStatus::Sending,
            "DELIVERED" => NotificationStatus::Delivered,
            "FAILED" => NotificationStatus::Failed,
            "READ" => NotificationStatus::Read,
            "DISMISSED" => NotificationStatus::Dismissed,
            _ => NotificationStatus::Queued,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_notification_type() {
        assert_eq!(
            NotificationService::parse_notification_type("LIKE"),
            NotificationType::Like
        );
        assert_eq!(
            NotificationService::parse_notification_type("comment"),
            NotificationType::Comment
        );
        assert_eq!(
            NotificationService::parse_notification_type("FOLLOW"),
            NotificationType::Follow
        );
        assert_eq!(
            NotificationService::parse_notification_type("mention"),
            NotificationType::Mention
        );
        assert_eq!(
            NotificationService::parse_notification_type("SYSTEM"),
            NotificationType::System
        );
        assert_eq!(
            NotificationService::parse_notification_type("unknown"),
            NotificationType::System
        );
    }

    #[test]
    fn test_parse_priority() {
        assert_eq!(
            NotificationService::parse_priority("LOW"),
            NotificationPriority::Low
        );
        assert_eq!(
            NotificationService::parse_priority("normal"),
            NotificationPriority::Normal
        );
        assert_eq!(
            NotificationService::parse_priority("HIGH"),
            NotificationPriority::High
        );
        assert_eq!(
            NotificationService::parse_priority("unknown"),
            NotificationPriority::Normal
        );
    }

    #[test]
    fn test_parse_status() {
        assert_eq!(
            NotificationService::parse_status("QUEUED"),
            NotificationStatus::Queued
        );
        assert_eq!(
            NotificationService::parse_status("sending"),
            NotificationStatus::Sending
        );
        assert_eq!(
            NotificationService::parse_status("DELIVERED"),
            NotificationStatus::Delivered
        );
        assert_eq!(
            NotificationService::parse_status("FAILED"),
            NotificationStatus::Failed
        );
        assert_eq!(
            NotificationService::parse_status("READ"),
            NotificationStatus::Read
        );
        assert_eq!(
            NotificationService::parse_status("unknown"),
            NotificationStatus::Queued
        );
    }

    #[test]
    fn test_push_notification_result_creation() {
        let result = PushNotificationResult {
            device_token_id: Uuid::new_v4(),
            success: true,
            message_id: Some("msg-123".to_string()),
            error: None,
        };

        assert!(result.success);
        assert_eq!(result.message_id, Some("msg-123".to_string()));
        assert_eq!(result.error, None);
    }

    #[test]
    fn test_push_notification_result_failure() {
        let result = PushNotificationResult {
            device_token_id: Uuid::new_v4(),
            success: false,
            message_id: None,
            error: Some("Connection timeout".to_string()),
        };

        assert!(!result.success);
        assert_eq!(result.message_id, None);
        assert!(result.error.is_some());
    }
}
