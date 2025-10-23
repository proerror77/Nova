use axum::Router;
use messaging_service::{config, error, logging, db, routes, state::AppState};
use sqlx::postgres::PgPoolOptions;
use std::net::SocketAddr;
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> Result<(), error::AppError> {
    logging::init_tracing();
    let cfg = config::Config::from_env()?;

    // Initialize DB pool
    let db = db::init_pool(&cfg.database_url)
        .await
        .map_err(|e| error::AppError::StartServer(format!("db: {e}")))?;

    let redis = redis::Client::open(cfg.redis_url.as_str()).map_err(|e| error::AppError::StartServer(format!("redis: {e}")))?;
    let registry = messaging_service::websocket::ConnectionRegistry::new();
    let state = AppState { db, registry: registry.clone(), redis: redis.clone() };
    // Start Redis psubscribe listener for cross-instance fanout
    tokio::spawn(async move {
        if let Err(e) = messaging_service::websocket::pubsub::start_psub_listener(redis, registry).await {
            tracing::warn!(error=%e, "redis psub listener exited");
        }
    });
    let app = routes::build_router().with_state(state);

    let addr: SocketAddr = ([0, 0, 0, 0], cfg.port).into();
    tracing::info!(%addr, "starting messaging-service");
    let listener = TcpListener::bind(addr)
        .await
        .map_err(|e| error::AppError::StartServer(e.to_string()))?;
    axum::serve(listener, app)
        .await
        .map_err(|e| error::AppError::StartServer(e.to_string()))?;

    Ok(())
}
