/// HTTP API for internal services (Zitadel Actions)
///
/// This module provides HTTP endpoints for internal service communication,
/// specifically designed for Zitadel Actions to fetch user claims during
/// OIDC token issuance.
///
/// Security: All endpoints require INTERNAL_API_KEY authentication via
/// X-Internal-API-Key header.
mod zitadel;

pub use zitadel::*;

use axum::{
    extract::Request,
    http::StatusCode,
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::get,
    Router,
};
use sqlx::PgPool;
use std::sync::Arc;
use tracing::{info, warn};

/// Shared HTTP server state
#[derive(Clone)]
pub struct HttpServerState {
    pub db: PgPool,
    pub internal_api_key: Option<String>,
}

/// Build the HTTP router with all internal API endpoints
pub fn build_router(state: HttpServerState) -> Router {
    let state = Arc::new(state);

    Router::new()
        .route("/health", get(health_check))
        .route(
            "/internal/zitadel/user-claims/{user_id}",
            get(zitadel::get_user_claims),
        )
        .layer(middleware::from_fn_with_state(
            Arc::clone(&state),
            auth_middleware,
        ))
        .with_state(state)
}

/// Health check endpoint (no auth required)
async fn health_check() -> impl IntoResponse {
    (StatusCode::OK, "OK")
}

/// Authentication middleware - validates X-Internal-API-Key header
async fn auth_middleware(
    axum::extract::State(state): axum::extract::State<Arc<HttpServerState>>,
    request: Request,
    next: Next,
) -> Response {
    // Skip auth for health check
    if request.uri().path() == "/health" {
        return next.run(request).await;
    }

    // Check if internal API key is configured
    let Some(expected_key) = &state.internal_api_key else {
        warn!("Internal API key not configured - blocking all internal requests");
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Internal API key not configured",
        )
            .into_response();
    };

    // Validate API key from header
    let provided_key = request
        .headers()
        .get("x-internal-api-key")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();

    if provided_key != expected_key {
        warn!(
            path = %request.uri().path(),
            "Unauthorized internal API request - invalid API key"
        );
        return (StatusCode::UNAUTHORIZED, "Invalid API key").into_response();
    }

    next.run(request).await
}

/// Start HTTP server for internal APIs
pub async fn start_http_server(
    state: HttpServerState,
    host: &str,
    port: u16,
) -> anyhow::Result<()> {
    let app = build_router(state);
    let addr = format!("{}:{}", host, port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;

    info!("Starting internal HTTP API server on {}", addr);

    axum::serve(listener, app)
        .await
        .map_err(|e| anyhow::anyhow!("HTTP server error: {}", e))?;

    Ok(())
}
