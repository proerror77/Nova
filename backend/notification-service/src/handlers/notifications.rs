use crate::models::CreateNotificationRequest;
use crate::services::NotificationService;
/// Notification CRUD handlers
use actix_web::{web, HttpResponse, Result as ActixResult};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

/// Request to create a notification
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct CreateNotificationPayload {
    pub recipient_id: Uuid,
    pub sender_id: Option<Uuid>,
    pub notification_type: String,
    pub title: String,
    pub body: String,
    pub image_url: Option<String>,
    pub object_id: Option<Uuid>,
    pub object_type: Option<String>,
    pub metadata: Option<serde_json::Value>,
    pub priority: Option<String>,
}

/// API Response wrapper
#[derive(Debug, Serialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

impl<T: Serialize> ApiResponse<T> {
    pub fn ok(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
        }
    }

    pub fn err(error: String) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(error),
        }
    }
}

/// Create a new notification
///
/// POST /api/v1/notifications
pub async fn create_notification(
    service: web::Data<Arc<NotificationService>>,
    req: web::Json<CreateNotificationPayload>,
) -> ActixResult<HttpResponse> {
    let notification_type = parse_notification_type(&req.notification_type);
    let priority = parse_priority(req.priority.as_deref().unwrap_or("normal"));

    let create_req = CreateNotificationRequest {
        recipient_id: req.recipient_id,
        sender_id: req.sender_id,
        notification_type,
        title: req.title.clone(),
        body: req.body.clone(),
        image_url: req.image_url.clone(),
        object_id: req.object_id,
        object_type: req.object_type.clone(),
        metadata: req.metadata.clone(),
        priority,
    };

    match service.create_notification(create_req).await {
        Ok(notification) => Ok(HttpResponse::Ok().json(ApiResponse::ok(notification))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<String>::err(e))),
    }
}

/// Get notification by ID
///
/// GET /api/v1/notifications/{id}
pub async fn get_notification(
    service: web::Data<Arc<NotificationService>>,
    path: web::Path<Uuid>,
) -> ActixResult<HttpResponse> {
    let notification_id = path.into_inner();

    match service.get_notification(notification_id).await {
        Ok(Some(notification)) => Ok(HttpResponse::Ok().json(ApiResponse::ok(notification))),
        Ok(None) => Ok(HttpResponse::NotFound().json(ApiResponse::<String>::err(
            "Notification not found".to_string(),
        ))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<String>::err(e))),
    }
}

/// Mark notification as read
///
/// PUT /api/v1/notifications/{id}/read
pub async fn mark_as_read(
    service: web::Data<Arc<NotificationService>>,
    path: web::Path<Uuid>,
) -> ActixResult<HttpResponse> {
    let notification_id = path.into_inner();

    match service.mark_as_read(notification_id).await {
        Ok(_) => Ok(HttpResponse::Ok().json(ApiResponse::ok(serde_json::json!({"success": true})))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<String>::err(e))),
    }
}

/// Send push notifications to a user
///
/// POST /api/v1/notifications/{id}/send
pub async fn send_notification(
    service: web::Data<Arc<NotificationService>>,
    path: web::Path<Uuid>,
) -> ActixResult<HttpResponse> {
    let notification_id = path.into_inner();

    match service.get_notification(notification_id).await {
        Ok(Some(notification)) => match service.send_push_notifications(&notification).await {
            Ok(results) => Ok(HttpResponse::Ok().json(ApiResponse::ok(results))),
            Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<String>::err(e))),
        },
        Ok(None) => Ok(HttpResponse::NotFound().json(ApiResponse::<String>::err(
            "Notification not found".to_string(),
        ))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<String>::err(e))),
    }
}

// Helper functions
fn parse_notification_type(s: &str) -> crate::models::NotificationType {
    use crate::models::NotificationType;
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

fn parse_priority(s: &str) -> crate::models::NotificationPriority {
    use crate::models::NotificationPriority;
    match s.to_uppercase().as_str() {
        "LOW" => NotificationPriority::Low,
        "NORMAL" => NotificationPriority::Normal,
        "HIGH" => NotificationPriority::High,
        _ => NotificationPriority::Normal,
    }
}

/// Register routes
pub fn register_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api/v1/notifications")
            .route("", web::post().to(create_notification))
            .route("/{id}", web::get().to(get_notification))
            .route("/{id}/read", web::put().to(mark_as_read))
            .route("/{id}/send", web::post().to(send_notification)),
    );
}
