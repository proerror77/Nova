// gRPC server for NotificationService
use chrono::{Duration, Utc};
use sqlx::{PgPool, Row};
use std::sync::Arc;
use tonic::{Request, Response, Status};
use tracing::{debug, error, info, warn};
use uuid::Uuid;

pub mod nova {
    pub mod common {
        pub mod v2 {
            tonic::include_proto!("nova.common.v2");
        }
        pub use v2::*;
    }
    pub mod notification_service {
        pub mod v2 {
            tonic::include_proto!("nova.notification_service.v2");
        }
        pub use v2::*;
    }
}

use nova::notification_service::v2::notification_service_server::NotificationService;
use nova::notification_service::v2::*;

use crate::models::{
    CreateNotificationRequest as CoreCreateRequest, NotificationPriority, NotificationType,
};
use crate::services::{NotificationService as CoreNotificationService, PushSender};

#[derive(Clone)]
pub struct NotificationServiceImpl {
    db: PgPool,
    core_service: Arc<CoreNotificationService>,
    push_sender: Arc<PushSender>,
}

impl NotificationServiceImpl {
    pub fn new(
        db: PgPool,
        core_service: Arc<CoreNotificationService>,
        push_sender: Arc<PushSender>,
    ) -> Self {
        Self {
            db,
            core_service,
            push_sender,
        }
    }
}

impl Default for NotificationServiceImpl {
    fn default() -> Self {
        let db = PgPool::connect_lazy("").expect("Failed to create lazy pool");
        let core_service = Arc::new(CoreNotificationService::new(db.clone(), None, None));
        let push_sender = Arc::new(PushSender::new(db.clone(), None, None));

        Self {
            db,
            core_service,
            push_sender,
        }
    }
}

#[tonic::async_trait]
impl NotificationService for NotificationServiceImpl {
    /// Get user's notifications with pagination
    async fn get_notifications(
        &self,
        request: Request<GetNotificationsRequest>,
    ) -> Result<Response<GetNotificationsResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let limit = if req.limit > 0 && req.limit <= 100 {
            req.limit
        } else {
            50
        };
        let offset = req.offset.max(0);

        info!(
            "GetNotifications: user_id={}, limit={}, offset={}, unread_only={}",
            user_id, limit, offset, req.unread_only
        );

        // Build query with optional unread filter
        let query = if req.unread_only {
            r#"
                SELECT id, user_id, title, body, notification_type, data,
                       related_user_id, related_post_id, related_message_id,
                       is_read, read_at, status, channel, created_at, sent_at, deleted_at
                FROM notifications
                WHERE user_id = $1 AND is_deleted = FALSE AND is_read = FALSE
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
            "#
        } else {
            r#"
                SELECT id, user_id, title, body, notification_type, data,
                       related_user_id, related_post_id, related_message_id,
                       is_read, read_at, status, channel, created_at, sent_at, deleted_at
                FROM notifications
                WHERE user_id = $1 AND is_deleted = FALSE
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
            "#
        };

        let rows = sqlx::query(query)
            .bind(user_id)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.db)
            .await
            .map_err(|e| {
                error!("Failed to fetch notifications: {}", e);
                Status::internal(format!("Database error: {}", e))
            })?;

        let mut notifications = Vec::new();
        for row in rows {
            let id: Uuid = row.try_get("id").unwrap_or_default();
            let created_at: chrono::DateTime<Utc> =
                row.try_get("created_at").unwrap_or_else(|_| Utc::now());
            let sent_at: Option<chrono::DateTime<Utc>> = row.try_get("sent_at").ok().flatten();
            let read_at: Option<chrono::DateTime<Utc>> = row.try_get("read_at").ok().flatten();
            let deleted_at: Option<chrono::DateTime<Utc>> =
                row.try_get("deleted_at").ok().flatten();
            let data: Option<serde_json::Value> = row.try_get("data").ok().flatten();

            notifications.push(Notification {
                id: id.to_string(),
                user_id: row
                    .try_get::<Uuid, _>("user_id")
                    .unwrap_or_default()
                    .to_string(),
                notification_type: row
                    .try_get("notification_type")
                    .unwrap_or_else(|_| "system".to_string()),
                title: row.try_get("title").unwrap_or_default(),
                body: row.try_get("body").unwrap_or_default(),
                data: data.map(|d| d.to_string()).unwrap_or_default(),
                related_user_id: row
                    .try_get::<Option<Uuid>, _>("related_user_id")
                    .ok()
                    .flatten()
                    .map(|u| u.to_string())
                    .unwrap_or_default(),
                related_post_id: row
                    .try_get::<Option<Uuid>, _>("related_post_id")
                    .ok()
                    .flatten()
                    .map(|u| u.to_string())
                    .unwrap_or_default(),
                related_message_id: row
                    .try_get::<Option<Uuid>, _>("related_message_id")
                    .ok()
                    .flatten()
                    .map(|u| u.to_string())
                    .unwrap_or_default(),
                is_read: row.try_get("is_read").unwrap_or(false),
                channel: row
                    .try_get("channel")
                    .unwrap_or_else(|_| "in_app".to_string()),
                status: row
                    .try_get("status")
                    .unwrap_or_else(|_| "pending".to_string()),
                created_at: created_at.timestamp(),
                sent_at: sent_at.map(|t| t.timestamp()).unwrap_or(0),
                read_at: read_at.map(|t| t.timestamp()).unwrap_or(0),
                deleted_at: deleted_at.map(|t| t.timestamp()).unwrap_or(0),
            });
        }

        // Get total count
        let count_query = if req.unread_only {
            "SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_deleted = FALSE AND is_read = FALSE"
        } else {
            "SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_deleted = FALSE"
        };

        let total_count: i64 = sqlx::query_scalar(count_query)
            .bind(user_id)
            .fetch_one(&self.db)
            .await
            .unwrap_or(0);

        // Get unread count
        let unread_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_deleted = FALSE AND is_read = FALSE"
        )
            .bind(user_id)
            .fetch_one(&self.db)
            .await
            .unwrap_or(0);

        Ok(Response::new(GetNotificationsResponse {
            notifications,
            total_count: total_count as i32,
            unread_count: unread_count as i32,
        }))
    }

    /// Get single notification by ID
    async fn get_notification(
        &self,
        request: Request<GetNotificationRequest>,
    ) -> Result<Response<GetNotificationResponse>, Status> {
        let req = request.into_inner();

        let notification_id = Uuid::parse_str(&req.notification_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid notification_id: {}", e)))?;

        debug!("GetNotification: notification_id={}", notification_id);

        match self.core_service.get_notification(notification_id).await {
            Ok(Some(notif)) => Ok(Response::new(GetNotificationResponse {
                notification: Some(Notification {
                    id: notif.id.to_string(),
                    user_id: notif.recipient_id.to_string(),
                    notification_type: notif.notification_type.as_str().to_string(),
                    title: notif.title,
                    body: notif.body,
                    data: notif.metadata.map(|d| d.to_string()).unwrap_or_default(),
                    related_user_id: notif.sender_id.map(|u| u.to_string()).unwrap_or_default(),
                    related_post_id: notif.object_id.map(|u| u.to_string()).unwrap_or_default(),
                    related_message_id: String::new(),
                    is_read: notif.is_read,
                    channel: "in_app".to_string(),
                    status: notif.status.as_str().to_string(),
                    created_at: notif.created_at.timestamp(),
                    sent_at: 0,
                    read_at: notif.read_at.map(|t| t.timestamp()).unwrap_or(0),
                    deleted_at: 0,
                }),
            })),
            Ok(None) => Err(Status::not_found("Notification not found")),
            Err(e) => {
                error!("Failed to get notification: {}", e);
                Err(Status::internal(format!(
                    "Failed to get notification: {}",
                    e
                )))
            }
        }
    }

    /// Create a new notification
    async fn create_notification(
        &self,
        request: Request<CreateNotificationRequest>,
    ) -> Result<Response<CreateNotificationResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let related_user_id =
            if !req.related_user_id.is_empty() {
                Some(Uuid::parse_str(&req.related_user_id).map_err(|e| {
                    Status::invalid_argument(format!("Invalid related_user_id: {}", e))
                })?)
            } else {
                None
            };

        let related_post_id =
            if !req.related_post_id.is_empty() {
                Some(Uuid::parse_str(&req.related_post_id).map_err(|e| {
                    Status::invalid_argument(format!("Invalid related_post_id: {}", e))
                })?)
            } else {
                None
            };

        info!(
            "CreateNotification: user_id={}, type={}",
            user_id, req.notification_type
        );

        let notification_type = match req.notification_type.to_lowercase().as_str() {
            "like" => NotificationType::Like,
            "comment" => NotificationType::Comment,
            "follow" => NotificationType::Follow,
            "mention" => NotificationType::Mention,
            "message" => NotificationType::Message,
            "stream" => NotificationType::Stream,
            "video" => NotificationType::Video,
            _ => NotificationType::System,
        };

        let data = if !req.data.is_empty() {
            serde_json::from_str(&req.data).ok()
        } else {
            None
        };

        let core_req = CoreCreateRequest {
            recipient_id: user_id,
            sender_id: related_user_id,
            notification_type,
            title: req.title,
            body: req.body,
            image_url: None,
            object_id: related_post_id,
            object_type: None,
            metadata: data,
            priority: NotificationPriority::Normal,
        };

        match self.core_service.create_notification(core_req).await {
            Ok(notif) => {
                // Send push notifications asynchronously
                let sender = self.push_sender.clone();
                let notif_clone = notif.clone();
                tokio::spawn(async move {
                    if let Err(e) = sender_send_push_for_notification(&sender, &notif_clone).await {
                        warn!("Failed to send push notifications: {}", e);
                    }
                });

                Ok(Response::new(CreateNotificationResponse {
                    notification: Some(Notification {
                        id: notif.id.to_string(),
                        user_id: notif.recipient_id.to_string(),
                        notification_type: notif.notification_type.as_str().to_string(),
                        title: notif.title,
                        body: notif.body,
                        data: notif.metadata.map(|d| d.to_string()).unwrap_or_default(),
                        related_user_id: notif.sender_id.map(|u| u.to_string()).unwrap_or_default(),
                        related_post_id: notif.object_id.map(|u| u.to_string()).unwrap_or_default(),
                        related_message_id: String::new(),
                        is_read: notif.is_read,
                        channel: "in_app".to_string(),
                        status: notif.status.as_str().to_string(),
                        created_at: notif.created_at.timestamp(),
                        sent_at: 0,
                        read_at: notif.read_at.map(|t| t.timestamp()).unwrap_or(0),
                        deleted_at: 0,
                    }),
                }))
            }
            Err(e) => {
                error!("Failed to create notification: {}", e);
                Err(Status::internal(format!(
                    "Failed to create notification: {}",
                    e
                )))
            }
        }
    }

    /// Mark notification as read
    async fn mark_notification_as_read(
        &self,
        request: Request<MarkNotificationAsReadRequest>,
    ) -> Result<Response<MarkNotificationAsReadResponse>, Status> {
        let req = request.into_inner();

        let notification_id = Uuid::parse_str(&req.notification_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid notification_id: {}", e)))?;

        debug!(
            "MarkNotificationAsRead: notification_id={}",
            notification_id
        );

        match self.core_service.mark_as_read(notification_id).await {
            Ok(_) => {
                // Fetch updated notification
                match self.core_service.get_notification(notification_id).await {
                    Ok(Some(notif)) => Ok(Response::new(MarkNotificationAsReadResponse {
                        notification: Some(Notification {
                            id: notif.id.to_string(),
                            user_id: notif.recipient_id.to_string(),
                            notification_type: notif.notification_type.as_str().to_string(),
                            title: notif.title,
                            body: notif.body,
                            data: notif.metadata.map(|d| d.to_string()).unwrap_or_default(),
                            related_user_id: notif
                                .sender_id
                                .map(|u| u.to_string())
                                .unwrap_or_default(),
                            related_post_id: notif
                                .object_id
                                .map(|u| u.to_string())
                                .unwrap_or_default(),
                            related_message_id: String::new(),
                            is_read: notif.is_read,
                            channel: "in_app".to_string(),
                            status: notif.status.as_str().to_string(),
                            created_at: notif.created_at.timestamp(),
                            sent_at: 0,
                            read_at: notif.read_at.map(|t| t.timestamp()).unwrap_or(0),
                            deleted_at: 0,
                        }),
                    })),
                    Ok(None) => Err(Status::not_found(
                        "Notification not found after marking as read",
                    )),
                    Err(e) => Err(Status::internal(format!(
                        "Failed to fetch notification: {}",
                        e
                    ))),
                }
            }
            Err(e) => {
                error!("Failed to mark notification as read: {}", e);
                Err(Status::internal(format!("Failed to mark as read: {}", e)))
            }
        }
    }

    /// Mark all notifications as read
    async fn mark_all_notifications_as_read(
        &self,
        request: Request<MarkAllNotificationsAsReadRequest>,
    ) -> Result<Response<MarkAllNotificationsAsReadResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        info!("MarkAllNotificationsAsRead: user_id={}", user_id);

        let query = r#"
            UPDATE notifications
            SET is_read = TRUE, read_at = NOW(), status = 'read', updated_at = NOW()
            WHERE user_id = $1 AND is_read = FALSE AND is_deleted = FALSE
        "#;

        let result = sqlx::query(query)
            .bind(user_id)
            .execute(&self.db)
            .await
            .map_err(|e| {
                error!("Failed to mark all as read: {}", e);
                Status::internal(format!("Database error: {}", e))
            })?;

        Ok(Response::new(MarkAllNotificationsAsReadResponse {
            marked_count: result.rows_affected() as i32,
        }))
    }

    /// Delete notification (soft delete)
    async fn delete_notification(
        &self,
        request: Request<DeleteNotificationRequest>,
    ) -> Result<Response<DeleteNotificationResponse>, Status> {
        let req = request.into_inner();

        let notification_id = Uuid::parse_str(&req.notification_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid notification_id: {}", e)))?;

        debug!("DeleteNotification: notification_id={}", notification_id);

        let query = r#"
            UPDATE notifications
            SET is_deleted = TRUE, deleted_at = NOW(), updated_at = NOW()
            WHERE id = $1
        "#;

        sqlx::query(query)
            .bind(notification_id)
            .execute(&self.db)
            .await
            .map_err(|e| {
                error!("Failed to delete notification: {}", e);
                Status::internal(format!("Database error: {}", e))
            })?;

        Ok(Response::new(DeleteNotificationResponse { success: true }))
    }

    /// Get user's notification preferences
    async fn get_notification_preferences(
        &self,
        request: Request<GetNotificationPreferencesRequest>,
    ) -> Result<Response<GetNotificationPreferencesResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        debug!("GetNotificationPreferences: user_id={}", user_id);

        match self.core_service.get_preferences(user_id).await {
            Ok(pref) => Ok(Response::new(GetNotificationPreferencesResponse {
                preferences: Some(NotificationPreference {
                    user_id: pref.user_id.to_string(),
                    email_on_like: pref.like_enabled,
                    email_on_comment: pref.comment_enabled,
                    email_on_follow: pref.follow_enabled,
                    email_on_mention: pref.mention_enabled,
                    push_on_like: pref.like_enabled,
                    push_on_comment: pref.comment_enabled,
                    push_on_follow: pref.follow_enabled,
                    push_on_mention: pref.mention_enabled,
                    push_on_message: pref.message_enabled,
                    quiet_hours_start: pref.quiet_hours_start.unwrap_or_default(),
                    quiet_hours_end: pref.quiet_hours_end.unwrap_or_default(),
                    disable_all: !pref.enabled,
                    created_at: 0,
                    updated_at: pref.updated_at.timestamp(),
                }),
            })),
            Err(e) => {
                error!("Failed to get preferences: {}", e);
                Err(Status::internal(format!(
                    "Failed to get preferences: {}",
                    e
                )))
            }
        }
    }

    /// Update user's notification preferences
    async fn update_notification_preferences(
        &self,
        _request: Request<UpdateNotificationPreferencesRequest>,
    ) -> Result<Response<UpdateNotificationPreferencesResponse>, Status> {
        // TODO: Implement preferences update
        Err(Status::unimplemented(
            "update_notification_preferences is not implemented yet",
        ))
    }

    /// Register push token
    async fn register_push_token(
        &self,
        request: Request<RegisterPushTokenRequest>,
    ) -> Result<Response<RegisterPushTokenResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        info!(
            "RegisterPushToken: user_id={}, platform={}",
            user_id, req.platform
        );

        let token_type = match req.platform.to_lowercase().as_str() {
            "ios" => "APNs",
            "android" | "web" => "FCM",
            _ => "FCM",
        };

        let query = r#"
            INSERT INTO push_tokens (user_id, token, token_type, device_id, platform, app_version, is_valid, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, TRUE, NOW(), NOW())
            ON CONFLICT (user_id, token, token_type) DO UPDATE
            SET is_valid = TRUE, updated_at = NOW(), last_used_at = NOW()
            RETURNING id, user_id, token, token_type, device_id, platform, app_version, is_valid, created_at, last_used_at
        "#;

        let row = sqlx::query(query)
            .bind(user_id)
            .bind(&req.token)
            .bind(token_type)
            .bind(&req.device_id)
            .bind(&req.platform)
            .bind(&req.app_version)
            .fetch_one(&self.db)
            .await
            .map_err(|e| {
                error!("Failed to register push token: {}", e);
                Status::internal(format!("Database error: {}", e))
            })?;

        let id: Uuid = row.try_get("id").unwrap_or_default();
        let created_at: chrono::DateTime<Utc> =
            row.try_get("created_at").unwrap_or_else(|_| Utc::now());
        let last_used_at: Option<chrono::DateTime<Utc>> =
            row.try_get("last_used_at").ok().flatten();

        Ok(Response::new(RegisterPushTokenResponse {
            push_token: Some(PushToken {
                id: id.to_string(),
                user_id: user_id.to_string(),
                device_id: req.device_id,
                token: req.token,
                platform: req.platform,
                app_version: req.app_version,
                is_active: true,
                created_at: created_at.timestamp(),
                last_used_at: last_used_at.map(|t| t.timestamp()).unwrap_or(0),
            }),
        }))
    }

    /// Unregister push token
    async fn unregister_push_token(
        &self,
        request: Request<UnregisterPushTokenRequest>,
    ) -> Result<Response<UnregisterPushTokenResponse>, Status> {
        let req = request.into_inner();

        debug!("UnregisterPushToken: token={}", req.token);

        let query = r#"
            UPDATE push_tokens
            SET is_valid = FALSE, updated_at = NOW()
            WHERE token = $1
        "#;

        sqlx::query(query)
            .bind(&req.token)
            .execute(&self.db)
            .await
            .map_err(|e| {
                error!("Failed to unregister push token: {}", e);
                Status::internal(format!("Database error: {}", e))
            })?;

        Ok(Response::new(UnregisterPushTokenResponse { success: true }))
    }

    /// Get unread count
    async fn get_unread_count(
        &self,
        request: Request<GetUnreadCountRequest>,
    ) -> Result<Response<GetUnreadCountResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_deleted = FALSE AND is_read = FALSE"
        )
            .bind(user_id)
            .fetch_one(&self.db)
            .await
            .unwrap_or(0);

        Ok(Response::new(GetUnreadCountResponse {
            unread_count: count as i32,
        }))
    }

    /// Batch create notifications
    async fn batch_create_notifications(
        &self,
        _request: Request<BatchCreateNotificationsRequest>,
    ) -> Result<Response<BatchCreateNotificationsResponse>, Status> {
        // TODO: Implement batch create
        Err(Status::unimplemented(
            "batch_create_notifications is not implemented yet",
        ))
    }

    /// Get notification statistics
    async fn get_notification_stats(
        &self,
        request: Request<GetNotificationStatsRequest>,
    ) -> Result<Response<GetNotificationStatsResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        debug!("GetNotificationStats: user_id={}", user_id);

        let total_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_deleted = FALSE",
        )
        .bind(user_id)
        .fetch_one(&self.db)
        .await
        .unwrap_or(0);

        let unread_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_deleted = FALSE AND is_read = FALSE"
        )
            .bind(user_id)
            .fetch_one(&self.db)
            .await
            .unwrap_or(0);

        let today = Utc::now().date_naive();
        let today_start = today.and_hms_opt(0, 0, 0).expect("Valid time: 00:00:00");

        let today_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_deleted = FALSE AND created_at >= $2"
        )
            .bind(user_id)
            .bind(today_start)
            .fetch_one(&self.db)
            .await
            .unwrap_or(0);

        let week_ago = Utc::now() - Duration::days(7);
        let this_week_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_deleted = FALSE AND created_at >= $2"
        )
            .bind(user_id)
            .bind(week_ago)
            .fetch_one(&self.db)
            .await
            .unwrap_or(0);

        Ok(Response::new(GetNotificationStatsResponse {
            total_count: total_count as i32,
            unread_count: unread_count as i32,
            today_count: today_count as i32,
            this_week_count: this_week_count as i32,
        }))
    }
}

/// Helper function to send push notifications for a notification
async fn sender_send_push_for_notification(
    _sender: &PushSender,
    notif: &crate::models::Notification,
) -> Result<(), String> {
    // Get user's push tokens from database
    // For now, this is a placeholder. In production, you would:
    // 1. Query push_tokens table
    // 2. Create PushRequest for each token
    // 3. Call sender.send_batch()

    info!("Sending push notifications for notification {}", notif.id);
    Ok(())
}
