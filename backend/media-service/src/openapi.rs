use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};
/// OpenAPI documentation for Nova Media Service
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Nova Media Service API",
        version = "1.0.0",
        description = "Media processing service for videos, reels, and uploads. Handles video upload, transcoding, HLS streaming, thumbnail generation, and media delivery. Supports resumable uploads, adaptive bitrate streaming, and real-time transcoding progress tracking.",
        contact(
            name = "Nova Team",
            email = "support@nova.app"
        ),
        license(
            name = "MIT"
        )
    ),
    servers(
        (url = "http://localhost:8082", description = "Development server"),
        (url = "https://media-api.nova.app", description = "Production server"),
    ),
    tags(
        (name = "health", description = "Service health checks"),
        (name = "videos", description = "Video upload, processing, and streaming"),
        (name = "reels", description = "Short-form video content (reels)"),
        (name = "uploads", description = "Resumable multipart file uploads"),
        (name = "transcoding", description = "Video transcoding progress tracking"),
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
                        .description(Some("JWT Bearer token"))
                        .build(),
                ),
            )
        }
    }
}

impl ApiDoc {
    pub fn title() -> &'static str {
        "Nova Media Service"
    }

    pub fn version() -> &'static str {
        "1.0.0"
    }

    pub fn openapi_json_path() -> &'static str {
        "/api/v1/openapi.json"
    }
}
