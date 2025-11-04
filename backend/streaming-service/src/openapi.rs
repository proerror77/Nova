use utoipa::openapi::{InfoBuilder, OpenApi, OpenApiBuilder, Paths};

/// Minimal OpenAPI specification for Streaming Service.
pub fn doc() -> OpenApi {
    OpenApiBuilder::new()
        .info(
            InfoBuilder::new()
                .title("Nova Streaming Service API")
                .version("1.0.0")
                .description(Some(
                    "Live streaming and real-time video delivery endpoints for the Nova platform.",
                ))
                .build(),
        )
        .paths(Paths::new())
        .build()
}
