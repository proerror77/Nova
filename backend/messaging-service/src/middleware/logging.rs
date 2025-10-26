use axum::http;
use axum::Router;
use tower_http::trace::TraceLayer;
use tracing::Level;

use crate::state::AppState;

/// Add HTTP trace logging layer (request/response + latency)
pub fn add_tracing(router: Router<AppState>) -> Router<AppState> {
    router.layer(
        TraceLayer::new_for_http()
            .make_span_with(|req: &http::Request<_>| {
                let method = req.method().clone();
                let uri = req.uri().path().to_string();
                tracing::span!(Level::INFO, "http", %method, %uri)
            })
            .on_response(|res: &http::Response<_>, latency: std::time::Duration, _span: &tracing::Span| {
                tracing::info!(status = %res.status(), elapsed_ms = latency.as_millis() as u64, "response");
            }),
    )
}
