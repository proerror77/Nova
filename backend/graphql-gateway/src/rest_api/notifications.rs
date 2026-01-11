//! Notifications API endpoints
//!
//! GET /api/v2/notifications - Get notifications for current user
//! GET /api/v2/notifications/{id} - Get single notification
//! POST /api/v2/notifications - Create notification
//! POST /api/v2/notifications/{id}/read - Mark notification as read
//! POST /api/v2/notifications/read-all - Mark all notifications as read
//! DELETE /api/v2/notifications/{id} - Delete notification
//! GET /api/v2/notifications/unread-count - Get unread count
//! GET /api/v2/notifications/stats - Get notification statistics
//! GET /api/v2/notifications/preferences - Get notification preferences
//! PUT /api/v2/notifications/preferences - Update notification preferences
//! POST /api/v2/notifications/push-token - Register push token
//! DELETE /api/v2/notifications/push-token/{token} - Unregister push token
//! POST /api/v2/notifications/batch - Batch create notifications

#![allow(dead_code)]

use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{error, info, warn};

use crate::clients::proto::auth::GetUserProfilesByIdsRequest;

use super::models::ErrorResponse;
use crate::clients::proto::notification::{
    BatchCreateNotificationsRequest, CreateNotificationRequest, DeleteNotificationRequest,
    GetNotificationPreferencesRequest, GetNotificationRequest, GetNotificationStatsRequest,
    GetNotificationsRequest, GetUnreadCountRequest, MarkAllNotificationsAsReadRequest,
    MarkNotificationAsReadRequest, RegisterPushTokenRequest, UnregisterPushTokenRequest,
    UpdateNotificationPreferencesRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

// ============================================================================
// Response Types
// ============================================================================

/// REST API response for notification (iOS compatible)
#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct NotificationResponse {
    pub id: String,
    #[serde(rename = "type")]
    pub notification_type: String,
    pub message: String,
    pub created_at: i64,
    pub is_read: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub related_user_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub related_post_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub related_comment_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_avatar_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub post_thumbnail_url: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct GetNotificationsResponse {
    pub notifications: Vec<NotificationResponse>,
    pub total_count: i32,
    pub unread_count: i32,
    pub has_more: bool,
}

#[derive(Debug, Serialize)]
pub struct MarkReadResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub marked_count: Option<i32>,
}

#[derive(Debug, Serialize)]
pub struct SuccessResponse {
    pub success: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct UnreadCountResponse {
    pub unread_count: i32,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct NotificationStatsResponse {
    pub total_count: i32,
    pub unread_count: i32,
    pub today_count: i32,
    pub week_count: i32,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct NotificationPreferencesResponse {
    pub in_app_enabled: bool,
    pub push_enabled: bool,
    pub email_enabled: bool,
    pub sms_enabled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quiet_hours_start: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quiet_hours_end: Option<i32>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct BatchNotificationResponse {
    pub success_count: i32,
    pub failure_count: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub errors: Option<Vec<String>>,
}

// ============================================================================
// Request Types
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct NotificationQueryParams {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
    pub unread_only: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateNotificationPayload {
    pub user_id: String,
    #[serde(rename = "type")]
    pub notification_type: String,
    pub title: String,
    pub body: String,
    #[serde(default)]
    pub channels: Vec<String>,
    pub related_user_id: Option<String>,
    pub related_post_id: Option<String>,
    pub related_message_id: Option<String>,
    pub data: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdatePreferencesPayload {
    pub in_app_enabled: Option<bool>,
    pub push_enabled: Option<bool>,
    pub email_enabled: Option<bool>,
    pub sms_enabled: Option<bool>,
    pub quiet_hours_start: Option<i32>,
    pub quiet_hours_end: Option<i32>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterPushTokenPayload {
    pub token: String,
    pub platform: String,
    pub device_id: String,
    pub app_version: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchNotificationPayload {
    pub notifications: Vec<BatchNotificationItem>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchNotificationItem {
    pub user_id: String,
    #[serde(rename = "type")]
    pub notification_type: String,
    pub title: String,
    pub body: String,
    #[serde(default)]
    pub channels: Vec<String>,
    pub related_user_id: Option<String>,
    pub related_post_id: Option<String>,
    pub data: Option<String>,
}

// ============================================================================
// Helper Functions
// ============================================================================

/// User info for notification enrichment
#[derive(Debug, Clone)]
struct UserInfo {
    display_name: Option<String>,
    avatar_url: Option<String>,
}

/// Batch fetch user profiles for notification enrichment
async fn fetch_user_profiles(
    clients: &ServiceClients,
    user_ids: Vec<String>,
) -> HashMap<String, UserInfo> {
    if user_ids.is_empty() {
        return HashMap::new();
    }

    let mut auth_client = clients.auth_client();
    let request = tonic::Request::new(GetUserProfilesByIdsRequest { user_ids });

    match auth_client.get_user_profiles_by_ids(request).await {
        Ok(response) => {
            let profiles = response.into_inner().profiles;
            profiles
                .into_iter()
                .map(|p| {
                    // Use display_name if available, otherwise username
                    let display_name = p.display_name.clone().or_else(|| {
                        if !p.username.is_empty() {
                            Some(p.username.clone())
                        } else {
                            None
                        }
                    });

                    (
                        p.user_id.clone(),
                        UserInfo {
                            display_name,
                            avatar_url: p.avatar_url,
                        },
                    )
                })
                .collect()
        }
        Err(status) => {
            warn!(
                error = %status,
                "Failed to fetch user profiles for notification enrichment"
            );
            HashMap::new()
        }
    }
}

fn convert_notification(
    n: crate::clients::proto::notification::Notification,
    user_profiles: &HashMap<String, UserInfo>,
) -> NotificationResponse {
    // Combine title and body into message, or use body if title is empty
    let message = if n.title.is_empty() {
        n.body
    } else if n.body.is_empty() {
        n.title
    } else {
        format!("{}: {}", n.title, n.body)
    };

    // Get user info from pre-fetched profiles
    let user_info = if !n.related_user_id.is_empty() {
        user_profiles.get(&n.related_user_id)
    } else {
        None
    };

    NotificationResponse {
        id: n.id,
        notification_type: n.notification_type,
        message,
        created_at: n.created_at,
        is_read: n.is_read,
        related_user_id: if n.related_user_id.is_empty() {
            None
        } else {
            Some(n.related_user_id)
        },
        related_post_id: if n.related_post_id.is_empty() {
            None
        } else {
            Some(n.related_post_id)
        },
        related_comment_id: None, // Not in gRPC response yet
        user_name: user_info.and_then(|u| u.display_name.clone()),
        user_avatar_url: user_info.and_then(|u| u.avatar_url.clone()),
        post_thumbnail_url: None, // TODO: Join with content data if needed
    }
}

fn handle_grpc_error(status: tonic::Status, context: &str) -> HttpResponse {
    match status.code() {
        tonic::Code::NotFound => HttpResponse::NotFound().json(ErrorResponse::new("Not found")),
        tonic::Code::Unauthenticated => {
            HttpResponse::Unauthorized().json(ErrorResponse::new("Unauthorized"))
        }
        tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
            ErrorResponse::with_message("Invalid request", status.message()),
        ),
        _ => HttpResponse::InternalServerError()
            .json(ErrorResponse::with_message(context, status.message())),
    }
}

// ============================================================================
// GET /api/v2/notifications
// ============================================================================

/// GET /api/v2/notifications
/// Returns notifications for the authenticated user
pub async fn get_notifications(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<NotificationQueryParams>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let limit = query.limit.unwrap_or(20).min(100);
    let offset = query.offset.unwrap_or(0);
    let unread_only = query.unread_only.unwrap_or(false);

    info!(
        user_id = %user_id,
        limit = %limit,
        offset = %offset,
        unread_only = %unread_only,
        "GET /api/v2/notifications"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(GetNotificationsRequest {
        user_id: user_id.clone(),
        limit,
        offset,
        unread_only,
    });

    match notification_client.get_notifications(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();
            let notification_count = grpc_response.notifications.len() as i32;

            // Collect unique related_user_ids for batch profile lookup
            let related_user_ids: Vec<String> = grpc_response
                .notifications
                .iter()
                .filter_map(|n| {
                    if n.related_user_id.is_empty() {
                        None
                    } else {
                        Some(n.related_user_id.clone())
                    }
                })
                .collect::<std::collections::HashSet<_>>()
                .into_iter()
                .collect();

            // Batch fetch user profiles for enrichment
            let user_profiles = fetch_user_profiles(&clients, related_user_ids).await;

            let notifications = grpc_response
                .notifications
                .into_iter()
                .map(|n| convert_notification(n, &user_profiles))
                .collect();

            let has_more = notification_count >= limit;

            info!(
                user_id = %user_id,
                total_count = grpc_response.total_count,
                unread_count = grpc_response.unread_count,
                "Notifications retrieved successfully"
            );

            Ok(HttpResponse::Ok().json(GetNotificationsResponse {
                notifications,
                total_count: grpc_response.total_count,
                unread_count: grpc_response.unread_count,
                has_more,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get notifications"
            );
            Ok(handle_grpc_error(status, "Failed to get notifications"))
        }
    }
}

// ============================================================================
// GET /api/v2/notifications/{id}
// ============================================================================

/// GET /api/v2/notifications/{id}
/// Get a single notification by ID
pub async fn get_notification(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let _user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let notification_id = path.into_inner();

    info!(
        notification_id = %notification_id,
        "GET /api/v2/notifications/{{id}}"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(GetNotificationRequest {
        notification_id: notification_id.clone(),
    });

    match notification_client.get_notification(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();
            if let Some(notification) = grpc_response.notification {
                // Fetch user profile if related_user_id exists
                let user_profiles = if !notification.related_user_id.is_empty() {
                    fetch_user_profiles(&clients, vec![notification.related_user_id.clone()]).await
                } else {
                    HashMap::new()
                };
                Ok(HttpResponse::Ok().json(convert_notification(notification, &user_profiles)))
            } else {
                Ok(HttpResponse::NotFound().json(ErrorResponse::new("Notification not found")))
            }
        }
        Err(status) => {
            error!(
                notification_id = %notification_id,
                error = %status,
                "Failed to get notification"
            );
            Ok(handle_grpc_error(status, "Failed to get notification"))
        }
    }
}

// ============================================================================
// POST /api/v2/notifications
// ============================================================================

/// POST /api/v2/notifications
/// Create a new notification
pub async fn create_notification(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    payload: web::Json<CreateNotificationPayload>,
) -> Result<HttpResponse> {
    let _auth_user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    info!(
        user_id = %payload.user_id,
        notification_type = %payload.notification_type,
        "POST /api/v2/notifications"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(CreateNotificationRequest {
        user_id: payload.user_id.clone(),
        notification_type: payload.notification_type.clone(),
        title: payload.title.clone(),
        body: payload.body.clone(),
        data: payload.data.clone().unwrap_or_default(),
        related_user_id: payload.related_user_id.clone().unwrap_or_default(),
        related_post_id: payload.related_post_id.clone().unwrap_or_default(),
        related_message_id: payload.related_message_id.clone().unwrap_or_default(),
        channels: payload.channels.clone(),
    });

    match notification_client.create_notification(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();
            if let Some(notification) = grpc_response.notification {
                // Fetch user profile if related_user_id exists
                let user_profiles = if !notification.related_user_id.is_empty() {
                    fetch_user_profiles(&clients, vec![notification.related_user_id.clone()]).await
                } else {
                    HashMap::new()
                };
                Ok(
                    HttpResponse::Created()
                        .json(convert_notification(notification, &user_profiles)),
                )
            } else {
                Ok(HttpResponse::InternalServerError()
                    .json(ErrorResponse::new("Failed to create notification")))
            }
        }
        Err(status) => {
            error!(
                error = %status,
                "Failed to create notification"
            );
            Ok(handle_grpc_error(status, "Failed to create notification"))
        }
    }
}

// ============================================================================
// POST /api/v2/notifications/{id}/read
// ============================================================================

/// POST /api/v2/notifications/{id}/read
/// Mark a single notification as read
pub async fn mark_notification_read(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let notification_id = path.into_inner();

    info!(
        user_id = %user_id,
        notification_id = %notification_id,
        "POST /api/v2/notifications/{{id}}/read"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(MarkNotificationAsReadRequest {
        notification_id: notification_id.clone(),
    });

    match notification_client
        .mark_notification_as_read(grpc_request)
        .await
    {
        Ok(_response) => {
            info!(
                user_id = %user_id,
                notification_id = %notification_id,
                "Notification marked as read"
            );

            Ok(HttpResponse::Ok().json(MarkReadResponse {
                success: true,
                marked_count: Some(1),
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                notification_id = %notification_id,
                error = %status,
                "Failed to mark notification as read"
            );
            Ok(handle_grpc_error(
                status,
                "Failed to mark notification as read",
            ))
        }
    }
}

// ============================================================================
// POST /api/v2/notifications/read-all
// ============================================================================

/// POST /api/v2/notifications/read-all
/// Mark all notifications as read for the user
pub async fn mark_all_notifications_read(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    info!(
        user_id = %user_id,
        "POST /api/v2/notifications/read-all"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(MarkAllNotificationsAsReadRequest {
        user_id: user_id.clone(),
    });

    match notification_client
        .mark_all_notifications_as_read(grpc_request)
        .await
    {
        Ok(response) => {
            let grpc_response = response.into_inner();

            info!(
                user_id = %user_id,
                marked_count = grpc_response.marked_count,
                "All notifications marked as read"
            );

            Ok(HttpResponse::Ok().json(MarkReadResponse {
                success: true,
                marked_count: Some(grpc_response.marked_count),
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to mark all notifications as read"
            );
            Ok(handle_grpc_error(
                status,
                "Failed to mark all notifications as read",
            ))
        }
    }
}

// ============================================================================
// DELETE /api/v2/notifications/{id}
// ============================================================================

/// DELETE /api/v2/notifications/{id}
/// Delete a notification
pub async fn delete_notification(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let notification_id = path.into_inner();

    info!(
        user_id = %user_id,
        notification_id = %notification_id,
        "DELETE /api/v2/notifications/{{id}}"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(DeleteNotificationRequest {
        notification_id: notification_id.clone(),
    });

    match notification_client.delete_notification(grpc_request).await {
        Ok(_response) => {
            info!(
                user_id = %user_id,
                notification_id = %notification_id,
                "Notification deleted"
            );

            Ok(HttpResponse::Ok().json(SuccessResponse { success: true }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                notification_id = %notification_id,
                error = %status,
                "Failed to delete notification"
            );
            Ok(handle_grpc_error(status, "Failed to delete notification"))
        }
    }
}

// ============================================================================
// GET /api/v2/notifications/unread-count
// ============================================================================

/// GET /api/v2/notifications/unread-count
/// Get the count of unread notifications
pub async fn get_unread_count(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    info!(
        user_id = %user_id,
        "GET /api/v2/notifications/unread-count"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(GetUnreadCountRequest {
        user_id: user_id.clone(),
    });

    match notification_client.get_unread_count(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            Ok(HttpResponse::Ok().json(UnreadCountResponse {
                unread_count: grpc_response.unread_count,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get unread count"
            );
            Ok(handle_grpc_error(status, "Failed to get unread count"))
        }
    }
}

// ============================================================================
// GET /api/v2/notifications/stats
// ============================================================================

/// GET /api/v2/notifications/stats
/// Get notification statistics
pub async fn get_notification_stats(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    info!(
        user_id = %user_id,
        "GET /api/v2/notifications/stats"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(GetNotificationStatsRequest {
        user_id: user_id.clone(),
    });

    match notification_client
        .get_notification_stats(grpc_request)
        .await
    {
        Ok(response) => {
            let grpc_response = response.into_inner();

            Ok(HttpResponse::Ok().json(NotificationStatsResponse {
                total_count: grpc_response.total_count,
                unread_count: grpc_response.unread_count,
                today_count: grpc_response.today_count,
                week_count: grpc_response.this_week_count,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get notification stats"
            );
            Ok(handle_grpc_error(
                status,
                "Failed to get notification stats",
            ))
        }
    }
}

// ============================================================================
// GET /api/v2/notifications/preferences
// ============================================================================

/// GET /api/v2/notifications/preferences
/// Get user's notification preferences
pub async fn get_notification_preferences(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    info!(
        user_id = %user_id,
        "GET /api/v2/notifications/preferences"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(GetNotificationPreferencesRequest {
        user_id: user_id.clone(),
    });

    match notification_client
        .get_notification_preferences(grpc_request)
        .await
    {
        Ok(response) => {
            let grpc_response = response.into_inner();

            if let Some(prefs) = grpc_response.preferences {
                // Convert gRPC preferences to REST response
                // Map the detailed preferences to simplified iOS model
                let in_app_enabled = !prefs.disable_all;
                let push_enabled = prefs.push_on_like
                    || prefs.push_on_comment
                    || prefs.push_on_follow
                    || prefs.push_on_mention
                    || prefs.push_on_message;
                let email_enabled = prefs.email_on_like
                    || prefs.email_on_comment
                    || prefs.email_on_follow
                    || prefs.email_on_mention;

                // Parse quiet hours (HH:MM format) to hour integers
                let quiet_hours_start = prefs
                    .quiet_hours_start
                    .split(':')
                    .next()
                    .and_then(|h| h.parse::<i32>().ok());
                let quiet_hours_end = prefs
                    .quiet_hours_end
                    .split(':')
                    .next()
                    .and_then(|h| h.parse::<i32>().ok());

                Ok(HttpResponse::Ok().json(NotificationPreferencesResponse {
                    in_app_enabled,
                    push_enabled,
                    email_enabled,
                    sms_enabled: false, // Not supported yet
                    quiet_hours_start,
                    quiet_hours_end,
                }))
            } else {
                // Return default preferences
                Ok(HttpResponse::Ok().json(NotificationPreferencesResponse {
                    in_app_enabled: true,
                    push_enabled: true,
                    email_enabled: true,
                    sms_enabled: false,
                    quiet_hours_start: None,
                    quiet_hours_end: None,
                }))
            }
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get notification preferences"
            );
            Ok(handle_grpc_error(
                status,
                "Failed to get notification preferences",
            ))
        }
    }
}

// ============================================================================
// PUT /api/v2/notifications/preferences
// ============================================================================

/// PUT /api/v2/notifications/preferences
/// Update user's notification preferences
pub async fn update_notification_preferences(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    payload: web::Json<UpdatePreferencesPayload>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    info!(
        user_id = %user_id,
        "PUT /api/v2/notifications/preferences"
    );

    let mut notification_client = clients.notification_client();

    // Map simplified preferences to detailed gRPC request
    let push_enabled = payload.push_enabled.unwrap_or(true);
    let email_enabled = payload.email_enabled.unwrap_or(true);
    let disable_all = payload.in_app_enabled.map(|v| !v).unwrap_or(false);

    // Convert quiet hours to HH:MM format
    let quiet_hours_start = payload
        .quiet_hours_start
        .map(|h| format!("{:02}:00", h))
        .unwrap_or_default();
    let quiet_hours_end = payload
        .quiet_hours_end
        .map(|h| format!("{:02}:00", h))
        .unwrap_or_default();

    let grpc_request = tonic::Request::new(UpdateNotificationPreferencesRequest {
        user_id: user_id.clone(),
        email_on_like: email_enabled,
        email_on_comment: email_enabled,
        email_on_follow: email_enabled,
        email_on_mention: email_enabled,
        push_on_like: push_enabled,
        push_on_comment: push_enabled,
        push_on_follow: push_enabled,
        push_on_mention: push_enabled,
        push_on_message: push_enabled,
        quiet_hours_start,
        quiet_hours_end,
        disable_all,
    });

    match notification_client
        .update_notification_preferences(grpc_request)
        .await
    {
        Ok(response) => {
            let grpc_response = response.into_inner();

            if let Some(prefs) = grpc_response.preferences {
                let in_app_enabled = !prefs.disable_all;
                let push_enabled = prefs.push_on_like
                    || prefs.push_on_comment
                    || prefs.push_on_follow
                    || prefs.push_on_mention
                    || prefs.push_on_message;
                let email_enabled = prefs.email_on_like
                    || prefs.email_on_comment
                    || prefs.email_on_follow
                    || prefs.email_on_mention;

                let quiet_hours_start = prefs
                    .quiet_hours_start
                    .split(':')
                    .next()
                    .and_then(|h| h.parse::<i32>().ok());
                let quiet_hours_end = prefs
                    .quiet_hours_end
                    .split(':')
                    .next()
                    .and_then(|h| h.parse::<i32>().ok());

                Ok(HttpResponse::Ok().json(NotificationPreferencesResponse {
                    in_app_enabled,
                    push_enabled,
                    email_enabled,
                    sms_enabled: false,
                    quiet_hours_start,
                    quiet_hours_end,
                }))
            } else {
                Ok(HttpResponse::InternalServerError()
                    .json(ErrorResponse::new("Failed to update preferences")))
            }
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to update notification preferences"
            );
            Ok(handle_grpc_error(
                status,
                "Failed to update notification preferences",
            ))
        }
    }
}

// ============================================================================
// POST /api/v2/notifications/push-token
// ============================================================================

/// POST /api/v2/notifications/push-token
/// Register a push notification token
pub async fn register_push_token(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    payload: web::Json<RegisterPushTokenPayload>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    info!(
        user_id = %user_id,
        platform = %payload.platform,
        device_id = %payload.device_id,
        "POST /api/v2/notifications/push-token"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(RegisterPushTokenRequest {
        user_id: user_id.clone(),
        device_id: payload.device_id.clone(),
        token: payload.token.clone(),
        platform: payload.platform.clone(),
        app_version: payload.app_version.clone().unwrap_or_default(),
    });

    match notification_client.register_push_token(grpc_request).await {
        Ok(_response) => {
            info!(
                user_id = %user_id,
                "Push token registered successfully"
            );

            Ok(HttpResponse::Ok().json(SuccessResponse { success: true }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to register push token"
            );
            Ok(handle_grpc_error(status, "Failed to register push token"))
        }
    }
}

// ============================================================================
// DELETE /api/v2/notifications/push-token/{token}
// ============================================================================

/// DELETE /api/v2/notifications/push-token/{token}
/// Unregister a push notification token
pub async fn unregister_push_token(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let token = path.into_inner();

    info!(
        user_id = %user_id,
        "DELETE /api/v2/notifications/push-token/{{token}}"
    );

    let mut notification_client = clients.notification_client();

    let grpc_request = tonic::Request::new(UnregisterPushTokenRequest {
        token: token.clone(),
    });

    match notification_client
        .unregister_push_token(grpc_request)
        .await
    {
        Ok(_response) => {
            info!(
                user_id = %user_id,
                "Push token unregistered successfully"
            );

            Ok(HttpResponse::Ok().json(SuccessResponse { success: true }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to unregister push token"
            );
            Ok(handle_grpc_error(status, "Failed to unregister push token"))
        }
    }
}

// ============================================================================
// POST /api/v2/notifications/batch
// ============================================================================

/// POST /api/v2/notifications/batch
/// Create multiple notifications in batch
pub async fn batch_create_notifications(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    payload: web::Json<BatchNotificationPayload>,
) -> Result<HttpResponse> {
    let _user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    info!(
        count = payload.notifications.len(),
        "POST /api/v2/notifications/batch"
    );

    let mut notification_client = clients.notification_client();

    let notifications = payload.notifications.iter().map(|n| {
        crate::clients::proto::notification::batch_create_notifications_request::NotificationData {
            user_id: n.user_id.clone(),
            notification_type: n.notification_type.clone(),
            title: n.title.clone(),
            body: n.body.clone(),
            data: n.data.clone().unwrap_or_default(),
            related_user_id: n.related_user_id.clone().unwrap_or_default(),
            related_post_id: n.related_post_id.clone().unwrap_or_default(),
            channels: n.channels.clone(),
        }
    }).collect();

    let grpc_request = tonic::Request::new(BatchCreateNotificationsRequest { notifications });

    match notification_client
        .batch_create_notifications(grpc_request)
        .await
    {
        Ok(response) => {
            let grpc_response = response.into_inner();

            info!(
                success_count = grpc_response.success_count,
                failed_count = grpc_response.failed_count,
                "Batch notifications created"
            );

            Ok(HttpResponse::Ok().json(BatchNotificationResponse {
                success_count: grpc_response.success_count,
                failure_count: grpc_response.failed_count,
                errors: None, // TODO: Include detailed errors if needed
            }))
        }
        Err(status) => {
            error!(
                error = %status,
                "Failed to create batch notifications"
            );
            Ok(handle_grpc_error(
                status,
                "Failed to create batch notifications",
            ))
        }
    }
}
