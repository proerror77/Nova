use actix_web::{web, App, HttpServer};
use crypto_core::jwt as core_jwt;
use grpc_clients::{config::GrpcConfig, AuthClient, GrpcClientPool};
use messaging_service::openapi::ApiDoc;
use messaging_service::{
    config, db, error, logging,
    nova::messaging_service::messaging_service_server::MessagingServiceServer,
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
use tokio::task::JoinHandle;
use tonic::transport::Server as GrpcServer;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

async fn openapi_json(
    doc: web::Data<utoipa::openapi::OpenApi>,
) -> actix_web::Result<actix_web::HttpResponse> {
    let body = serde_json::to_string(&*doc).map_err(|e| {
        tracing::error!("OpenAPI serialization failed: {}", e);
        actix_web::error::ErrorInternalServerError("OpenAPI serialization error")
    })?;

    Ok(actix_web::HttpResponse::Ok()
        .content_type("application/json")
        .body(body))
}

#[actix_web::main]
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
    // Treat migration failures as fatal - the database schema must be in sync
    messaging_service::migrations::run_all(&db)
        .await
        .map_err(|e| error::AppError::StartServer(format!("database migrations failed: {}", e)))?;

    // Initialize JWT validation using unified crypto-core helpers
    // Supports both JWT_PUBLIC_KEY_PEM and JWT_PUBLIC_KEY_FILE environment variables
    let public_key = core_jwt::load_validation_key()
        .map_err(|e| error::AppError::StartServer(format!("Failed to load JWT public key: {e}")))?;

    core_jwt::initialize_jwt_validation_only(&public_key).map_err(|e| {
        error::AppError::StartServer(format!("Failed to initialize JWT validation: {e}"))
    })?;

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

    // Phase 1: Spec 007 - Initialize gRPC client pool with connection pooling
    tracing::info!("Initializing gRPC client pool with connection pooling");
    let grpc_config = GrpcConfig::from_env()
        .map_err(|e| error::AppError::Config(format!("Failed to load gRPC config: {}", e)))?;
    let grpc_pool = Arc::new(
        GrpcClientPool::new(&grpc_config)
            .await
            .expect("Failed to create gRPC client pool"),
    );

    // Initialize AuthClient from connection pool
    let auth_client = Arc::new(AuthClient::from_pool(grpc_pool.clone()));
    tracing::info!("✅ Auth-service gRPC client initialized from connection pool");

    let state = AppState {
        db: db.clone(),
        registry: registry.clone(),
        redis: redis.clone(),
        config: cfg.clone(),
        apns: apns_client.clone(),
        encryption: encryption.clone(),
        key_exchange_service: Some(key_exchange_service),
        auth_client: auth_client.clone(),
    };

    // Metrics updater (queue depth gauges)
    messaging_service::metrics::spawn_metrics_updater(db.clone());

    // Start Redis Streams listener for cross-instance fanout
    // Keep track of the listener task for graceful shutdown
    let redis_stream = redis.clone();
    let _streams_listener: JoinHandle<()> = tokio::spawn(async move {
        let config = StreamsConfig::default();
        if let Err(e) = start_streams_listener(redis_stream, registry, config).await {
            tracing::error!(error=%e, "redis streams listener failed");
        }
    });

    let bind_addr = format!("0.0.0.0:{}", cfg.port);
    tracing::info!(%bind_addr, "starting messaging-service (REST on port {})", cfg.port);

    // Build gRPC service
    let grpc_service = messaging_service::grpc::MessagingServiceImpl::new(state.clone());
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
        MessagingServiceServer::with_interceptor(grpc_service, grpc_server_interceptor);

    // Start both REST and gRPC servers
    let rest_state = state.clone();
    let rest_db = db.clone();

    // REST API server on cfg.port
    // CRITICAL: HttpServer must be created outside tokio::spawn to avoid Send issues
    // Only the .run() future (which is Send) goes into spawn
    let bind_addr_parsed: SocketAddr =
        bind_addr.parse().map_err(|e: std::net::AddrParseError| {
            error::AppError::StartServer(format!("Invalid bind address: {}", e))
        })?;

    tracing::info!("REST API listening on {}", bind_addr_parsed);

    let rest_server = HttpServer::new(move || {
        let openapi_doc = ApiDoc::openapi();

        App::new()
            .app_data(web::Data::new(openapi_doc.clone()))
            .service(
                SwaggerUi::new("/swagger-ui/{_:.*}")
                    .url("/api/v1/openapi.json", openapi_doc.clone()),
            )
            .route("/api/v1/openapi.json", web::get().to(openapi_json))
            .app_data(web::Data::new(rest_state.clone()))
            .app_data(web::Data::new(rest_db.clone()))
            .configure(routes::configure_routes)
            .wrap(actix_middleware::CorrelationIdMiddleware)
            .wrap(actix_middleware::MetricsMiddleware)
    })
    .bind(&bind_addr_parsed)
    .map_err(|e| error::AppError::StartServer(format!("Failed to bind REST server: {}", e)))?
    .run();

    // Now spawn only the Server future (which IS Send)
    let rest_handle = tokio::spawn(async move {
        rest_server
            .await
            .map_err(|e| error::AppError::StartServer(format!("REST server error: {}", e)))
    });

    // Phase 1: Spec 007 - Start orphan cleaner background job
    // Cleans up conversation_members for soft-deleted users after 30-day retention period
    let orphan_cleaner_db = db.clone();
    let orphan_cleaner_auth = auth_client.clone();
    let _orphan_cleaner_handle: JoinHandle<()> = tokio::spawn(async move {
        messaging_service::jobs::start_orphan_cleaner(orphan_cleaner_db, orphan_cleaner_auth).await;
    });
    tracing::info!("Orphan cleaner background job started");

    // gRPC server on cfg.port + 1000 (e.g., 8080 -> 9080)
    let grpc_addr = format!("0.0.0.0:{}", cfg.port + 1000);
    let grpc_handle = tokio::spawn(async move {
        let grpc_addr_parsed: SocketAddr =
            grpc_addr.parse().map_err(|e: std::net::AddrParseError| {
                tracing::error!("Invalid gRPC address: {}", e);
            })?;

        tracing::info!("gRPC server listening on {}", grpc_addr_parsed);

        let (mut health, health_service) = tonic_health::server::health_reporter();
        health
            .set_serving::<MessagingServiceServer<messaging_service::grpc::MessagingServiceImpl>>()
            .await;
        GrpcServer::builder()
            .add_service(health_service)
            .add_service(grpc_server)
            .serve(grpc_addr_parsed)
            .await
            .map_err(|e| {
                tracing::error!("gRPC server error: {}", e);
            })
    });

    // Wait for either server to exit
    tokio::select! {
        result = rest_handle => {
            match result {
                Ok(Ok(())) => tracing::info!("REST server exited normally"),
                Ok(Err(e)) => {
                    tracing::error!("REST server error: {:?}", e);
                    return Err(e);
                }
                Err(e) => {
                    tracing::error!("REST server task error: {}", e);
                    return Err(error::AppError::StartServer(format!("REST server task error: {}", e)));
                }
            }
        }
        result = grpc_handle => {
            match result {
                Ok(Ok(())) => tracing::info!("gRPC server exited normally"),
                Ok(Err(())) => tracing::error!("gRPC server exited with error"),
                Err(e) => {
                    tracing::error!("gRPC server task error: {}", e);
                    return Err(error::AppError::StartServer(format!("gRPC server task error: {}", e)));
                }
            }
        }
    }

    // Note: When server exits, the _streams_listener task is still running.
    // In a production deployment with graceful shutdown handlers, you would
    // implement a shutdown signal (e.g., Ctrl+C) to abort this task properly.
    // For now, it will be implicitly dropped when main() exits.

    Ok(())
}
