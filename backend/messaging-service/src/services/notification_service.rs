use std::sync::Arc;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{Pool, Postgres, Row};
use uuid::Uuid;

use super::push::ApnsPush;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Notification {
    pub id: Uuid,
    pub recipient_id: Uuid,
    pub actor_id: Uuid,
    pub notification_type: String, // 'message', 'reaction', 'mention', 'follow', 'comment', 'like'
    pub action_type: Option<String>,
    pub target_type: Option<String>,
    pub target_id: Option<Uuid>,
    pub message: Option<serde_json::Value>,
    pub is_read: bool,
    pub read_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub expires_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationResponse {
    pub notifications: Vec<Notification>,
    pub total: usize,
    pub unread_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationPreferences {
    pub user_id: Uuid,
    pub enable_push_notifications: bool,
    pub enable_email_notifications: bool,
    pub enable_sms_notifications: bool,
    pub notification_frequency: String,
    pub quiet_hours_start: Option<String>,
    pub quiet_hours_end: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateNotificationRequest {
    pub recipient_id: Uuid,
    pub actor_id: Uuid,
    pub notification_type: String,
    pub action_type: Option<String>,
    pub target_type: Option<String>,
    pub target_id: Option<Uuid>,
    pub message: Option<serde_json::Value>,
}

pub struct NotificationService;

impl NotificationService {
    /// Create a new notification
    pub async fn create_notification(
        db: &Pool<Postgres>,
        request: CreateNotificationRequest,
    ) -> Result<Notification, String> {
        // Check if user has notifications enabled for this type
        let is_enabled = sqlx::query(
            r#"
            SELECT is_enabled
            FROM notification_subscriptions
            WHERE user_id = $1 AND notification_type = $2
            "#,
        )
        .bind(request.recipient_id)
        .bind(&request.notification_type)
        .fetch_optional(db)
        .await
        .map_err(|e| format!("Failed to check notification preference: {}", e))?
        .and_then(|row| Some(row.get(0)))
        .unwrap_or(true); // Default to enabled

        if !is_enabled {
            return Err("User has disabled this notification type".to_string());
        }

        let notification = sqlx::query_as::<_, Notification>(
            r#"
            INSERT INTO notifications (
                recipient_id, actor_id, notification_type, action_type,
                target_type, target_id, message
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            RETURNING *
            "#,
        )
        .bind(request.recipient_id)
        .bind(request.actor_id)
        .bind(request.notification_type)
        .bind(request.action_type)
        .bind(request.target_type)
        .bind(request.target_id)
        .bind(request.message)
        .fetch_one(db)
        .await
        .map_err(|e| format!("Failed to create notification: {}", e))?;

        Ok(notification)
    }

    pub async fn register_device_token(
        db: &Pool<Postgres>,
        user_id: Uuid,
        device_token: &str,
        device_platform: &str,
        app_version: Option<&str>,
        locale: Option<&str>,
    ) -> Result<(), String> {
        if device_token.trim().is_empty() {
            return Err("Device token cannot be empty".into());
        }

        let platform = device_platform.trim().to_lowercase();
        let normalized_token = device_token.trim();

        sqlx::query(
            r#"
            INSERT INTO notification_device_tokens (
                user_id,
                device_token,
                device_platform,
                app_version,
                locale,
                is_active,
                last_used_at,
                updated_at
            )
            VALUES ($1, $2, $3, $4, $5, TRUE, NOW(), NOW())
            ON CONFLICT (user_id, device_token) DO UPDATE
            SET device_platform = EXCLUDED.device_platform,
                app_version = EXCLUDED.app_version,
                locale = EXCLUDED.locale,
                is_active = TRUE,
                last_used_at = NOW(),
                updated_at = NOW()
            "#,
        )
        .bind(user_id)
        .bind(normalized_token)
        .bind(platform)
        .bind(app_version)
        .bind(locale)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to register device token: {}", e))?;

        Ok(())
    }

    pub async fn unregister_device_token(
        db: &Pool<Postgres>,
        user_id: Uuid,
        device_token: &str,
    ) -> Result<(), String> {
        let normalized = device_token.trim();

        sqlx::query(
            r#"
            UPDATE notification_device_tokens
            SET is_active = FALSE, updated_at = NOW()
            WHERE user_id = $1 AND device_token = $2
            "#,
        )
        .bind(user_id)
        .bind(normalized)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to deactivate device token: {}", e))?;

        Ok(())
    }

    /// Get user's notifications
    pub async fn get_notifications(
        db: &Pool<Postgres>,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<NotificationResponse, String> {
        let limit = limit.min(50); // Cap at 50 notifications

        let notifications = sqlx::query_as::<_, Notification>(
            r#"
            SELECT *
            FROM notifications
            WHERE recipient_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(db)
        .await
        .map_err(|e| format!("Failed to fetch notifications: {}", e))?;

        // Get total count
        let total: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM notifications WHERE recipient_id = $1")
                .bind(user_id)
                .fetch_one(db)
                .await
                .map_err(|e| format!("Failed to count notifications: {}", e))?;

        // Get unread count
        let unread_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM notifications WHERE recipient_id = $1 AND is_read = FALSE",
        )
        .bind(user_id)
        .fetch_one(db)
        .await
        .map_err(|e| format!("Failed to count unread: {}", e))?;

        Ok(NotificationResponse {
            notifications,
            total: total as usize,
            unread_count: unread_count as usize,
        })
    }

    /// Get unread notifications only
    pub async fn get_unread_notifications(
        db: &Pool<Postgres>,
        user_id: Uuid,
        limit: i64,
    ) -> Result<Vec<Notification>, String> {
        let limit = limit.min(50);

        let notifications = sqlx::query_as::<_, Notification>(
            r#"
            SELECT *
            FROM notifications
            WHERE recipient_id = $1 AND is_read = FALSE
            ORDER BY created_at DESC
            LIMIT $2
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .fetch_all(db)
        .await
        .map_err(|e| format!("Failed to fetch unread notifications: {}", e))?;

        Ok(notifications)
    }

    /// Mark notification as read
    pub async fn mark_as_read(db: &Pool<Postgres>, notification_id: Uuid) -> Result<(), String> {
        sqlx::query(
            r#"
            UPDATE notifications
            SET is_read = TRUE, read_at = NOW(), updated_at = NOW()
            WHERE id = $1
            "#,
        )
        .bind(notification_id)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to mark notification as read: {}", e))?;

        Ok(())
    }

    /// Mark all notifications as read for a user
    pub async fn mark_all_as_read(db: &Pool<Postgres>, user_id: Uuid) -> Result<u64, String> {
        let result = sqlx::query(
            r#"
            UPDATE notifications
            SET is_read = TRUE, read_at = NOW(), updated_at = NOW()
            WHERE recipient_id = $1 AND is_read = FALSE
            "#,
        )
        .bind(user_id)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to mark all as read: {}", e))?;

        Ok(result.rows_affected())
    }

    /// Delete a notification
    pub async fn delete_notification(
        db: &Pool<Postgres>,
        notification_id: Uuid,
    ) -> Result<(), String> {
        sqlx::query("DELETE FROM notifications WHERE id = $1")
            .bind(notification_id)
            .execute(db)
            .await
            .map_err(|e| format!("Failed to delete notification: {}", e))?;

        Ok(())
    }

    /// Delete old notifications (cleanup job)
    pub async fn cleanup_old_notifications(db: &Pool<Postgres>) -> Result<u64, String> {
        let result =
            sqlx::query("DELETE FROM notifications WHERE created_at < NOW() - INTERVAL '30 days'")
                .execute(db)
                .await
                .map_err(|e| format!("Failed to cleanup notifications: {}", e))?;

        Ok(result.rows_affected())
    }

    async fn get_active_device_tokens(
        db: &Pool<Postgres>,
        user_id: Uuid,
    ) -> Result<Vec<String>, String> {
        let tokens = sqlx::query_scalar::<_, String>(
            r#"
            SELECT device_token
            FROM notification_device_tokens
            WHERE user_id = $1 AND is_active = TRUE
            "#,
        )
        .bind(user_id)
        .fetch_all(db)
        .await
        .map_err(|e| format!("Failed to fetch device tokens: {}", e))?;

        Ok(tokens)
    }

    async fn insert_delivery_log(
        db: &Pool<Postgres>,
        notification_id: Uuid,
        device_token: &str,
        status: &str,
        error: Option<&str>,
    ) -> Result<(), String> {
        sqlx::query(
            r#"
            INSERT INTO notification_delivery_logs (
                notification_id,
                delivery_method,
                device_token,
                status,
                error_message,
                sent_at,
                created_at
            )
            VALUES ($1, 'apns', $2, $3, $4, CASE WHEN $3 = 'sent' THEN NOW() ELSE NULL END, NOW())
            "#,
        )
        .bind(notification_id)
        .bind(device_token)
        .bind(status)
        .bind(error)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to log push delivery: {}", e))?;

        Ok(())
    }

    fn build_push_content(notification: &Notification) -> (String, String) {
        if let Some(message) = notification.message.as_ref() {
            let title = message
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("NovaSocial");
            let body = message
                .get("body")
                .and_then(|v| v.as_str())
                .unwrap_or("You have a new notification");
            return (title.to_string(), body.to_string());
        }

        let title = "NovaSocial";
        let body = match notification.notification_type.as_str() {
            "message" => "You have a new message",
            "reaction" => "Someone reacted to your post",
            "mention" | "mention_post" | "mention_comment" => "You were mentioned",
            "follow" => "You have a new follower",
            "comment" => "Someone commented on your post",
            "like" => "Your content received a like",
            _ => "You have a new notification",
        };

        (title.to_string(), body.to_string())
    }

    pub async fn send_push_notification(
        db: &Pool<Postgres>,
        notification: &Notification,
        apns: Arc<ApnsPush>,
    ) -> Result<(), String> {
        let prefs = Self::get_or_create_preferences(db, notification.recipient_id).await?;
        if !prefs.enable_push_notifications {
            return Ok(());
        }

        let tokens = Self::get_active_device_tokens(db, notification.recipient_id).await?;
        if tokens.is_empty() {
            return Ok(());
        }

        let (title, body) = Self::build_push_content(notification);

        for token in tokens {
            let send_result = apns
                .send_alert(token.clone(), title.clone(), body.clone(), None)
                .await;

            match send_result {
                Ok(_) => {
                    let _ =
                        Self::insert_delivery_log(db, notification.id, &token, "sent", None).await;
                }
                Err(err) => {
                    let _ = Self::insert_delivery_log(
                        db,
                        notification.id,
                        &token,
                        "failed",
                        Some(&format!("{err}")),
                    )
                    .await;
                }
            }
        }

        Ok(())
    }

    /// Get or create notification preferences
    pub async fn get_or_create_preferences(
        db: &Pool<Postgres>,
        user_id: Uuid,
    ) -> Result<NotificationPreferences, String> {
        let prefs = sqlx::query(
            r#"
            SELECT user_id, enable_push_notifications, enable_email_notifications,
                   enable_sms_notifications, notification_frequency,
                   quiet_hours_start, quiet_hours_end
            FROM notification_preferences
            WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_optional(db)
        .await
        .map_err(|e| format!("Failed to fetch preferences: {}", e))?;

        if let Some(row) = prefs {
            Ok(NotificationPreferences {
                user_id: row.get("user_id"),
                enable_push_notifications: row.get("enable_push_notifications"),
                enable_email_notifications: row.get("enable_email_notifications"),
                enable_sms_notifications: row.get("enable_sms_notifications"),
                notification_frequency: row.get("notification_frequency"),
                quiet_hours_start: row.get("quiet_hours_start"),
                quiet_hours_end: row.get("quiet_hours_end"),
            })
        } else {
            // Create default preferences
            sqlx::query(
                r#"
                INSERT INTO notification_preferences (user_id)
                VALUES ($1)
                "#,
            )
            .bind(user_id)
            .execute(db)
            .await
            .map_err(|e| format!("Failed to create preferences: {}", e))?;

            Ok(NotificationPreferences {
                user_id,
                enable_push_notifications: true,
                enable_email_notifications: false,
                enable_sms_notifications: false,
                notification_frequency: "immediate".to_string(),
                quiet_hours_start: None,
                quiet_hours_end: None,
            })
        }
    }

    /// Update notification preferences
    pub async fn update_preferences(
        db: &Pool<Postgres>,
        user_id: Uuid,
        prefs: NotificationPreferences,
    ) -> Result<NotificationPreferences, String> {
        sqlx::query(
            r#"
            UPDATE notification_preferences
            SET enable_push_notifications = $1,
                enable_email_notifications = $2,
                enable_sms_notifications = $3,
                notification_frequency = $4,
                quiet_hours_start = $5,
                quiet_hours_end = $6,
                updated_at = NOW()
            WHERE user_id = $7
            "#,
        )
        .bind(prefs.enable_push_notifications)
        .bind(prefs.enable_email_notifications)
        .bind(prefs.enable_sms_notifications)
        .bind(&prefs.notification_frequency)
        .bind(&prefs.quiet_hours_start)
        .bind(&prefs.quiet_hours_end)
        .bind(user_id)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to update preferences: {}", e))?;

        Ok(prefs)
    }

    /// Subscribe to a notification type
    pub async fn subscribe_to_type(
        db: &Pool<Postgres>,
        user_id: Uuid,
        notification_type: &str,
    ) -> Result<(), String> {
        sqlx::query(
            r#"
            INSERT INTO notification_subscriptions (user_id, notification_type, is_enabled)
            VALUES ($1, $2, TRUE)
            ON CONFLICT (user_id, notification_type) DO UPDATE
            SET is_enabled = TRUE, updated_at = NOW()
            "#,
        )
        .bind(user_id)
        .bind(notification_type)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to subscribe: {}", e))?;

        Ok(())
    }

    /// Unsubscribe from a notification type
    pub async fn unsubscribe_from_type(
        db: &Pool<Postgres>,
        user_id: Uuid,
        notification_type: &str,
    ) -> Result<(), String> {
        sqlx::query(
            r#"
            UPDATE notification_subscriptions
            SET is_enabled = FALSE, updated_at = NOW()
            WHERE user_id = $1 AND notification_type = $2
            "#,
        )
        .bind(user_id)
        .bind(notification_type)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to unsubscribe: {}", e))?;

        Ok(())
    }
}
