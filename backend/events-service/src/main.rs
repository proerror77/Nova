use actix_web::{web, App, HttpServer};
use std::io;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

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

    tracing::info!("Starting service");

    // Initialize database
    let db_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(10)
        .connect(&std::env::var("DATABASE_URL").unwrap_or_default())
        .await
        .ok();

    // Start HTTP server
    HttpServer::new(move || App::new().route("/health", web::get().to(|| async { "OK" })))
        .bind("0.0.0.0:8000")?
        .run()
        .await
}
