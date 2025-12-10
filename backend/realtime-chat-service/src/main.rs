#![recursion_limit = "512"]

use actix_web::{web, App, HttpServer};
use crypto_core::jwt as core_jwt;
use grpc_clients::AuthClient;
use grpc_tls::mtls::{MtlsClientConfig, TlsConfigPaths};
use realtime_chat_service::{
    config, db, error, grpc, handlers, logging,
    nova::realtime_chat::v1::realtime_chat_service_server::RealtimeChatServiceServer,
    redis_client::RedisClient,
    routes,
    services::{
        encryption::EncryptionService,
        key_exchange::KeyExchangeService,
        megolm_service::MegolmService,
        olm_service::{AccountEncryptionKey, OlmService},
    },
    state::AppState,
    websocket::streams::{start_streams_listener, StreamsConfig},
};
use redis_utils::{RedisPool, SentinelConfig};
use std::env;
use std::net::SocketAddr;
use std::path::PathBuf;
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

    // Initialize E2EE services (vodozemac Olm/Megolm)
    let (olm_service, megolm_service) = match AccountEncryptionKey::from_env() {
        Ok(encryption_key) => {
            // Copy key bytes for MegolmService before moving into OlmService
            let key_bytes = encryption_key.0;
            let olm = Arc::new(OlmService::new(db.clone(), encryption_key));
            let megolm = Arc::new(MegolmService::new(
                db.clone(),
                realtime_chat_service::services::megolm_service::AccountEncryptionKey::new(
                    key_bytes,
                ),
            ));
            tracing::info!("✅ E2EE services (Olm/Megolm) initialized");
            (Some(olm), Some(megolm))
        }
        Err(e) => {
            tracing::warn!(
                error = %e,
                "E2EE services disabled - OLM_ACCOUNT_KEY not set"
            );
            (None, None)
        }
    };

    // Initialize AuthClient (identity-service with mTLS)
    tracing::info!("Initializing Auth gRPC client");
    let identity_service_url = env::var("GRPC_IDENTITY_SERVICE_URL")
        .unwrap_or_else(|_| "https://identity-service:50051".to_string());

    // Build mTLS client config if certificates are available
    let auth_client = {
        let use_mtls = identity_service_url.starts_with("https://");

        let mut endpoint = Endpoint::from_shared(identity_service_url.clone())
            .map_err(|e| error::AppError::Config(format!("Invalid identity service URL: {}", e)))?
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(30))
            .tcp_keepalive(Some(Duration::from_secs(60)))
            .http2_keep_alive_interval(Duration::from_secs(30))
            .keep_alive_timeout(Duration::from_secs(10));

        if use_mtls {
            // Load mTLS client configuration from environment/paths
            // realtime-chat-service uses same certs for both server and client auth
            let ca_cert_path = env::var("GRPC_CA_CERT_PATH")
                .unwrap_or_else(|_| "/etc/grpc/certs/ca.crt".to_string());
            let server_cert_path = env::var("GRPC_SERVER_CERT_PATH")
                .unwrap_or_else(|_| "/etc/grpc/certs/server.crt".to_string());
            let server_key_path = env::var("GRPC_SERVER_KEY_PATH")
                .unwrap_or_else(|_| "/etc/grpc/certs/server.key".to_string());

            let tls_paths = TlsConfigPaths {
                ca_cert_path: PathBuf::from(&ca_cert_path),
                server_cert_path: PathBuf::from(&server_cert_path),
                server_key_path: PathBuf::from(&server_key_path),
                // Use server cert as client cert (same identity for internal services)
                client_cert_path: Some(PathBuf::from(&server_cert_path)),
                client_key_path: Some(PathBuf::from(&server_key_path)),
            };

            // Extract domain name from URL for TLS verification
            let domain_name = identity_service_url
                .replace("https://", "")
                .split(':')
                .next()
                .unwrap_or("identity-service")
                .to_string();

            match MtlsClientConfig::from_paths(tls_paths, domain_name).await {
                Ok(mtls_config) => {
                    let tls_config = mtls_config.build_client_tls().map_err(|e| {
                        error::AppError::StartServer(format!(
                            "Failed to build mTLS client config: {}",
                            e
                        ))
                    })?;
                    endpoint = endpoint.tls_config(tls_config).map_err(|e| {
                        error::AppError::StartServer(format!("Failed to configure TLS: {}", e))
                    })?;
                    tracing::info!("✅ mTLS client configured for identity-service");
                }
                Err(e) => {
                    tracing::warn!(
                        error = %e,
                        "Failed to load mTLS client config, falling back to plaintext (dev only)"
                    );
                }
            }
        }

        let channel = endpoint.connect_lazy();
        Arc::new(AuthClient::new(channel))
    };
    tracing::info!("✅ Auth gRPC client initialized (will connect on first use)");

    // Initialize Matrix client (optional, when MATRIX_ENABLED=true)
    let matrix_client = if cfg.matrix.enabled {
        match realtime_chat_service::services::matrix_client::MatrixClient::new(cfg.matrix.clone()).await {
            Ok(client) => {
                tracing::info!("✅ Matrix client initialized for homeserver: {}", cfg.matrix.homeserver_url);

                // Try to recover encryption keys from server-side backup
                if let Some(ref recovery_key) = cfg.matrix.recovery_key {
                    if !recovery_key.is_empty() {
                        match client.recover_keys(recovery_key).await {
                            Ok(()) => tracing::info!("✅ Matrix E2EE keys recovered from backup"),
                            Err(e) => tracing::warn!(error = %e, "Failed to recover Matrix E2EE keys (may be first run)"),
                        }
                    }
                } else {
                    tracing::info!("Matrix E2EE key backup not configured (MATRIX_RECOVERY_KEY not set)");
                    tracing::info!("  To enable: call enable_key_backup() and store the returned recovery key");
                }

                Some(Arc::new(client))
            }
            Err(e) => {
                tracing::error!(error = %e, "Failed to initialize Matrix client, continuing without Matrix");
                None
            }
        }
    } else {
        tracing::info!("Matrix integration disabled (MATRIX_ENABLED=false)");
        None
    };

    let state = AppState {
        db: db.clone(),
        registry: registry.clone(),
        redis: redis.clone(),
        config: cfg.clone(),
        encryption: encryption.clone(),
        key_exchange_service: Some(key_exchange_service),
        auth_client: auth_client.clone(),
        olm_service,
        megolm_service,
        matrix_client,
    };

    // Start Redis Streams listener for cross-instance fanout
    let redis_stream = redis.clone();
    let _streams_listener: JoinHandle<()> = tokio::spawn(async move {
        let config = StreamsConfig::default();
        if let Err(e) = start_streams_listener(redis_stream, registry, config).await {
            tracing::error!(error=%e, "redis streams listener failed");
        }
    });

    // Start Matrix sync loop (if Matrix is enabled)
    if let Some(ref matrix) = state.matrix_client {
        let matrix_clone = matrix.clone();
        let db_clone = db.clone();
        let registry_clone = Arc::new(state.registry.clone());
        let redis_clone = Arc::new(state.redis.clone());

        // Register VoIP event handler for Matrix call signaling
        let voip_handler = Arc::new(handlers::MatrixVoipEventHandler::new(
            db.clone(),
            registry_clone.clone(),
            redis_clone.clone(),
        ));
        matrix.register_voip_handler(voip_handler);
        tracing::info!("✅ Matrix VoIP event handler registered");

        let _matrix_sync_task: JoinHandle<()> = tokio::spawn(async move {
            tracing::info!("Starting Matrix sync loop");

            // Start sync loop with inline event handler
            if let Err(e) = matrix_clone.start_sync({
                let db = db_clone.clone();
                let registry = registry_clone.clone();
                let redis = redis_clone.clone();

                move |event, room| {
                    let db = db.clone();
                    let registry = registry.clone();
                    let redis = redis.clone();

                    tokio::spawn(async move {
                        if let Err(e) = realtime_chat_service::services::matrix_event_handler::handle_matrix_message_event(
                            &db,
                            &registry,
                            &redis,
                            room,
                            event,
                        )
                        .await
                        {
                            tracing::error!(error = %e, "Failed to handle Matrix message event");
                        }
                    });
                }
            }).await {
                tracing::error!(error = %e, "Matrix sync loop failed");
            }
        });

        tracing::info!("✅ Matrix sync loop started in background");
    }

    let bind_addr = format!("0.0.0.0:{}", cfg.port);
    tracing::info!(%bind_addr, "starting realtime-chat-service (REST on port {})", cfg.port);

    // Build gRPC service with mTLS
    let grpc_service = realtime_chat_service::grpc::RealtimeChatServiceImpl::new(state.clone());

    // Server-side correlation-id extractor interceptor
    #[allow(clippy::result_large_err)]
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

    // Check if TLS is enabled via environment variable
    let tls_enabled = env::var("GRPC_TLS_ENABLED")
        .map(|v| v.to_lowercase() == "true" || v == "1")
        .unwrap_or(false);

    // gRPC server with optional mTLS
    let grpc_addr: SocketAddr = format!("0.0.0.0:{}", cfg.grpc_port)
        .parse()
        .map_err(|e| error::AppError::Config(format!("Invalid gRPC address: {e}")))?;

    if tls_enabled {
        tracing::info!("Starting gRPC server with mTLS on {}", grpc_addr);
    } else {
        tracing::warn!(
            "gRPC server TLS is DISABLED on {}; enable GRPC_TLS_ENABLED=true for staging/production",
            grpc_addr
        );
    }

    // Spawn gRPC server in background (gRPC futures ARE Send)
    let grpc_server_task = tokio::spawn(async move {
        let (mut health_reporter, health_service) = tonic_health::server::health_reporter();
        health_reporter
            .set_serving::<RealtimeChatServiceServer<grpc::RealtimeChatServiceImpl>>()
            .await;

        if tls_enabled {
            // Load mTLS config and start with TLS
            let tls_config = grpc_tls::mtls::load_mtls_server_config()
                .await
                .map_err(|e| error::AppError::StartServer(format!("mTLS config: {e}")))?;

            GrpcServer::builder()
                .tls_config(tls_config)
                .map_err(|e| error::AppError::StartServer(format!("TLS setup: {e}")))?
                .add_service(grpc_server)
                .add_service(health_service)
                .serve(grpc_addr)
                .await
                .map_err(|e| error::AppError::StartServer(format!("run gRPC: {e}")))?;
        } else {
            // Start without TLS (development/testing only)
            GrpcServer::builder()
                .add_service(grpc_server)
                .add_service(health_service)
                .serve(grpc_addr)
                .await
                .map_err(|e| error::AppError::StartServer(format!("run gRPC: {e}")))?;
        }

        Ok::<_, error::AppError>(())
    });

    // REST server (WebSocket + HTTP endpoints)
    let rest_server_factory = move || {
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
            .service(routes::wsroute::ws_chat_alias)
            // API v2 routes (matches iOS APIConfig)
            .service(
                web::scope("/api/v2")
                    .configure(handlers::e2ee::configure)
                    .configure(routes::relationships::configure),
            )
            .route("/health", web::get().to(|| async { "OK" }))
    };

    let rest_server = HttpServer::new(rest_server_factory)
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
