/// Nova Auth Service - Main entry point
/// Provides both gRPC and REST API for authentication

mod metrics;
mod routes;

use axum::{
    middleware,
    routing::{get, post},
    Router,
};
use redis::aio::ConnectionManager;
use sqlx::postgres::PgPoolOptions;
use std::net::SocketAddr;
use tokio::net::TcpListener;
use tonic::transport::Server as GrpcServer;
use tower_http::trace::TraceLayer;
use tracing_subscriber;

use auth_service::{
    config::Config,
    handlers::{register, login, logout, refresh_token, change_password, request_password_reset},
    handlers::{start_oauth_flow, complete_oauth_flow},
    services::KafkaEventProducer,
    AppState,
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Load configuration
    let config = Config::from_env()
        .expect("Failed to load configuration from environment");

    tracing::info!("Starting Nova Auth Service on {}:{}", config.server_host, config.server_port);

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
    crypto_core::jwt::initialize_jwt_keys(
        &config.jwt_private_key_pem,
        &config.jwt_public_key_pem,
    ).map_err(|e| format!("Failed to initialize JWT keys: {}", e))?;

    tracing::info!("JWT keys initialized");

    // Initialize Kafka event producer (optional)
    let kafka_producer = match std::env::var("KAFKA_BROKERS") {
        Ok(brokers) => {
            match KafkaEventProducer::new(&brokers, "auth-events") {
                Ok(producer) => {
                    tracing::info!("Kafka event producer initialized");
                    Some(producer)
                }
                Err(e) => {
                    tracing::warn!("Failed to initialize Kafka producer: {}", e);
                    None
                }
            }
        }
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

    // Build REST API router
    let rest_router = Router::new()
        // Authentication endpoints
        .route("/api/v1/auth/register", post(register))
        .route("/api/v1/auth/login", post(login))
        .route("/api/v1/auth/logout", post(logout))
        .route("/api/v1/auth/refresh", post(refresh_token))
        .route("/api/v1/auth/change-password", post(change_password))
        .route("/api/v1/auth/password-reset/request", post(request_password_reset))

        // OAuth endpoints
        .route("/api/v1/oauth/start", post(start_oauth_flow))
        .route("/api/v1/oauth/complete", post(complete_oauth_flow))

        // Health check
        .route("/health", get(health_check))
        .route("/readiness", get(readiness_check))
        .route("/metrics", get(metrics::metrics_handler))

        .layer(middleware::from_fn(metrics::track_http_metrics))
        .layer(TraceLayer::new_for_http())
        .with_state(app_state.clone());

    // Build gRPC server
    let grpc_service = build_grpc_service(app_state)?;

    // Start both servers
    start_servers(
        rest_router,
        grpc_service,
        &config.server_host,
        config.server_port,
    )
    .await?;

    Ok(())
}

/// Health check endpoint
async fn health_check() -> &'static str {
    "OK"
}

/// Readiness check endpoint
async fn readiness_check() -> &'static str {
    "READY"
}

/// Build gRPC service
fn build_grpc_service(
    app_state: AppState,
) -> Result<auth_service::nova::auth::v1::auth_service_server::AuthServiceServer<
    auth_service::grpc::AuthServiceImpl,
>, Box<dyn std::error::Error>> {
    let auth_service = auth_service::grpc::AuthServiceImpl::new(app_state);
    Ok(auth_service::nova::auth::v1::auth_service_server::AuthServiceServer::new(auth_service))
}

/// Start both REST and gRPC servers
async fn start_servers(
    rest_router: Router,
    grpc_service: auth_service::nova::auth::v1::auth_service_server::AuthServiceServer<
        auth_service::grpc::AuthServiceImpl,
    >,
    host: &str,
    port: u16,
) -> Result<(), Box<dyn std::error::Error>> {
    let addr: SocketAddr = format!("{}:{}", host, port).parse()?;

    // REST API server on port `port`
    let rest_listener = TcpListener::bind(&addr).await?;
    tracing::info!("REST API listening on {}", addr);

    let rest_handle = tokio::spawn(async move {
        axum::serve(rest_listener, rest_router)
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
