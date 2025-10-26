/// OpenAPI documentation for Nova Search Service
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Nova Search Service API",
        version = "1.0.0",
        description = "Unified search across users, posts, videos, and streaming content",
        contact(
            name = "Nova Team",
            email = "support@nova.app"
        ),
        license(
            name = "MIT"
        )
    ),
    servers(
        (url = "http://localhost:8086", description = "Development server"),
        (url = "https://api.nova.app/search", description = "Production server"),
    ),
    tags(
        (name = "Health", description = "Service health checks"),
        (name = "Search", description = "Unified search endpoints"),
        (name = "Users", description = "User search"),
        (name = "Posts", description = "Post search"),
        (name = "Videos", description = "Video search"),
        (name = "Streams", description = "Stream search"),
    )
)]
pub struct ApiDoc;

impl ApiDoc {
    pub fn title() -> &'static str {
        "Nova Search Service"
    }

    pub fn version() -> &'static str {
        "1.0.0"
    }

    pub fn openapi_json_path() -> &'static str {
        "/openapi.json"
    }
}
