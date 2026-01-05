mod api;
mod config;
mod db;
mod error;
mod middleware;
mod models;
mod services;

use axum::{
    routing::get,
    Router,
};
use tower_http::{
    cors::{Any, CorsLayer},
    trace::TraceLayer,
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::config::Config;
use crate::db::Database;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "admin_api=debug,tower_http=debug".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load configuration
    let config = Config::load()?;
    tracing::info!("Configuration loaded successfully");

    // Initialize database connections
    let db = Database::connect(&config).await?;
    tracing::info!("Database connections established");

    // Run database migrations
    db.run_migrations().await?;

    // Build application state
    let state = AppState { db, config: config.clone() };

    // Build router
    let app = Router::new()
        .route("/health", get(health_check))
        .nest("/api/v1", api::routes())
        .layer(CorsLayer::new()
            .allow_origin(Any)
            .allow_methods(Any)
            .allow_headers(Any))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Start server
    let addr = format!("{}:{}", config.server.host, config.server.port);
    tracing::info!("Starting server on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn health_check() -> &'static str {
    "OK"
}

#[derive(Clone)]
pub struct AppState {
    pub db: Database,
    pub config: Config,
}
