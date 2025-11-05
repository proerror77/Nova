use actix_web::{web, App, HttpServer};
use std::io;
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
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

    // Initialize database (standardized pool)
    let mut cfg = DbPoolConfig::from_env().unwrap_or_default();
    if cfg.database_url.is_empty() {
        cfg.database_url = std::env::var("DATABASE_URL").unwrap_or_default();
    }
    if cfg.max_connections < 20 { cfg.max_connections = 20; }
    cfg.log_config();
    let db_pool = create_pg_pool(cfg).await.ok();

    // Start HTTP server
    HttpServer::new(move || App::new().route("/health", web::get().to(|| async { "OK" })))
        .bind("0.0.0.0:8000")?
        .run()
        .await
}
