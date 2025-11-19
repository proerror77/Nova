use actix_web::{web, App, HttpServer};
use crypto_core::jwt as core_jwt;
use grpc_clients::AuthClient;
use realtime_chat_service::{
    config, db, error, grpc, logging,
    nova::realtime_chat::v1::realtime_chat_service_server::RealtimeChatServiceServer,
    redis_client::RedisClient,
    routes,
    services::{encryption::EncryptionService, key_exchange::KeyExchangeService},
    state::AppState,
    websocket::streams::{start_streams_listener, StreamsConfig},
};
use redis_utils::{RedisPool, SentinelConfig};
use std::env;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::task::JoinHandle;
use tonic::transport::{Endpoint, Server as GrpcServer};

#[tokio::main]
async fn main() -> Result<(), error::AppError> {
    // Initialize rustls crypto provider
    if let Err(err) = rustls::crypto::aws_lc_rs::default_provider().install_default() {
        eprintln!("ERROR: failed to install rustls crypto provider: {:?}", err);
        return Err(error::AppError::StartServer(
            "failed to install rustls crypto provider".to_string(),
        ));
    }

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
    let registry = realtime_chat_service::websocket::ConnectionRegistry::new();

    // Initialize JWT validation using unified crypto-core helpers
    let public_key = core_jwt::load_validation_key()
        .map_err(|e| error::AppError::StartServer(format!("Failed to load JWT public key: {e}")))?;

    core_jwt::initialize_jwt_validation_only(&public_key).map_err(|e| {
        error::AppError::StartServer(format!("Failed to initialize JWT validation: {e}"))
    })?;

    let encryption = Arc::new(EncryptionService::new(cfg.encryption_master_key));
    let key_exchange_service = Arc::new(KeyExchangeService::new(Arc::new(db.clone())));

    // Initialize AuthClient (identity-service only - lazy connection)
    tracing::info!("Initializing Auth gRPC client (lazy connection)");
    let identity_service_url = env::var("GRPC_IDENTITY_SERVICE_URL")
        .unwrap_or_else(|_| "http://identity-service:50051".to_string());

    let identity_channel = Endpoint::from_shared(identity_service_url.clone())
        .map_err(|e| error::AppError::Config(format!("Invalid identity service URL: {}", e)))?
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(30))
        .tcp_keepalive(Some(Duration::from_secs(60)))
        .http2_keep_alive_interval(Duration::from_secs(30))
        .keep_alive_timeout(Duration::from_secs(10))
        .connect_lazy(); // Lazy connection - won't block startup

    let auth_client = Arc::new(AuthClient::new(identity_channel));
    tracing::info!("✅ Auth gRPC client initialized (will connect on first use)");

    let state = AppState {
        db: db.clone(),
        registry: registry.clone(),
        redis: redis.clone(),
        config: cfg.clone(),
        encryption: encryption.clone(),
        key_exchange_service: Some(key_exchange_service),
        auth_client: auth_client.clone(),
    };

    // Start Redis Streams listener for cross-instance fanout
    let redis_stream = redis.clone();
    let _streams_listener: JoinHandle<()> = tokio::spawn(async move {
        let config = StreamsConfig::default();
        if let Err(e) = start_streams_listener(redis_stream, registry, config).await {
            tracing::error!(error=%e, "redis streams listener failed");
        }
    });

    let bind_addr = format!("0.0.0.0:{}", cfg.port);
    tracing::info!(%bind_addr, "starting realtime-chat-service (REST on port {})", cfg.port);

    // Build gRPC service with mTLS
    let grpc_service = realtime_chat_service::grpc::RealtimeChatServiceImpl::new(state.clone());

    // Server-side correlation-id extractor interceptor
    fn grpc_server_interceptor(
        mut req: tonic::Request<()>,
    ) -> Result<tonic::Request<()>, tonic::Status> {
        if let Some(val) = req.metadata().get("correlation-id") {
            let correlation_id = val.to_str().map(|s| s.to_string()).ok();
            if let Some(id) = correlation_id {
                req.extensions_mut().insert::<String>(id);
            }
        }
        Ok(req)
    }
    let grpc_server =
        RealtimeChatServiceServer::with_interceptor(grpc_service, grpc_server_interceptor);

    // Start both REST and gRPC servers
    let rest_state = state.clone();
    let rest_db = db.clone();

    // gRPC server with mTLS
    let grpc_addr: SocketAddr = format!("0.0.0.0:{}", cfg.grpc_port)
        .parse()
        .map_err(|e| error::AppError::Config(format!("Invalid gRPC address: {e}")))?;

    tracing::info!("Starting gRPC server with mTLS on {}", grpc_addr);

    // Spawn gRPC server in background (gRPC futures ARE Send)
    let grpc_server_task = tokio::spawn(async move {
        let tls_config = grpc_tls::mtls::load_mtls_server_config()
            .await
            .map_err(|e| error::AppError::StartServer(format!("mTLS config: {e}")))?;

        let (mut health_reporter, health_service) = tonic_health::server::health_reporter();
        health_reporter
            .set_serving::<RealtimeChatServiceServer<grpc::RealtimeChatServiceImpl>>()
            .await;

        GrpcServer::builder()
            .tls_config(tls_config)
            .map_err(|e| error::AppError::StartServer(format!("TLS setup: {e}")))?
            .add_service(grpc_server)
            .add_service(health_service)
            .serve(grpc_addr)
            .await
            .map_err(|e| error::AppError::StartServer(format!("run gRPC: {e}")))?;

        Ok::<_, error::AppError>(())
    });

    // REST server (WebSocket + HTTP endpoints)
    // Run in foreground - actix-web HttpServer futures are NOT Send
    // So we run it directly instead of spawning with tokio::spawn
    let rest_server = HttpServer::new(move || {
        let cors = actix_cors::Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .max_age(3600);

        App::new()
            .wrap(cors)
            .wrap(actix_middleware::RequestId::new())
            .wrap(actix_middleware::Logging)
            .app_data(web::Data::new(rest_state.clone()))
            .app_data(web::Data::new(rest_db.clone()))
            .service(routes::messages::send_message)
            .service(routes::messages::get_messages)
            .service(routes::messages::edit_message)
            .service(routes::messages::delete_message)
            .service(routes::messages::recall_message)
            .service(routes::reactions::add_reaction)
            .service(routes::reactions::remove_reaction)
            .service(routes::conversations::create_conversation)
            .service(routes::conversations::get_conversation)
            .service(routes::conversations::get_conversations)
            .service(routes::conversations::update_conversation)
            .service(routes::groups::create_group)
            .service(routes::groups::add_member)
            .service(routes::groups::remove_member)
            .service(routes::groups::update_member_role)
            .service(routes::key_exchange::exchange_keys)
            .service(routes::key_exchange::get_public_key)
            .service(routes::calls::initiate_call)
            .service(routes::calls::answer_call)
            .service(routes::calls::reject_call)
            .service(routes::calls::end_call)
            .service(routes::calls::ice_candidate)
            .service(routes::calls::get_ice_servers)
            .service(routes::locations::share_location)
            .service(routes::locations::stop_sharing_location)
            .service(routes::locations::get_nearby_users)
            .service(routes::wsroute::ws_handler)
            .route("/health", web::get().to(|| async { "OK" }))
    })
    .bind(&bind_addr)
    .map_err(|e| error::AppError::StartServer(format!("bind REST: {e}")))?
    .run();

    // Run both servers concurrently
    tokio::select! {
        res = rest_server => {
            res.map_err(|e| error::AppError::StartServer(format!("REST server: {e}")))?;
            Ok(())
        }
        res = grpc_server_task => {
            res.map_err(|e| error::AppError::StartServer(format!("gRPC task join: {e}")))??;
            Ok(())
        }
    }
}
