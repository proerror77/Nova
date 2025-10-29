use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};
/// OpenAPI documentation for Nova User Service
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Nova User Service API",
        version = "1.0.0",
        description = "User authentication, profiles, relationships, feed, and trending content discovery. This service provides core user management functionality including registration, login, 2FA, password reset, profile management, social relationships (follow/unfollow), personalized feeds, and trending content discovery.",
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
        (name = "health", description = "Service health and readiness checks"),
        (name = "auth", description = "Authentication and authorization - registration, login, 2FA, JWT tokens"),
        (name = "users", description = "User profile and account management"),
        (name = "preferences", description = "User feed preferences and privacy settings"),
        (name = "relationships", description = "Social graph - follow, unfollow, block users"),
        (name = "feed", description = "Personalized content feed with ranking algorithms"),
        (name = "trending", description = "Trending posts, videos, streams, and categories"),
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
                        .description(Some("JWT Bearer token. Obtain from /api/v1/auth/login or /api/v1/auth/register"))
                        .build()
                ),
            )
        }
    }
}

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
