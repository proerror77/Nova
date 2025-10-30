use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};
/// OpenAPI documentation for Nova Search Service
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Nova Search Service API",
        version = "1.0.0",
        description = "Elasticsearch-powered unified search service. Provides full-text search across users, posts, videos, and streaming content. Features include autocomplete suggestions, fuzzy matching, faceted search, and real-time indexing via Kafka CDC events.",
        contact(
            name = "Nova Team",
            email = "support@nova.app"
        ),
        license(
            name = "MIT"
        )
    ),
    servers(
        (url = "http://localhost:8084", description = "Development server"),
        (url = "https://search-api.nova.app", description = "Production server"),
    ),
    tags(
        (name = "health", description = "Service health checks"),
        (name = "search", description = "Unified search endpoints with ranking"),
        (name = "suggestions", description = "Autocomplete and search suggestions"),
        (name = "indexing", description = "Document indexing and updates"),
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
        "Nova Search Service"
    }

    pub fn version() -> &'static str {
        "1.0.0"
    }

    pub fn openapi_json_path() -> &'static str {
        "/api/v1/openapi.json"
    }
}
