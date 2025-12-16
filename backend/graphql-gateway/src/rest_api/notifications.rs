//! Notifications API endpoints
//!
//! GET /api/v2/notifications - Get notifications for current user
//! POST /api/v2/notifications/read/{id} - Mark notification as read
//! POST /api/v2/notifications/read-all - Mark all notifications as read

#![allow(dead_code)]

use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use super::models::ErrorResponse;
use crate::clients::proto::notification::{
    GetNotificationsRequest, MarkAllNotificationsAsReadRequest, MarkNotificationAsReadRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

/// REST API response for notification (iOS compatible)
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
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
#[serde(rename_all = "camelCase")]
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

#[derive(Debug, Deserialize)]
pub struct NotificationQueryParams {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
    pub unread_only: Option<bool>,
}

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
            let notifications = grpc_response
                .notifications
                .into_iter()
                .map(|n| {
                    // Combine title and body into message, or use body if title is empty
                    let message = if n.title.is_empty() {
                        n.body
                    } else if n.body.is_empty() {
                        n.title
                    } else {
                        format!("{}: {}", n.title, n.body)
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
                        user_name: None,          // Not in gRPC response yet
                        user_avatar_url: None,    // Not in gRPC response yet
                        post_thumbnail_url: None, // Not in gRPC response yet
                    }
                })
                .collect();

            // Calculate has_more based on whether we got a full page of results
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
                "Failed to get notifications from notification-service"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::new("User not found"))
                }
                tonic::Code::Unauthenticated => {
                    HttpResponse::Unauthorized().json(ErrorResponse::new("Unauthorized"))
                }
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid request", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    status.message(),
                )),
            };

            Ok(error_response)
        }
    }
}

/// POST /api/v2/notifications/read/{id}
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
        "POST /api/v2/notifications/read/{{id}}"
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

            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to mark notification as read",
                    status.message(),
                )),
            )
        }
    }
}

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

            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to mark all notifications as read",
                    status.message(),
                )),
            )
        }
    }
}
