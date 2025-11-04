use serde::Deserialize;
use uuid::Uuid;

use crate::{
    error::AppError,
    middleware::guards::User,
    services::notification_service::{CreateNotificationRequest, NotificationService},
    state::AppState,
};
use actix_web::{web, HttpResponse};

#[derive(Debug, Deserialize)]
pub struct GetNotificationsQuery {
    #[serde(default = "default_limit")]
    limit: i64,
    #[serde(default)]
    offset: i64,
}

fn default_limit() -> i64 {
    20
}

#[derive(Debug, Deserialize)]
pub struct CreateNotificationPayload {
    recipient_id: Uuid,
    actor_id: Uuid,
    notification_type: String,
    action_type: Option<String>,
    target_type: Option<String>,
    target_id: Option<Uuid>,
    message: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
pub struct UpdatePreferencesPayload {
    enable_push_notifications: Option<bool>,
    enable_email_notifications: Option<bool>,
    enable_sms_notifications: Option<bool>,
    notification_frequency: Option<String>,
    quiet_hours_start: Option<String>,
    quiet_hours_end: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct SubscribePayload {
    pub notification_type: String,
}

#[derive(Debug, Deserialize)]
pub struct RegisterDeviceTokenPayload {
    #[serde(rename = "device_token")]
    device_token: String,
    #[serde(default = "default_platform", rename = "device_platform")]
    device_platform: String,
    #[serde(rename = "app_version")]
    app_version: Option<String>,
    locale: Option<String>,
}

fn default_platform() -> String {
    "ios".to_string()
}

/// GET /api/notifications
/// Get user's notifications with pagination
pub async fn get_notifications(
    state: web::Data<AppState>,
    user_id: web::Path<Uuid>,
    params: web::Query<GetNotificationsQuery>,
) -> Result<HttpResponse, AppError> {
    let user_id = user_id.into_inner();
    let result =
        NotificationService::get_notifications(&state.db, user_id, params.limit, params.offset)
            .await
            .map_err(|e| AppError::BadRequest(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "notifications": result.notifications,
        "total": result.total,
        "unread_count": result.unread_count,
        "limit": params.limit,
        "offset": params.offset
    })))
}

/// GET /api/notifications/unread
/// Get only unread notifications for user
pub async fn get_unread_notifications(
    state: web::Data<AppState>,
    user_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let user_id = user_id.into_inner();
    let notifications = NotificationService::get_unread_notifications(&state.db, user_id, 50)
        .await
        .map_err(|e| AppError::BadRequest(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "notifications": notifications,
        "count": notifications.len()
    })))
}

/// POST /api/notifications
/// Create a new notification
pub async fn create_notification(
    state: web::Data<AppState>,
    payload: web::Json<CreateNotificationPayload>,
) -> Result<HttpResponse, AppError> {
    let request = CreateNotificationRequest {
        recipient_id: payload.recipient_id,
        actor_id: payload.actor_id,
        notification_type: payload.notification_type.clone(),
        action_type: payload.action_type.clone(),
        target_type: payload.target_type.clone(),
        target_id: payload.target_id,
        message: payload.message.clone(),
    };

    let notification = NotificationService::create_notification(&state.db, request)
        .await
        .map_err(|e| AppError::BadRequest(e))?;

    if let Some(apns) = state.apns.clone() {
        let db = state.db.clone();
        let notification_clone = notification.clone();
        tokio::spawn(async move {
            if let Err(err) =
                NotificationService::send_push_notification(&db, &notification_clone, apns).await
            {
                tracing::warn!(error = %err, "failed to deliver APNs notification");
            }
        });
    }

    Ok(HttpResponse::Created().json(serde_json::json!({
        "id": notification.id,
        "recipient_id": notification.recipient_id,
        "actor_id": notification.actor_id,
        "notification_type": notification.notification_type,
        "is_read": notification.is_read,
        "created_at": notification.created_at
    })))
}

/// PUT /api/notifications/:notification_id/read
/// Mark a notification as read
pub async fn mark_notification_read(
    state: web::Data<AppState>,
    notification_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let notification_id = notification_id.into_inner();
    NotificationService::mark_as_read(&state.db, notification_id)
        .await
        .map_err(|e| AppError::BadRequest(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "message": "Notification marked as read"
    })))
}

/// POST /api/notifications/device-tokens
/// Register or update a device token for push notifications
pub async fn register_device_token(
    state: web::Data<AppState>,
    user: User,
    payload: web::Json<RegisterDeviceTokenPayload>,
) -> Result<HttpResponse, AppError> {
    NotificationService::register_device_token(
        &state.db,
        user.id,
        &payload.device_token,
        &payload.device_platform,
        payload.app_version.as_deref(),
        payload.locale.as_deref(),
    )
    .await
    .map_err(AppError::BadRequest)?;

    Ok(HttpResponse::Created().finish())
}

/// DELETE /api/notifications/device-tokens/:token
/// Deactivate a device token
pub async fn unregister_device_token(
    state: web::Data<AppState>,
    user: User,
    device_token: web::Path<String>,
) -> Result<HttpResponse, AppError> {
    NotificationService::unregister_device_token(&state.db, user.id, &device_token)
        .await
        .map_err(AppError::BadRequest)?;

    Ok(HttpResponse::NoContent().finish())
}

/// PUT /api/notifications/mark-all-read
/// Mark all notifications as read for user
pub async fn mark_all_read(
    state: web::Data<AppState>,
    user_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let user_id = user_id.into_inner();
    let count = NotificationService::mark_all_as_read(&state.db, user_id)
        .await
        .map_err(|e| AppError::BadRequest(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "message": "All notifications marked as read",
        "count": count
    })))
}

/// DELETE /api/notifications/:notification_id
/// Delete a notification
pub async fn delete_notification(
    state: web::Data<AppState>,
    notification_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let notification_id = notification_id.into_inner();
    NotificationService::delete_notification(&state.db, notification_id)
        .await
        .map_err(|e| AppError::BadRequest(e))?;

    Ok(HttpResponse::NoContent().finish())
}

/// GET /api/notifications/preferences
/// Get notification preferences for user
pub async fn get_preferences(
    state: web::Data<AppState>,
    user_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let user_id = user_id.into_inner();
    let prefs = NotificationService::get_or_create_preferences(&state.db, user_id)
        .await
        .map_err(|e| AppError::BadRequest(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "user_id": prefs.user_id,
        "enable_push_notifications": prefs.enable_push_notifications,
        "enable_email_notifications": prefs.enable_email_notifications,
        "enable_sms_notifications": prefs.enable_sms_notifications,
        "notification_frequency": prefs.notification_frequency,
        "quiet_hours_start": prefs.quiet_hours_start,
        "quiet_hours_end": prefs.quiet_hours_end
    })))
}

/// PUT /api/notifications/preferences
/// Update notification preferences for user
pub async fn update_preferences(
    state: web::Data<AppState>,
    user_id: web::Path<Uuid>,
    payload: web::Json<UpdatePreferencesPayload>,
) -> Result<HttpResponse, AppError> {
    let user_id = user_id.into_inner();
    let mut prefs = NotificationService::get_or_create_preferences(&state.db, user_id)
        .await
        .map_err(|e| AppError::BadRequest(e))?;

    if let Some(push) = payload.enable_push_notifications {
        prefs.enable_push_notifications = push;
    }
    if let Some(email) = payload.enable_email_notifications {
        prefs.enable_email_notifications = email;
    }
    if let Some(sms) = payload.enable_sms_notifications {
        prefs.enable_sms_notifications = sms;
    }
    if let Some(freq) = payload.notification_frequency.clone() {
        prefs.notification_frequency = freq;
    }
    if let Some(start) = payload.quiet_hours_start.clone() {
        prefs.quiet_hours_start = Some(start);
    }
    if let Some(end) = payload.quiet_hours_end.clone() {
        prefs.quiet_hours_end = Some(end);
    }

    let updated = NotificationService::update_preferences(&state.db, user_id, prefs)
        .await
        .map_err(|e| AppError::BadRequest(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "user_id": updated.user_id,
        "enable_push_notifications": updated.enable_push_notifications,
        "enable_email_notifications": updated.enable_email_notifications,
        "enable_sms_notifications": updated.enable_sms_notifications,
        "notification_frequency": updated.notification_frequency,
        "quiet_hours_start": updated.quiet_hours_start,
        "quiet_hours_end": updated.quiet_hours_end
    })))
}

/// POST /api/notifications/subscribe/:notification_type
/// Subscribe to a notification type
pub async fn subscribe(
    state: web::Data<AppState>,
    path: web::Path<(Uuid, String)>,
) -> Result<HttpResponse, AppError> {
    let (user_id, notification_type) = path.into_inner();
    NotificationService::subscribe_to_type(&state.db, user_id, &notification_type)
        .await
        .map_err(|e| AppError::BadRequest(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "message": format!("Subscribed to {}", notification_type)
    })))
}

/// POST /api/notifications/unsubscribe/:notification_type
/// Unsubscribe from a notification type
pub async fn unsubscribe(
    state: web::Data<AppState>,
    path: web::Path<(Uuid, String)>,
) -> Result<HttpResponse, AppError> {
    let (user_id, notification_type) = path.into_inner();
    NotificationService::unsubscribe_from_type(&state.db, user_id, &notification_type)
        .await
        .map_err(|e| AppError::BadRequest(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "message": format!("Unsubscribed from {}", notification_type)
    })))
}
