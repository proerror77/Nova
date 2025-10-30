use axum::extract::Request;
use axum::middleware;
use crypto_core::jwt as core_jwt;
use messaging_service::{
    config, db, error, logging,
    redis_client::RedisClient,
    routes,
    services::{encryption::EncryptionService, key_exchange::KeyExchangeService, push::ApnsPush},
    state::AppState,
    websocket::streams::{start_streams_listener, StreamsConfig},
};
use redis_utils::{RedisPool, SentinelConfig};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> Result<(), error::AppError> {
    logging::init_tracing();
    let cfg = Arc::new(config::Config::from_env()?);

    // Initialize DB pool
    let db = db::init_pool(&cfg.database_url)
        .await
        .map_err(|e| error::AppError::StartServer(format!("db: {e}")))?;

    let sentinel_cfg = cfg.redis_sentinel.as_ref().map(|cfg| {
        SentinelConfig::new(
            cfg.endpoints.clone(),
            cfg.master_name.clone(),
            Duration::from_millis(cfg.poll_interval_ms),
        )
    });

    let redis_pool = RedisPool::connect(&cfg.redis_url, sentinel_cfg)
        .await
        .map_err(|e| error::AppError::StartServer(format!("redis: {e}")))?;
    let redis = RedisClient::new(redis_pool.manager());
    let registry = messaging_service::websocket::ConnectionRegistry::new();
    // Run embedded migrations (idempotent)
    if let Err(e) = messaging_service::migrations::run_all(&db).await {
        tracing::warn!(error=%e, "failed to run migrations at startup");
    }
    // 初始化 JWT 驗證（支援從檔案讀取）
    // debug: print whether file env exists
    if let Ok(path) = std::env::var("JWT_PUBLIC_KEY_FILE") {
        tracing::info!(jwt_public_key_file=%path, "JWT public key file env detected");
    } else {
        tracing::info!("JWT_PUBLIC_KEY_FILE not set");
    }

    let public_key = match std::env::var("JWT_PUBLIC_KEY_PEM") {
        Ok(pem) => pem,
        Err(_) => {
            let path = std::env::var("JWT_PUBLIC_KEY_FILE")
                .map_err(|_| error::AppError::StartServer("JWT_PUBLIC_KEY_PEM missing".into()))?;
            std::fs::read_to_string(path)
                .map_err(|e| error::AppError::StartServer(format!("read jwt pubkey file: {e}")))?
        }
    };
    core_jwt::initialize_jwt_validation_only(&public_key)
        .map_err(|e| error::AppError::StartServer(format!("init jwt: {e}")))?;

    let apns_client = match cfg.apns.as_ref() {
        Some(apns_cfg) => match ApnsPush::new(apns_cfg) {
            Ok(client) => Some(Arc::new(client)),
            Err(e) => {
                tracing::warn!(error=%e, "failed to initialize APNs client; push delivery disabled");
                None
            }
        },
        None => None,
    };

    let encryption = Arc::new(EncryptionService::new(cfg.encryption_master_key));
    let key_exchange_service = Arc::new(KeyExchangeService::new(Arc::new(db.clone())));

    let state = AppState {
        db: db.clone(),
        registry: registry.clone(),
        redis: redis.clone(),
        config: cfg.clone(),
        apns: apns_client.clone(),
        encryption: encryption.clone(),
        key_exchange_service: Some(key_exchange_service),
    };
    // Start Redis Streams listener for cross-instance fanout
    let redis_stream = redis.clone();
    tokio::spawn(async move {
        let config = StreamsConfig::default();
        if let Err(e) = start_streams_listener(redis_stream, registry, config).await {
            tracing::warn!(error=%e, "redis streams listener exited");
        }
    });

    // Wrap db in Arc for sharing across middleware
    let db_arc = Arc::new(db);

    // Add DB pool to all request extensions via middleware
    // and apply JWT authentication middleware
    let app = routes::build_router()
        .with_state(state)
        .layer(middleware::from_fn(
            messaging_service::metrics::track_http_metrics,
        ))
        .layer(middleware::from_fn(
            move |mut req: Request, next: axum::middleware::Next| {
                let db = db_arc.clone();
                async move {
                    req.extensions_mut().insert(db);
                    next.run(req).await
                }
            },
        ));

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
