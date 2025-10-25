use axum::middleware;
use messaging_service::{config, error, logging, db, routes, state::AppState};
use std::net::SocketAddr;
use tokio::net::TcpListener;
use axum::extract::Request;
use std::sync::Arc;

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
    // Run embedded migrations (idempotent)
    if let Err(e) = messaging_service::migrations::run_all(&db).await {
        tracing::warn!(error=%e, "failed to run migrations at startup");
    }
    let state = AppState { db: db.clone(), registry: registry.clone(), redis: redis.clone() };
    // Start Redis psubscribe listener for cross-instance fanout
    tokio::spawn(async move {
        if let Err(e) = messaging_service::websocket::pubsub::start_psub_listener(redis, registry).await {
            tracing::warn!(error=%e, "redis psub listener exited");
        }
    });

    // Wrap db in Arc for sharing across middleware
    let db_arc = Arc::new(db);

    // Add DB pool to all request extensions via middleware
    // and apply JWT authentication middleware
    let app = routes::build_router()
        .with_state(state)
        .layer(middleware::from_fn(move |mut req: Request, next: axum::middleware::Next| {
            let db = db_arc.clone();
            async move {
                req.extensions_mut().insert(db);
                next.run(req).await
            }
        }))
        .layer(middleware::from_fn(messaging_service::middleware::auth::auth_middleware));

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
