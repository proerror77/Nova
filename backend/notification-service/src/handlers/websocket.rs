/// WebSocket handler for real-time notifications
///
/// Implements WebSocket endpoints for connection status and broadcasting.
/// Real-time WebSocket connections are handled via /ws/{user_id}

use actix_web::{web, HttpResponse, Result as ActixResult};
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

use crate::ConnectionManager;
use crate::websocket::WebSocketMessage;

/// WebSocket message size limit (256 KB)
#[allow(dead_code)]
const WS_MESSAGE_SIZE_LIMIT: usize = 256_000;

/// Get WebSocket connection status for a user
///
/// Endpoint: GET /api/v1/ws/status/{user_id}
pub async fn ws_status(
    path: web::Path<Uuid>,
    connection_manager: web::Data<Arc<ConnectionManager>>,
) -> ActixResult<HttpResponse> {
    let user_id = path.into_inner();

    let connection_count = connection_manager.connection_count(user_id).await;

    Ok(HttpResponse::Ok().json(json!({
        "user_id": user_id.to_string(),
        "connected": connection_count > 0,
        "connection_count": connection_count
    })))
}

/// Broadcast message to all connected users
///
/// Endpoint: POST /api/v1/ws/broadcast
pub async fn broadcast_message(
    connection_manager: web::Data<Arc<ConnectionManager>>,
    body: web::Json<serde_json::Value>,
) -> ActixResult<HttpResponse> {
    // Create a generic notification from the request
    let notification = WebSocketMessage::notification(
        Uuid::new_v4(),
        Uuid::nil(), // Broadcast to all
        body
            .get("notification_type")
            .and_then(|v| v.as_str())
            .unwrap_or("broadcast")
            .to_string(),
        body
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("Broadcast")
            .to_string(),
        body
            .get("body")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        None,
        body
            .get("priority")
            .and_then(|v| v.as_str())
            .unwrap_or("normal")
            .to_string(),
    );

    match connection_manager.broadcast(notification).await {
        Ok(_) => Ok(HttpResponse::Ok().json(json!({
            "success": true,
            "message": "Broadcast sent successfully"
        }))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(json!({
            "success": false,
            "error": e.to_string()
        }))),
    }
}

/// Get connection metrics
///
/// Endpoint: GET /api/v1/ws/metrics
pub async fn ws_metrics(
    connection_manager: web::Data<Arc<ConnectionManager>>,
) -> ActixResult<HttpResponse> {
    let total_connections = connection_manager.total_connections().await;
    let connected_users = connection_manager.connected_users_count().await;

    Ok(HttpResponse::Ok().json(json!({
        "total_connections": total_connections,
        "connected_users": connected_users,
        "average_connections_per_user": if connected_users > 0 {
            total_connections as f64 / connected_users as f64
        } else {
            0.0
        }
    })))
}

/// Send targeted notification to specific user
///
/// Endpoint: POST /api/v1/ws/notify/{user_id}
pub async fn send_user_notification(
    path: web::Path<Uuid>,
    connection_manager: web::Data<Arc<ConnectionManager>>,
    body: web::Json<serde_json::Value>,
) -> ActixResult<HttpResponse> {
    let recipient_id = path.into_inner();

    let notification = WebSocketMessage::notification(
        Uuid::new_v4(),
        recipient_id,
        body
            .get("notification_type")
            .and_then(|v| v.as_str())
            .unwrap_or("notification")
            .to_string(),
        body
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("Notification")
            .to_string(),
        body
            .get("body")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        body.get("image_url").and_then(|v| v.as_str()).map(String::from),
        body
            .get("priority")
            .and_then(|v| v.as_str())
            .unwrap_or("normal")
            .to_string(),
    );

    match connection_manager
        .send_notification(recipient_id, notification)
        .await
    {
        Ok(_) => {
            let count = connection_manager.connection_count(recipient_id).await;
            Ok(HttpResponse::Ok().json(json!({
                "success": true,
                "recipient_id": recipient_id.to_string(),
                "active_connections": count,
                "message": if count > 0 {
                    "Notification sent to connected clients"
                } else {
                    "User not connected (notification queued)"
                }
            })))
        }
        Err(e) => Ok(HttpResponse::InternalServerError().json(json!({
            "success": false,
            "error": e.to_string()
        }))),
    }
}

/// Send error notification
///
/// Endpoint: POST /api/v1/ws/error/{user_id}
pub async fn send_user_error(
    path: web::Path<Uuid>,
    connection_manager: web::Data<Arc<ConnectionManager>>,
    body: web::Json<serde_json::Value>,
) -> ActixResult<HttpResponse> {
    let user_id = path.into_inner();

    let code = body
        .get("code")
        .and_then(|v| v.as_str())
        .unwrap_or("ERROR")
        .to_string();

    let message = body
        .get("message")
        .and_then(|v| v.as_str())
        .unwrap_or("An error occurred")
        .to_string();

    match connection_manager.send_error(user_id, code, message).await {
        Ok(_) => Ok(HttpResponse::Ok().json(json!({
            "success": true,
            "user_id": user_id.to_string()
        }))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(json!({
            "success": false,
            "error": e.to_string()
        }))),
    }
}

/// Get list of all connected user IDs
///
/// Endpoint: GET /api/v1/ws/users
pub async fn list_connected_users(
    connection_manager: web::Data<Arc<ConnectionManager>>,
) -> ActixResult<HttpResponse> {
    let user_ids = connection_manager.connected_user_ids().await;

    Ok(HttpResponse::Ok().json(json!({
        "count": user_ids.len(),
        "users": user_ids
            .iter()
            .map(|id| id.to_string())
            .collect::<Vec<_>>()
    })))
}

/// Register WebSocket routes
pub fn register_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api/v1/ws")
            .route("/status/{user_id}", web::get().to(ws_status))
            .route("/broadcast", web::post().to(broadcast_message))
            .route("/metrics", web::get().to(ws_metrics))
            .route("/notify/{user_id}", web::post().to(send_user_notification))
            .route("/error/{user_id}", web::post().to(send_user_error))
            .route("/users", web::get().to(list_connected_users)),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_websocket_message_size_limit() {
        assert_eq!(WS_MESSAGE_SIZE_LIMIT, 256_000);
    }

    #[test]
    fn test_broadcast_message_structure() {
        let body = json!({
            "notification_type": "test",
            "title": "Test",
            "body": "Test message",
            "priority": "high"
        });

        assert_eq!(
            body.get("notification_type")
                .and_then(|v| v.as_str())
                .unwrap_or("broadcast"),
            "test"
        );
    }
}
