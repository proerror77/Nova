/// OpenAPI documentation for Nova Messaging Service
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Nova Messaging Service API",
        version = "1.0.0",
        description = "Real-time messaging, conversations, and message reactions",
        contact(
            name = "Nova Team",
            email = "support@nova.app"
        ),
        license(
            name = "MIT"
        )
    ),
    servers(
        (url = "http://localhost:8085", description = "Development server"),
        (url = "https://api.nova.app/messages", description = "Production server"),
    ),
    tags(
        (name = "Health", description = "Service health checks"),
        (name = "Conversations", description = "Conversation management"),
        (name = "Messages", description = "Message CRUD operations"),
        (name = "Reactions", description = "Message reactions"),
        (name = "WebSocket", description = "Real-time messaging via WebSocket"),
    )
)]
pub struct ApiDoc;

impl ApiDoc {
    pub fn title() -> &'static str {
        "Nova Messaging Service"
    }

    pub fn version() -> &'static str {
        "1.0.0"
    }

    pub fn openapi_json_path() -> &'static str {
        "/openapi.json"
    }
}
