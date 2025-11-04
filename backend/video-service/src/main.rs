use actix_web::{web, App, HttpServer};
use std::io;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use video_service::config::Config;
use video_service::handlers;

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let config = Config::from_env().expect("Failed to load configuration");

    tracing::info!("Starting video-service v{}", env!("CARGO_PKG_VERSION"));
    tracing::info!("Environment: {}", config.app.env);

    let db_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(config.database.max_connections)
        .connect(&config.database.url)
        .await
        .expect("Failed to create database pool");
    let db_pool = web::Data::new(db_pool);

    // TODO: Start gRPC server for VideoService in addition to HTTP server

    HttpServer::new(move || {
        App::new()
            .app_data(db_pool.clone())
            .route("/health", web::get().to(|| async { "OK" }))
            .configure(handlers::configure_routes)
    })
    .bind(format!("0.0.0.0:{}", config.app.port))?
    .run()
    .await
}
