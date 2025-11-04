use utoipa::openapi::{InfoBuilder, OpenApi, OpenApiBuilder, Paths};

/// Minimal OpenAPI specification for Feed Service.
pub fn doc() -> OpenApi {
    OpenApiBuilder::new()
        .info(
            InfoBuilder::new()
                .title("Nova Feed Service API")
                .version("1.0.0")
                .description(Some(
                    "Feed aggregation and recommendation endpoints for the Nova platform.",
                ))
                .build(),
        )
        .paths(Paths::new())
        .build()
}
