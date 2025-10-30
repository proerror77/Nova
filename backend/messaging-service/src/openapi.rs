use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};
/// OpenAPI documentation for Nova Messaging Service
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Nova Messaging Service API",
        version = "1.0.0",
        description = "Real-time messaging service with WebSocket support. Provides end-to-end encrypted messaging, group conversations, file attachments, typing indicators, read receipts, and WebRTC signaling for voice/video calls. Supports ECDH key exchange for E2E encryption.",
        contact(
            name = "Nova Team",
            email = "support@nova.app"
        ),
        license(
            name = "MIT"
        )
    ),
    servers(
        (url = "http://localhost:8083", description = "Development server"),
        (url = "https://messaging-api.nova.app", description = "Production server"),
    ),
    tags(
        (name = "health", description = "Service health checks"),
        (name = "messages", description = "Message CRUD operations"),
        (name = "conversations", description = "Conversation management and history"),
        (name = "websocket", description = "WebSocket real-time messaging"),
        (name = "key-exchange", description = "ECDH key exchange for E2E encryption"),
        (name = "calls", description = "WebRTC voice/video call signaling"),
        (name = "attachments", description = "File attachment upload and download"),
        (name = "reactions", description = "Message reactions and emojis"),
    ),
    modifiers(&SecurityAddon),
)]
pub struct ApiDoc;

struct SecurityAddon;

impl utoipa::Modify for SecurityAddon {
    fn modify(&self, openapi: &mut utoipa::openapi::OpenApi) {
        if let Some(components) = openapi.components.as_mut() {
            components.add_security_scheme(
                "bearer_auth",
                SecurityScheme::Http(
                    HttpBuilder::new()
                        .scheme(HttpAuthScheme::Bearer)
                        .bearer_format("JWT")
                        .description(Some("JWT Bearer token from user-service"))
                        .build(),
                ),
            )
        }
    }
}

impl ApiDoc {
    pub fn title() -> &'static str {
        "Nova Messaging Service"
    }

    pub fn version() -> &'static str {
        "1.0.0"
    }

    pub fn openapi_json_path() -> &'static str {
        "/api/v1/openapi.json"
    }
}
