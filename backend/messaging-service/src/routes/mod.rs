use crate::state::AppState;
use axum::middleware;
use axum::{
    routing::{delete, get, post, put},
    Json, Router,
};
use serde_json::json;
pub mod calls;
use calls::{
    answer_call, end_call, get_call_history, get_participants, initiate_call, join_call,
    leave_call, reject_call,
};
pub mod locations;
use locations::{
    get_conversation_locations, get_location_permissions, get_location_stats, get_user_location,
    share_location, stop_sharing_location, update_location_permissions,
};
pub mod conversations;
use conversations::{
    create_conversation, create_group_conversation, delete_group, get_conversation,
    get_conversation_key, leave_group, mark_as_read,
};
pub mod messages;
use messages::{
    delete_message, forward_message, get_audio_presigned_url, get_message_history, recall_message,
    search_messages, send_audio_message, send_message, update_message,
};
pub mod groups;
use groups::{add_member, list_members, remove_member, update_group_settings, update_member_role};
pub mod reactions;
use reactions::{add_reaction, get_reactions, remove_reaction};
pub mod attachments;
use attachments::{delete_attachment, get_attachments, upload_attachment};
pub mod notifications;
use notifications::{
    create_notification, delete_notification, get_notifications, get_preferences,
    get_unread_notifications, mark_all_read, mark_notification_read, register_device_token,
    subscribe, unregister_device_token, unsubscribe, update_preferences,
};
pub mod rtc;
use rtc::get_ice_config;
pub mod wsroute;
use wsroute::ws_handler;
pub mod key_exchange;
use key_exchange::{
    complete_key_exchange, get_peer_public_key, list_conversation_key_exchanges,
    store_device_public_key,
};

// OpenAPI endpoint handler
async fn openapi_json() -> Json<serde_json::Value> {
    use utoipa::OpenApi;
    Json(serde_json::to_value(&crate::openapi::ApiDoc::openapi()).unwrap())
}

// Swagger UI handler
async fn swagger_ui() -> axum::response::Html<&'static str> {
    axum::response::Html(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Nova Messaging Service API</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
    <script>
        window.onload = function() {
            SwaggerUIBundle({
                url: "/openapi.json",
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIStandalonePreset
                ],
                plugins: [
                    SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "StandaloneLayout"
            });
        };
    </script>
</body>
</html>"#,
    )
}

// Documentation entry point
async fn docs() -> axum::response::Html<&'static str> {
    axum::response::Html(
        r#"<!DOCTYPE html>
<html>
<head>
    <title>Nova Messaging Service API</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        a { display: block; margin: 15px 0; padding: 15px; background: #28a745; color: white; text-decoration: none; border-radius: 4px; }
        a:hover { background: #218838; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Nova Messaging Service API</h1>
        <p>Choose your preferred documentation viewer:</p>
        <a href="/swagger-ui">📘 Swagger UI (Interactive)</a>
        <a href="/openapi.json">📄 OpenAPI JSON (Raw)</a>
    </div>
</body>
</html>"#,
    )
}

// Metrics endpoint for monitoring (Prometheus-compatible format)
async fn metrics() -> String {
    // Basic metrics - can be extended with actual Prometheus instrumentation
    json!({
        "service": "messaging-service",
        "version": "0.1.0",
        "status": "healthy",
        "timestamp": chrono::Utc::now().to_rfc3339(),
    })
    .to_string()
}

pub fn build_router() -> Router<AppState> {
    // Service introspection endpoints (no API version prefix)
    let introspection = Router::new()
        .route("/health", get(|| async { "OK" }))
        .route("/metrics", get(metrics))
        .route("/openapi.json", get(openapi_json))
        .route("/swagger-ui", get(swagger_ui))
        .route("/docs", get(docs));

    // API v1 endpoints (all business logic routes with /api/v1 prefix)
    let api_v1 = Router::new()
        // Video calls
        .route("/conversations/:id/calls", post(initiate_call))
        .route("/calls/:id/answer", post(answer_call))
        .route("/calls/:id/join", post(join_call))
        .route("/calls/:id/leave", post(leave_call))
        .route("/calls/:id/participants", get(get_participants))
        .route("/calls/:id/reject", post(reject_call))
        .route("/calls/:id/end", post(end_call))
        .route("/calls/history", get(get_call_history))
        // RTC configuration
        .route("/rtc/ice-config", get(get_ice_config))
        // Location sharing
        .route("/conversations/:id/location", post(share_location))
        .route(
            "/conversations/:id/locations",
            get(get_conversation_locations),
        )
        .route(
            "/conversations/:id/location/:user_id",
            get(get_user_location),
        )
        .route(
            "/conversations/:id/location/stop",
            post(stop_sharing_location),
        )
        .route("/conversations/:id/location/stats", get(get_location_stats))
        .route("/location/permissions", get(get_location_permissions))
        .route("/location/permissions", put(update_location_permissions))
        // Conversations
        .route("/conversations", post(create_conversation))
        .route("/conversations/groups", post(create_group_conversation))
        .route(
            "/conversations/:id",
            get(get_conversation).delete(delete_group),
        )
        .route(
            "/conversations/:id/encryption-key",
            get(get_conversation_key),
        )
        .route("/conversations/:id/leave", post(leave_group))
        .route("/conversations/:id/messages", post(send_message))
        .route(
            "/conversations/:id/messages/audio",
            post(send_audio_message),
        )
        .route(
            "/conversations/:id/messages/audio/presigned-url",
            post(get_audio_presigned_url),
        )
        .route("/conversations/:id/messages", get(get_message_history))
        .route("/conversations/:id/messages/search", get(search_messages))
        .route(
            "/conversations/:id/messages/:message_id/recall",
            post(recall_message),
        )
        .route(
            "/conversations/:id/messages/:message_id/forward",
            post(forward_message),
        )
        .route("/conversations/:id/read", post(mark_as_read))
        // Group management routes
        .route("/conversations/:id/members", post(add_member))
        .route("/conversations/:id/members", get(list_members))
        .route("/conversations/:id/members/:user_id", delete(remove_member))
        .route(
            "/conversations/:id/members/:user_id",
            put(update_member_role),
        )
        .route("/conversations/:id/settings", put(update_group_settings))
        // Message reactions routes
        .route("/messages/:id/reactions", post(add_reaction))
        .route("/messages/:id/reactions", get(get_reactions))
        .route("/messages/:id/reactions/:user_id", delete(remove_reaction))
        // File attachments routes
        .route(
            "/conversations/:id/messages/:message_id/attachments",
            post(upload_attachment),
        )
        .route("/messages/:id/attachments", get(get_attachments))
        .route(
            "/messages/:id/attachments/:attachment_id",
            delete(delete_attachment),
        )
        .route("/messages/:id", put(update_message))
        .route("/messages/:id", delete(delete_message))
        // Notifications routes (reworked paths to avoid dynamic conflicts)
        .route("/notifications", post(create_notification))
        .route("/notifications/device-tokens", post(register_device_token))
        .route(
            "/notifications/device-tokens/:device_token",
            delete(unregister_device_token),
        )
        .route("/notifications/users/:user_id", get(get_notifications))
        .route(
            "/notifications/users/:user_id/unread",
            get(get_unread_notifications),
        )
        .route(
            "/notifications/by-id/:notification_id/read",
            put(mark_notification_read),
        )
        .route(
            "/notifications/users/:user_id/mark-all-read",
            put(mark_all_read),
        )
        .route(
            "/notifications/by-id/:notification_id",
            delete(delete_notification),
        )
        .route(
            "/notifications/users/:user_id/preferences",
            get(get_preferences),
        )
        .route(
            "/notifications/users/:user_id/preferences",
            put(update_preferences),
        )
        .route(
            "/notifications/users/:user_id/subscribe/:notification_type",
            post(subscribe),
        )
        .route(
            "/notifications/users/:user_id/unsubscribe/:notification_type",
            post(unsubscribe),
        )
        // ECDH Key Exchange routes
        .route("/keys/device", post(store_device_public_key))
        .route(
            "/conversations/:conversation_id/keys/:peer_user_id/:peer_device_id",
            get(get_peer_public_key),
        )
        .route(
            "/conversations/:conversation_id/complete-key-exchange",
            post(complete_key_exchange),
        )
        .route(
            "/conversations/:conversation_id/key-exchanges",
            get(list_conversation_key_exchanges),
        )
        // WebSocket endpoint (with API version prefix for consistency)
        .route("/ws", get(ws_handler));

    // Apply auth middleware only to API v1 (introspection stays public for healthchecks)
    let secured_api_v1 = api_v1.layer(middleware::from_fn(
        crate::middleware::auth::auth_middleware,
    ));

    // Combine introspection and API v1 routes
    let router = introspection.merge(axum::Router::new().nest("/api/v1", secured_api_v1));

    crate::middleware::with_defaults(router)
}
