/// OpenAPI documentation for Nova User Service
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Nova User Service API",
        version = "1.0.0",
        description = "User authentication, profiles, relationships, posts, videos, and streaming",
        contact(
            name = "Nova Team",
            email = "support@nova.app"
        ),
        license(
            name = "MIT"
        )
    ),
    servers(
        (url = "http://localhost:8080", description = "Development server"),
        (url = "https://api.nova.app", description = "Production server"),
    ),
    tags(
        (name = "Health", description = "Service health checks"),
        (name = "Auth", description = "Authentication and authorization endpoints"),
        (name = "Users", description = "User profile and account management"),
        (name = "Posts", description = "Post creation and management"),
        (name = "Videos", description = "Video upload, processing and streaming"),
        (name = "Streams", description = "Live streaming management"),
        (name = "Relationships", description = "Follow, block, and user relationships"),
        (name = "Feed", description = "Feed ranking and content discovery"),
        (name = "Stories", description = "Story creation and management"),
    )
)]
pub struct ApiDoc;

impl ApiDoc {
    pub fn title() -> &'static str {
        "Nova User Service"
    }

    pub fn version() -> &'static str {
        "1.0.0"
    }

    pub fn openapi_json_path() -> &'static str {
        "/api/v1/openapi.json"
    }
}

/// Helper to build OpenAPI documentation URL
pub fn swagger_ui_url() -> String {
    format!(
        "https://cdn.jsdelivr.net/npm/swagger-ui-dist@3/index.html?url={}",
        ApiDoc::openapi_json_path()
    )
}

/// RapidOC documentation URL
pub fn rapidoc_url() -> String {
    format!(
        "https://unpkg.com/rapidoc@latest/dist/rapidoc-min.html?spec-url={}",
        ApiDoc::openapi_json_path()
    )
}
