/// OpenAPI documentation for Nova Content Service
use utoipa::OpenApi;
use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Nova Content Service API",
        version = "1.0.0",
        description = "Content management service for posts, comments, and stories. Handles creation, retrieval, updates, and deletion of user-generated content including text posts, images, comments, and ephemeral stories. Provides feed generation and caching capabilities.",
        contact(
            name = "Nova Team",
            email = "support@nova.app"
        ),
        license(
            name = "MIT"
        )
    ),
    servers(
        (url = "http://localhost:8081", description = "Development server"),
        (url = "https://content-api.nova.app", description = "Production server"),
    ),
    tags(
        (name = "health", description = "Service health checks"),
        (name = "posts", description = "Post creation, retrieval, updates, and deletion"),
        (name = "comments", description = "Comment management on posts"),
        (name = "stories", description = "Ephemeral stories (24-hour lifespan)"),
        (name = "feed", description = "Feed generation and ranking"),
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
                        .build()
                ),
            )
        }
    }
}

impl ApiDoc {
    pub fn title() -> &'static str {
        "Nova Content Service"
    }

    pub fn version() -> &'static str {
        "1.0.0"
    }

    pub fn openapi_json_path() -> &'static str {
        "/api/v1/openapi.json"
    }
}
