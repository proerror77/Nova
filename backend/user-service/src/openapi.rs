use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};
/// OpenAPI documentation for Nova User Service
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Nova User Service API",
        version = "1.0.0",
        description = "User profiles, relationships, and preferences management. This service provides core user account functionality including profile management, social relationships (follow/unfollow), user preferences, and relationship management. Authentication, feed generation, and trending content discovery have been moved to dedicated microservices.",
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
        (name = "users", description = "User profile and account management"),
        (name = "preferences", description = "User preferences and privacy settings"),
        (name = "relationships", description = "Social graph - follow, unfollow, block users"),
    ),
    // NOTE: Auth endpoints moved to auth-service (port 8084)
    // NOTE: Feed endpoints moved to feed-service (port 8089)
    // NOTE: Trending endpoints moved to feed-service (port 8089)
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
                        .description(Some("JWT Bearer token. Obtain from auth-service (port 8084) via /api/v1/auth/login or /api/v1/auth/register"))
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
