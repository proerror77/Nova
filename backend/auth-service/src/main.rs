use axum::{
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde_json::json;
use sqlx::postgres::PgPoolOptions;
use std::sync::Arc;
use tracing_subscriber::layer::SubscriberExt;

mod db;
mod error;
mod handlers;
mod models;
mod services;
mod telemetry;

use auth_service::Result;
use tracing::{info, subscriber::set_global_default};

#[derive(Clone)]
pub struct AppState {
    db: sqlx::PgPool,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize Jaeger tracing
    telemetry::init_tracer();

    // Initialize tracing subscriber
    let subscriber = tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::from_default_env())
        .with(tracing_subscriber::fmt::layer());
    set_global_default(subscriber)
        .map_err(|e| auth_service::AuthError::Internal(format!("Failed to set subscriber: {}", e)))?;

    // Database setup
    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgresql://postgres:postgres@localhost:5432/nova_auth".to_string());

    let pool = PgPoolOptions::new()
        .max_connections(20)
        .connect(&database_url)
        .await
        .map_err(|e| auth_service::AuthError::Internal(format!("Failed to connect to DB: {}", e)))?;

    // Verify database connection
    sqlx::query("SELECT 1")
        .execute(&pool)
        .await
        .map_err(|e| auth_service::AuthError::Internal(format!("DB health check failed: {}", e)))?;

    let state = AppState { db: pool };

    // Build router
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/api/v1/auth/register", post(handlers::auth::register))
        .route("/api/v1/auth/login", post(handlers::auth::login))
        .route("/api/v1/auth/verify-email", post(handlers::auth::verify_email))
        .route("/api/v1/auth/refresh", post(handlers::auth::refresh_token))
        .route("/api/v1/auth/logout", post(handlers::auth::logout))
        .with_state(Arc::new(state));

    // Start server
    let host = std::env::var("APP_HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port = std::env::var("APP_PORT")
        .unwrap_or_else(|_| "8084".to_string())
        .parse::<u16>()
        .map_err(|e| auth_service::AuthError::Internal(format!("Invalid port: {}", e)))?;

    let addr = format!("{}:{}", host, port);
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .map_err(|e| auth_service::AuthError::Internal(format!("Failed to bind: {}", e)))?;

    info!("Auth service listening on {}", addr);

    axum::serve(listener, app)
        .await
        .map_err(|e| auth_service::AuthError::Internal(format!("Server error: {}", e)))?;

    Ok(())
}

async fn health_check() -> impl IntoResponse {
    (
        StatusCode::OK,
        Json(json!({
            "status": "healthy",
            "service": "auth-service",
            "version": "0.1.0"
        })),
    )
}
