/// Nova Auth Service - Main entry point
/// Provides both gRPC and REST API for authentication
mod metrics;
mod openapi;

use actix_middleware::{JwtAuthMiddleware, MetricsMiddleware};
use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use redis_utils::{RedisPool, SharedConnectionManager};
use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use tonic::transport::Server as GrpcServer;
use tonic_health::server::health_reporter;
use tracing_subscriber;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

use auth_service::{
    config::Config,
    handlers::{change_password, login, logout, refresh_token, register, request_password_reset},
    handlers::{complete_oauth_flow, start_oauth_flow},
    services::{
        email::EmailService,
        oauth::OAuthService,
        outbox::{spawn_outbox_consumer, OutboxConsumerConfig},
        two_fa::TwoFaService,
        KafkaEventProducer,
    },
    AppState,
};

#[actix_web::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Load configuration
    let config = Config::from_env()?;

    tracing::info!(
        "Starting Nova Auth Service on {}:{}",
        config.server_host,
        config.server_port
    );

    // Initialize database connection pool
    let mut pool_cfg = DbPoolConfig::from_env().unwrap_or_default();
    if pool_cfg.database_url.is_empty() {
        pool_cfg.database_url = config.database_url.clone();
    }
    pool_cfg.log_config();
    let db_pool = create_pg_pool(pool_cfg).await?;

    tracing::info!("Database connection pool initialized");

    // Run database migrations unless explicitly disabled
    let run_migrations = std::env::var("RUN_MIGRATIONS").unwrap_or_else(|_| "true".into());
    if run_migrations != "false" {
        tracing::info!("Running database migrations...");
        if let Err(err) = sqlx::migrate!("../migrations").run(&db_pool).await {
            tracing::error!("Database migration failed: {:#}", err);
            return Err(err.into());
        }
        tracing::info!("Database migrations completed");
    } else {
        tracing::info!("Skipping database migrations (RUN_MIGRATIONS=false)");
    }

    // Initialize Redis connection pool
    let redis_pool = RedisPool::connect(&config.redis_url, None)
        .await
        .map_err(|e| format!("Failed to initialize Redis pool: {:#}", e))?;
    let redis_manager = redis_pool.manager();

    tracing::info!("Redis connection initialized");

    // Spawn metrics updater for outbox backlog gauge
    crate::metrics::spawn_metrics_updater(db_pool.clone());

    // Initialize JWT keys from environment variables (with file fallback support)
    // Use shared crypto-core helpers for consistent key loading across services
    let (private_key, public_key) = crypto_core::jwt::load_signing_keys()
        .map_err(|e| format!("Failed to load JWT keys from environment: {}", e))?;

    crypto_core::jwt::initialize_jwt_keys(&private_key, &public_key)
        .map_err(|e| format!("Failed to initialize JWT keys: {}", e))?;

    tracing::info!("JWT keys initialized");

    // Initialize Kafka event producer (optional)
    let kafka_producer = match std::env::var("KAFKA_BROKERS") {
        Ok(brokers) => match KafkaEventProducer::new(&brokers, "auth-events") {
            Ok(producer) => {
                tracing::info!("Kafka event producer initialized");
                Some(producer)
            }
            Err(e) => {
                tracing::warn!("Failed to initialize Kafka producer: {}", e);
                None
            }
        },
        Err(_) => {
            tracing::warn!("KAFKA_BROKERS environment variable not set, event publishing disabled");
            None
        }
    };

    let email_service = EmailService::new(&config.email).map_err(|e| {
        tracing::error!("Failed to initialize email service: {}", e);
        Box::new(e) as Box<dyn std::error::Error>
    })?;

    let two_fa_service = TwoFaService::new(
        db_pool.clone(),
        redis_manager.clone(),
        kafka_producer.clone(),
    );

    let oauth_service = Arc::new(OAuthService::new(
        config.oauth.clone(),
        db_pool.clone(),
        redis_manager.clone(),
        kafka_producer.clone(),
    ));

    let _outbox_handle = spawn_outbox_consumer(
        db_pool.clone(),
        kafka_producer.clone(),
        OutboxConsumerConfig::default(),
    );

    // Create shared application state
    let app_state = AppState {
        db: db_pool.clone(),
        redis: redis_manager.clone(),
        kafka_producer,
        email_service: email_service.clone(),
        oauth_service: oauth_service.clone(),
        two_fa_service: two_fa_service.clone(),
    };

    // Build gRPC service
    let grpc_service = build_grpc_service(app_state.clone())?;

    // Start both servers
    start_servers(
        app_state,
        grpc_service,
        &config.server_host,
        config.server_port,
    )
    .await?;

    Ok(())
}

/// Health check endpoint
async fn health_check() -> impl Responder {
    HttpResponse::Ok().body("OK")
}

/// Readiness check endpoint
async fn readiness_check() -> impl Responder {
    HttpResponse::Ok().body("READY")
}

/// OpenAPI 規格輸出
async fn openapi_json(doc: web::Data<utoipa::openapi::OpenApi>) -> HttpResponse {
    match serde_json::to_string(&*doc) {
        Ok(body) => HttpResponse::Ok()
            .content_type("application/json")
            .body(body),
        Err(e) => {
            tracing::error!("failed to serialize OpenAPI document: {}", e);
            HttpResponse::InternalServerError().body("Failed to serialize OpenAPI specification")
        }
    }
}

/// Build gRPC service
fn build_grpc_service(
    app_state: AppState,
) -> Result<
    auth_service::nova::auth_service::auth_service_server::AuthServiceServer<
        auth_service::grpc::AuthServiceImpl,
    >,
    Box<dyn std::error::Error>,
> {
    let auth_service = auth_service::grpc::AuthServiceImpl::new(app_state);
    Ok(auth_service::nova::auth_service::auth_service_server::AuthServiceServer::new(auth_service))
}

/// Configure REST API routes
fn configure_routes(cfg: &mut web::ServiceConfig, redis: SharedConnectionManager) {
    let openapi = openapi::ApiDoc::openapi();

    cfg.app_data(web::Data::new(openapi.clone()))
        .service(SwaggerUi::new("/swagger-ui/{_:.*}").url("/api/v1/openapi.json", openapi))
        .route("/api/v1/openapi.json", web::get().to(openapi_json))
        .service(
            web::scope("/api/v1")
                .service(
                    web::scope("/auth")
                        .route("/register", web::post().to(register))
                        .route("/login", web::post().to(login))
                        .route("/refresh", web::post().to(refresh_token))
                        .route(
                            "/password-reset/request",
                            web::post().to(request_password_reset),
                        )
                        .service(
                            web::scope("")
                                .wrap(JwtAuthMiddleware::with_cache(redis.clone(), 600))
                                .route("/logout", web::post().to(logout))
                                .route("/change-password", web::post().to(change_password)),
                        ),
                )
                .service(
                    web::scope("/oauth")
                        .route("/start", web::post().to(start_oauth_flow))
                        .route("/complete", web::post().to(complete_oauth_flow)),
                ),
        )
        .route("/health", web::get().to(health_check))
        .route("/readiness", web::get().to(readiness_check))
        .route("/metrics", web::get().to(metrics::metrics_handler));
}

/// Start both REST and gRPC servers
async fn start_servers(
    app_state: AppState,
    grpc_service: auth_service::nova::auth_service::auth_service_server::AuthServiceServer<
        auth_service::grpc::AuthServiceImpl,
    >,
    host: &str,
    port: u16,
) -> Result<(), Box<dyn std::error::Error>> {
    let addr: SocketAddr = format!("{}:{}", host, port).parse()?;

    // Clone state for REST server
    let rest_state = app_state.clone();

    let rest_server_state = rest_state.clone();
    let rest_server = HttpServer::new(move || {
        let state = rest_server_state.clone();
        let redis_for_routes = state.redis.clone();
        App::new()
            .app_data(web::Data::new(state))
            .wrap(MetricsMiddleware)
            .configure(move |cfg| configure_routes(cfg, redis_for_routes.clone()))
    })
    .bind(addr)?
    .run();

    tracing::info!("REST API listening on {}", addr);

    let rest_handle = rest_server.handle();
    let mut http_handle = Some(tokio::spawn(rest_server));

    // gRPC server on port `port + 1000`
    let grpc_addr = format!("{}:{}", host, port + 1000).parse()?;
    tracing::info!("gRPC server listening on {}", grpc_addr);

    let (grpc_shutdown_tx, grpc_shutdown_rx) = tokio::sync::oneshot::channel();

    let mut grpc_handle = Some(tokio::spawn(async move {
        // Health service
        let (mut health, health_service) = health_reporter();
        health
            .set_serving::<auth_service::nova::auth_service::auth_service_server::AuthServiceServer<
                auth_service::grpc::AuthServiceImpl,
            >>()
            .await;

        // Server-side correlation-id extractor interceptor
        fn server_interceptor(
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

        // Wrap service with interceptor (rebuild from implementation not available here), so we rely on Server::builder add layer? As workaround, add without wrapping.
        match GrpcServer::builder()
            .add_service(health_service)
            .add_service(grpc_service)
            .serve_with_shutdown(grpc_addr, async {
                let _ = grpc_shutdown_rx.await;
            })
            .await
        {
            Ok(_) => {
                tracing::info!("gRPC server exited normally");
                Ok(())
            }
            Err(e) => {
                tracing::error!("gRPC server error: {}", e);
                Err(())
            }
        }
    }));

    let mut grpc_shutdown_tx = Some(grpc_shutdown_tx);
    let mut shutdown_signal = Box::pin(async {
        tokio::signal::ctrl_c()
            .await
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))
    });

    let mut shutdown_initiated = false;
    let result = loop {
        tokio::select! {
            http_res = async {
                if let Some(handle) = &mut http_handle {
                    Some(handle.await)
                } else {
                    None
                }
            }, if http_handle.is_some() => {
                let join_res = http_res.expect("HTTP join result");
                http_handle = None;
                tracing::info!("REST server exited");
                let http_result = match join_res {
                    Ok(inner) => inner,
                    Err(e) => Err(io::Error::new(io::ErrorKind::Other, e.to_string())),
                };
                break http_result;
            }
            grpc_res = async {
                if let Some(handle) = &mut grpc_handle {
                    Some(handle.await)
                } else {
                    None
                }
            }, if grpc_handle.is_some() => {
                let join_res = grpc_res.expect("gRPC join result");
                grpc_handle = None;
                tracing::info!("gRPC server exited");
                let grpc_result = match join_res {
                    Ok(Ok(())) => Ok(()),
                    Ok(Err(())) => Err(io::Error::new(io::ErrorKind::Other, "gRPC server error")),
                    Err(e) => Err(io::Error::new(io::ErrorKind::Other, e.to_string())),
                };
                break grpc_result;
            }
            sig = &mut shutdown_signal => {
                match sig {
                    Ok(()) => tracing::info!("Shutdown signal received; stopping auth service"),
                    Err(e) => {
                        tracing::error!("Failed to listen for shutdown signal: {}", e);
                        break Err(io::Error::new(e.kind(), e.to_string()));
                    }
                }

                if !shutdown_initiated {
                    shutdown_initiated = true;
                    rest_handle.stop(true).await;
                    if let Some(tx) = grpc_shutdown_tx.take() {
                        let _ = tx.send(());
                    }
                }
            }
        }
    };

    if !shutdown_initiated {
        rest_handle.stop(true).await;
        if let Some(tx) = grpc_shutdown_tx.take() {
            let _ = tx.send(());
        }
    }

    if let Some(handle) = http_handle {
        if let Err(e) = tokio::time::timeout(std::time::Duration::from_secs(5), handle).await {
            tracing::warn!("REST server did not shut down within timeout: {}", e);
        }
    }

    if let Some(handle) = grpc_handle {
        match tokio::time::timeout(std::time::Duration::from_secs(5), handle).await {
            Ok(join_res) => {
                if let Err(e) = join_res {
                    tracing::warn!("gRPC server join error after shutdown: {}", e);
                }
            }
            Err(_) => {
                tracing::warn!("gRPC server did not shut down within timeout");
            }
        }
    }

    result.map_err(|e| e.into())
}
