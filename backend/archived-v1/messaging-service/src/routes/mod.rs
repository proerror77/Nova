use actix_web::{web, HttpResponse};

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
async fn openapi_json() -> HttpResponse {
    use utoipa::OpenApi;
    let api_doc = crate::openapi::ApiDoc::openapi();
    HttpResponse::Ok().json(serde_json::to_value(&api_doc).unwrap())
}

// Swagger UI handler
async fn swagger_ui() -> HttpResponse {
    HttpResponse::Ok().content_type("text/html").body(
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
async fn docs() -> HttpResponse {
    HttpResponse::Ok().content_type("text/html").body(
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

// Health check handler
async fn health_check() -> HttpResponse {
    HttpResponse::Ok().body("OK")
}

pub fn configure_routes(cfg: &mut web::ServiceConfig) {
    // Service introspection endpoints (no API version prefix)
    cfg.service(
        web::scope("")
            .route("/health", web::get().to(health_check))
            .route("/metrics", web::get().to(crate::metrics::metrics_handler))
            .route("/openapi.json", web::get().to(openapi_json))
            .route("/swagger-ui", web::get().to(swagger_ui))
            .route("/docs", web::get().to(docs)),
    );

    // API v1 endpoints (all business logic routes with /api/v1 prefix)
    cfg.service(
        web::scope("/api/v1")
            .wrap(actix_middleware::jwt_auth::JwtAuthMiddleware::new())
            // Video calls
            .route("/conversations/{id}/calls", web::post().to(initiate_call))
            .route("/calls/{id}/answer", web::post().to(answer_call))
            .route("/calls/{id}/join", web::post().to(join_call))
            .route("/calls/{id}/leave", web::post().to(leave_call))
            .route("/calls/{id}/participants", web::get().to(get_participants))
            .route("/calls/{id}/reject", web::post().to(reject_call))
            .route("/calls/{id}/end", web::post().to(end_call))
            .route("/calls/history", web::get().to(get_call_history))
            // RTC configuration
            .route("/rtc/ice-config", web::get().to(get_ice_config))
            // Location sharing
            .route(
                "/conversations/{id}/location",
                web::post().to(share_location),
            )
            .route(
                "/conversations/{id}/locations",
                web::get().to(get_conversation_locations),
            )
            .route(
                "/conversations/{id}/location/{user_id}",
                web::get().to(get_user_location),
            )
            .route(
                "/conversations/{id}/location/stop",
                web::post().to(stop_sharing_location),
            )
            .route(
                "/conversations/{id}/location/stats",
                web::get().to(get_location_stats),
            )
            .route(
                "/location/permissions",
                web::get().to(get_location_permissions),
            )
            .route(
                "/location/permissions",
                web::put().to(update_location_permissions),
            )
            // Conversations
            .route("/conversations", web::post().to(create_conversation))
            .route(
                "/conversations/groups",
                web::post().to(create_group_conversation),
            )
            .route("/conversations/{id}", web::get().to(get_conversation))
            .route("/conversations/{id}", web::delete().to(delete_group))
            .route(
                "/conversations/{id}/encryption-key",
                web::get().to(get_conversation_key),
            )
            .route("/conversations/{id}/leave", web::post().to(leave_group))
            .route("/conversations/{id}/messages", web::post().to(send_message))
            .route(
                "/conversations/{id}/messages/audio",
                web::post().to(send_audio_message),
            )
            .route(
                "/conversations/{id}/messages/audio/presigned-url",
                web::post().to(get_audio_presigned_url),
            )
            .route(
                "/conversations/{id}/messages",
                web::get().to(get_message_history),
            )
            .route(
                "/conversations/{id}/messages/search",
                web::get().to(search_messages),
            )
            .route(
                "/conversations/{id}/messages/{message_id}/recall",
                web::post().to(recall_message),
            )
            .route(
                "/conversations/{id}/messages/{message_id}/forward",
                web::post().to(forward_message),
            )
            .route("/conversations/{id}/read", web::post().to(mark_as_read))
            // Group management routes
            .route("/conversations/{id}/members", web::post().to(add_member))
            .route("/conversations/{id}/members", web::get().to(list_members))
            .route(
                "/conversations/{id}/members/{user_id}",
                web::delete().to(remove_member),
            )
            .route(
                "/conversations/{id}/members/{user_id}",
                web::put().to(update_member_role),
            )
            .route(
                "/conversations/{id}/settings",
                web::put().to(update_group_settings),
            )
            // Message reactions routes
            .route("/messages/{id}/reactions", web::post().to(add_reaction))
            .route("/messages/{id}/reactions", web::get().to(get_reactions))
            .route(
                "/messages/{id}/reactions/{user_id}",
                web::delete().to(remove_reaction),
            )
            // File attachments routes
            .route(
                "/conversations/{id}/messages/{message_id}/attachments",
                web::post().to(upload_attachment),
            )
            .route("/messages/{id}/attachments", web::get().to(get_attachments))
            .route(
                "/messages/{id}/attachments/{attachment_id}",
                web::delete().to(delete_attachment),
            )
            .route("/messages/{id}", web::put().to(update_message))
            .route("/messages/{id}", web::delete().to(delete_message))
            // Notifications routes
            .route("/notifications", web::post().to(create_notification))
            .route(
                "/notifications/device-tokens",
                web::post().to(register_device_token),
            )
            .route(
                "/notifications/device-tokens/{device_token}",
                web::delete().to(unregister_device_token),
            )
            .route(
                "/notifications/users/{user_id}",
                web::get().to(get_notifications),
            )
            .route(
                "/notifications/users/{user_id}/unread",
                web::get().to(get_unread_notifications),
            )
            .route(
                "/notifications/by-id/{notification_id}/read",
                web::put().to(mark_notification_read),
            )
            .route(
                "/notifications/users/{user_id}/mark-all-read",
                web::put().to(mark_all_read),
            )
            .route(
                "/notifications/by-id/{notification_id}",
                web::delete().to(delete_notification),
            )
            .route(
                "/notifications/users/{user_id}/preferences",
                web::get().to(get_preferences),
            )
            .route(
                "/notifications/users/{user_id}/preferences",
                web::put().to(update_preferences),
            )
            .route(
                "/notifications/users/{user_id}/subscribe/{notification_type}",
                web::post().to(subscribe),
            )
            .route(
                "/notifications/users/{user_id}/unsubscribe/{notification_type}",
                web::post().to(unsubscribe),
            )
            // ECDH Key Exchange routes
            .route("/keys/device", web::post().to(store_device_public_key))
            .route(
                "/conversations/{conversation_id}/keys/{peer_user_id}/{peer_device_id}",
                web::get().to(get_peer_public_key),
            )
            .route(
                "/conversations/{conversation_id}/complete-key-exchange",
                web::post().to(complete_key_exchange),
            )
            .route(
                "/conversations/{conversation_id}/key-exchanges",
                web::get().to(list_conversation_key_exchanges),
            )
            // WebSocket endpoint (with API version prefix for consistency)
            .route("/ws", web::get().to(ws_handler)),
    );
}
