/// Route definitions and middleware setup
use axum::{
    body::Body,
    middleware::Next,
    response::IntoResponse,
};
use axum::http::Request;

/// CORS middleware configuration
pub async fn cors_middleware(
    req: Request<Body>,
    next: Next,
) -> impl IntoResponse {
    let response = next.run(req).await;
    response
}
