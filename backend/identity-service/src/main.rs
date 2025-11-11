use anyhow::{Context, Result};
use std::sync::Arc;
use tonic::transport::Server;
use tonic_health::server::{health_reporter, HealthReporter};
use tracing::{info, warn};

mod config;
mod domain;
mod grpc;
mod infrastructure;
mod application;

use config::Settings;
use infrastructure::{database::DatabasePool, cache::CacheManager, events::EventPublisher};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter("identity_service=debug,info")
        .with_target(false)
        .json()
        .init();

    info!("Starting Identity Service v2.0.0");

    // Load configuration
    let settings = Settings::load()?;

    // Initialize database pool with proper timeouts
    let db_pool = DatabasePool::new(&settings.database)
        .await
        .context("Failed to create database pool")?;

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(db_pool.get())
        .await
        .context("Failed to run database migrations")?;

    // Initialize cache manager
    let cache_manager = Arc::new(
        CacheManager::new(&settings.redis)
            .await
            .context("Failed to initialize cache manager")?
    );

    // Initialize event publisher (Kafka)
    let event_publisher = Arc::new(
        EventPublisher::new(&settings.kafka)
            .await
            .context("Failed to initialize event publisher")?
    );

    // Create application services
    let auth_service = Arc::new(
        application::AuthenticationService::new(
            db_pool.clone(),
            cache_manager.clone(),
            event_publisher.clone(),
            settings.jwt.clone(),
        )
    );

    let session_service = Arc::new(
        application::SessionService::new(
            db_pool.clone(),
            cache_manager.clone(),
            event_publisher.clone(),
        )
    );

    let token_service = Arc::new(
        application::TokenService::new(
            db_pool.clone(),
            cache_manager.clone(),
            settings.jwt.clone(),
        )
    );

    // Create gRPC server
    let identity_impl = grpc::IdentityServiceImpl::new(
        auth_service,
        session_service,
        token_service,
    );

    let addr = format!("{}:{}", settings.server.host, settings.server.port)
        .parse()
        .context("Failed to parse server address")?;

    info!("Identity Service listening on {}", addr);

    // ✅ P0-4: Create gRPC health reporter
    let (mut health_reporter, health_service) = health_reporter();

    // Mark service as SERVING
    health_reporter
        .set_serving::<grpc::identity_service_server::IdentityServiceServer<grpc::IdentityServiceImpl>>()
        .await;

    info!("gRPC health check enabled (tonic-health protocol)");

    // Start health check endpoint (HTTP)
    tokio::spawn(health_check_server(settings.server.health_port));

    // Start metrics endpoint
    tokio::spawn(metrics_server(settings.server.metrics_port));

    // ✅ P0-1: Load mTLS configuration
    let tls_config = match grpc_tls::GrpcServerTlsConfig::from_env() {
        Ok(config) => {
            info!("mTLS enabled - service-to-service authentication active");
            Some(config)
        }
        Err(e) => {
            warn!("mTLS disabled - TLS config not found: {}. Using development mode for testing only.", e);
            // In development, allow non-TLS for testing
            // In production, this should fail hard
            if cfg!(debug_assertions) {
                info!("Development mode: Starting without TLS (NOT FOR PRODUCTION)");
                None
            } else {
                return Err(e).context("Production requires mTLS - GRPC_SERVER_CERT_PATH must be set");
            }
        }
    };

    // Build server with optional TLS
    let mut server_builder = Server::builder();

    if let Some(tls_cfg) = tls_config {
        let server_tls = tls_cfg
            .build_server_tls()
            .context("Failed to build server TLS config")?;
        server_builder = server_builder
            .tls_config(server_tls)
            .context("Failed to configure TLS on gRPC server")?;
        info!("gRPC server TLS configured successfully");
    }

    // Start gRPC server with graceful shutdown
    server_builder
        .add_service(health_service)  // ✅ P0-4: Add health service
        .add_service(grpc::identity_service_server::IdentityServiceServer::new(identity_impl))
        .add_service(tonic_reflection::server::Builder::configure()
            .register_encoded_file_descriptor_set(grpc::FILE_DESCRIPTOR_SET)
            .build()?)
        .serve_with_shutdown(addr, shutdown_signal())
        .await
        .context("Failed to start gRPC server")?;

    info!("Identity Service shutting down gracefully");
    Ok(())
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c()
        .await
        .expect("Failed to install CTRL+C signal handler");
    warn!("Received shutdown signal");
}

async fn health_check_server(port: u16) {
    use actix_web::{web, App, HttpResponse, HttpServer};

    HttpServer::new(|| {
        App::new()
            .route("/health", web::get().to(|| async {
                HttpResponse::Ok().json(serde_json::json!({
                    "status": "healthy",
                    "service": "identity-service",
                    "version": "2.0.0"
                }))
            }))
            .route("/ready", web::get().to(|| async {
                HttpResponse::Ok().json(serde_json::json!({
                    "ready": true
                }))
            }))
    })
    .bind(("0.0.0.0", port))
    .expect("Failed to bind health check server")
    .run()
    .await
    .expect("Failed to run health check server");
}

async fn metrics_server(port: u16) {
    use actix_web::{web, App, HttpResponse, HttpServer};
    use prometheus::{Encoder, TextEncoder};

    HttpServer::new(|| {
        App::new()
            .route("/metrics", web::get().to(|| async {
                let encoder = TextEncoder::new();
                let metric_families = prometheus::gather();
                let mut buffer = Vec::new();
                encoder.encode(&metric_families, &mut buffer).unwrap();
                HttpResponse::Ok()
                    .content_type("text/plain; version=0.0.4")
                    .body(buffer)
            }))
    })
    .bind(("0.0.0.0", port))
    .expect("Failed to bind metrics server")
    .run()
    .await
    .expect("Failed to run metrics server");
}