use actix_web::{web, App, HttpServer};
use anyhow::{Context, Result};
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use std::sync::Arc;
use tonic::transport::Server as GrpcServer;
use tonic_health::server::health_reporter;
use tracing::{error, info, warn};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod config;
mod db;
mod error;
mod grpc;
mod models;
mod services;
mod utils;

use crate::config::Config;
use crate::services::online::OnlineFeatureStore;

#[actix_web::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=debug,feature_store=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    info!("Starting feature-store service");

    // Load configuration
    let config = Config::from_env().context("Failed to load configuration")?;
    config
        .validate()
        .context("Configuration validation failed")?;
    info!("Configuration loaded and validated");

    // Initialize PostgreSQL pool (standardized)
    let mut db_cfg = DbPoolConfig::for_service("feature-store");
    if db_cfg.database_url.is_empty() {
        db_cfg.database_url = config.database_url.clone();
    }
    if db_cfg.max_connections < 20 {
        db_cfg.max_connections = 20;
    }
    db_cfg.log_config();

    let pg_pool = create_pg_pool(db_cfg)
        .await
        .context("Failed to create PostgreSQL pool")?;
    info!("PostgreSQL connection pool created");

    // TODO: Run migrations
    // sqlx::migrate!("./migrations") requires DATABASE_URL at compile time
    // For now, migrations must be run manually or via deployment scripts
    warn!("Manual migrations required - run: sqlx migrate run --database-url $DATABASE_URL");

    // Initialize Redis connection pool
    let redis_pool = redis_utils::RedisPool::connect(&config.redis_url, None)
        .await
        .context("Failed to create Redis pool")?;
    let redis_manager = redis_pool.manager();
    info!("Redis connection pool initialized");

    // Initialize ClickHouse client (not used yet - placeholder for future implementation)
    let _clickhouse_client = clickhouse::Client::default()
        .with_url(&config.clickhouse_url)
        .with_database(&config.clickhouse_database);
    info!("ClickHouse client initialized");

    // Create OnlineFeatureStore
    let online_store = Arc::new(OnlineFeatureStore::new(redis_manager));
    info!("OnlineFeatureStore initialized");

    // Create AppState for gRPC service
    let app_state = Arc::new(grpc::AppState::new(online_store));

    // Compute HTTP and gRPC ports
    let http_port = config.http_port;
    let grpc_port = config.grpc_port;

    info!("HTTP port: {}, gRPC port: {}", http_port, grpc_port);

    // Start gRPC server in background
    let grpc_addr: std::net::SocketAddr = format!("0.0.0.0:{}", grpc_port)
        .parse()
        .expect("Failed to parse gRPC address");
    let app_state_clone = Arc::clone(&app_state);

    tokio::spawn(async move {
        let (mut health, health_service) = health_reporter();
        health
            .set_serving::<grpc::FeatureStoreServer<grpc::FeatureStoreImpl>>()
            .await;

        // Server-side correlation-id extractor interceptor
        fn server_interceptor(
            mut req: tonic::Request<()>,
        ) -> Result<tonic::Request<()>, tonic::Status> {
            if let Some(val) = req.metadata().get("correlation-id") {
                if let Ok(s) = val.to_str() {
                    let correlation_id = s.to_string();
                    req.extensions_mut().insert::<String>(correlation_id);
                }
            }
            Ok(req)
        }

        // ✅ P0-1: Load mTLS configuration
        let tls_config = match grpc_tls::GrpcServerTlsConfig::from_env() {
            Ok(config) => {
                info!("mTLS enabled - service-to-service authentication active");
                Some(config)
            }
            Err(e) => {
                warn!(
                    "mTLS disabled - TLS config not found: {}. Using development mode for testing only.",
                    e
                );
                if cfg!(debug_assertions) {
                    info!("Development mode: Starting without TLS (NOT FOR PRODUCTION)");
                    None
                } else {
                    error!("Production requires mTLS - GRPC_SERVER_CERT_PATH must be set");
                    return;
                }
            }
        };

        // Build server with optional TLS
        let mut server_builder = GrpcServer::builder();

        if let Some(tls_cfg) = tls_config {
            match tls_cfg.build_server_tls() {
                Ok(server_tls) => match server_builder.tls_config(server_tls) {
                    Ok(builder) => {
                        server_builder = builder;
                        info!("gRPC server TLS configured successfully");
                    }
                    Err(e) => {
                        error!("Failed to configure TLS on gRPC server: {}", e);
                        return;
                    }
                },
                Err(e) => {
                    error!("Failed to build server TLS config: {}", e);
                    return;
                }
            }
        }

        let svc = grpc::FeatureStoreImpl::new(app_state_clone);

        info!("Starting gRPC server on {}", grpc_addr);

        if let Err(e) = server_builder
            .add_service(health_service)
            .add_service(grpc::FeatureStoreServer::with_interceptor(
                svc,
                server_interceptor,
            ))
            .serve(grpc_addr)
            .await
        {
            error!("feature-store gRPC server error: {}", e);
        }
    });

    // Start HTTP server for health checks
    info!("Starting HTTP server on 0.0.0.0:{}", http_port);

    HttpServer::new(move || {
        App::new()
            .route("/health", web::get().to(health_check))
            .route("/ready", web::get().to(readiness_check))
    })
    .bind(("0.0.0.0", http_port))
    .context("Failed to bind HTTP server")?
    .run()
    .await
    .context("HTTP server error")
}

async fn health_check() -> actix_web::HttpResponse {
    actix_web::HttpResponse::Ok().json(serde_json::json!({
        "status": "healthy",
        "service": "feature-store"
    }))
}

async fn readiness_check() -> actix_web::HttpResponse {
    // TODO: Add actual readiness checks (Redis, ClickHouse, PostgreSQL)
    actix_web::HttpResponse::Ok().json(serde_json::json!({
        "status": "ready",
        "service": "feature-store"
    }))
}
