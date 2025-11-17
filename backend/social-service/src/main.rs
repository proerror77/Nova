use actix_web::{web, App, HttpServer};
use anyhow::{Context, Result};

#[actix_web::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    tracing::info!("Starting social-service");

    // TODO: Initialize DB pool, Redis, gRPC server

    // HTTP health check server
    let http_port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8006); // social-service default port

    HttpServer::new(|| {
        App::new()
            .route("/health", web::get().to(|| async { "OK" }))
            .route("/ready", web::get().to(|| async { "READY" }))
    })
    .bind(("0.0.0.0", http_port))?
    .run()
    .await
    .context("HTTP server error")
}
