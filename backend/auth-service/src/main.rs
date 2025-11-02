/// Nova Auth Service - Main entry point
/// Provides both gRPC and REST API for authentication
mod metrics;

use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use actix_middleware::MetricsMiddleware;
use redis::aio::ConnectionManager;
use sqlx::postgres::PgPoolOptions;
use std::net::SocketAddr;
use tonic::transport::Server as GrpcServer;
use tracing_subscriber;

use auth_service::{
    config::Config,
    handlers::{change_password, login, logout, refresh_token, register, request_password_reset},
    handlers::{complete_oauth_flow, start_oauth_flow},
    services::KafkaEventProducer,
    AppState,
};

#[actix_web::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Load configuration
    let config = Config::from_env().expect("Failed to load configuration from environment");

    tracing::info!(
        "Starting Nova Auth Service on {}:{}",
        config.server_host,
        config.server_port
    );

    // Initialize database connection pool
    let database_url = config.database_url.clone();
    let db_pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await?;

    tracing::info!("Database connection pool initialized");

    // Initialize Redis connection
    let redis_client = redis::Client::open(config.redis_url.clone())?;
    let redis_conn = ConnectionManager::new(redis_client).await?;

    tracing::info!("Redis connection initialized");

    // Initialize JWT keys from shared crypto-core library
    crypto_core::jwt::initialize_jwt_keys(&config.jwt_private_key_pem, &config.jwt_public_key_pem)
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

    // Create shared application state
    let app_state = AppState {
        db: db_pool.clone(),
        redis: redis_conn,
        kafka_producer,
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

/// Build gRPC service
fn build_grpc_service(
    app_state: AppState,
) -> Result<
    auth_service::nova::auth::v1::auth_service_server::AuthServiceServer<
        auth_service::grpc::AuthServiceImpl,
    >,
    Box<dyn std::error::Error>,
> {
    let auth_service = auth_service::grpc::AuthServiceImpl::new(app_state);
    Ok(auth_service::nova::auth::v1::auth_service_server::AuthServiceServer::new(auth_service))
}

/// Configure REST API routes
fn configure_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api/v1")
            .service(
                web::scope("/auth")
                    .route("/register", web::post().to(register))
                    .route("/login", web::post().to(login))
                    .route("/logout", web::post().to(logout))
                    .route("/refresh", web::post().to(refresh_token))
                    .route("/change-password", web::post().to(change_password))
                    .route("/password-reset/request", web::post().to(request_password_reset))
            )
            .service(
                web::scope("/oauth")
                    .route("/start", web::post().to(start_oauth_flow))
                    .route("/complete", web::post().to(complete_oauth_flow))
            )
    )
    .route("/health", web::get().to(health_check))
    .route("/readiness", web::get().to(readiness_check))
    .route("/metrics", web::get().to(metrics::metrics_handler));
}

/// Start both REST and gRPC servers
async fn start_servers(
    app_state: AppState,
    grpc_service: auth_service::nova::auth::v1::auth_service_server::AuthServiceServer<
        auth_service::grpc::AuthServiceImpl,
    >,
    host: &str,
    port: u16,
) -> Result<(), Box<dyn std::error::Error>> {
    let addr: SocketAddr = format!("{}:{}", host, port).parse()?;

    // Clone state for REST server
    let rest_state = app_state.clone();

    // REST API server on port `port`
    let rest_handle = tokio::spawn(async move {
        tracing::info!("REST API listening on {}", addr);

        HttpServer::new(move || {
            App::new()
                .app_data(web::Data::new(rest_state.clone()))
                .wrap(MetricsMiddleware)
                .configure(configure_routes)
        })
        .bind(addr)
        .expect("Failed to bind REST server")
        .run()
        .await
        .expect("REST server failed");
    });

    // gRPC server on port `port + 1000`
    let grpc_addr = format!("{}:{}", host, port + 1000).parse()?;
    tracing::info!("gRPC server listening on {}", grpc_addr);

    let grpc_handle = tokio::spawn(async move {
        GrpcServer::builder()
            .add_service(grpc_service)
            .serve(grpc_addr)
            .await
            .expect("gRPC server failed");
    });

    // Wait for both servers
    tokio::select! {
        _ = rest_handle => {
            tracing::error!("REST server stopped");
        }
        _ = grpc_handle => {
            tracing::error!("gRPC server stopped");
        }
    }

    Ok(())
}
