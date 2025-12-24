use actix_web::{web, App, HttpServer};
use anyhow::{Context, Result};
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use std::sync::Arc;
use tokio::sync::RwLock;
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
use crate::services::near_line::NearLineFeatureService;
use crate::services::online::OnlineFeatureStore;

/// Shared application state for health checks
struct HealthState {
    redis_healthy: RwLock<bool>,
    clickhouse_healthy: RwLock<bool>,
    postgres_healthy: RwLock<bool>,
}

impl HealthState {
    fn new() -> Self {
        Self {
            redis_healthy: RwLock::new(true),
            clickhouse_healthy: RwLock::new(true),
            postgres_healthy: RwLock::new(true),
        }
    }

    async fn is_ready(&self) -> bool {
        let redis = *self.redis_healthy.read().await;
        let clickhouse = *self.clickhouse_healthy.read().await;
        let postgres = *self.postgres_healthy.read().await;
        redis && clickhouse && postgres
    }
}

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
    // sqlx::migrate!(\"./migrations\") requires DATABASE_URL at compile time
    // For now, migrations must be run manually or via deployment scripts
    warn!("Manual migrations required - run: sqlx migrate run --database-url $DATABASE_URL");

    // Initialize Redis connection pool
    let redis_pool = redis_utils::RedisPool::connect(&config.redis_url, None)
        .await
        .context("Failed to create Redis pool")?;
    let redis_manager = redis_pool.manager();
    info!("Redis connection pool initialized");

    // Initialize ClickHouse client
    let clickhouse_client = clickhouse::Client::default()
        .with_url(&config.clickhouse_url)
        .with_user(&config.clickhouse_user)
        .with_password(&config.clickhouse_password)
        .with_database(&config.clickhouse_database);
    info!("ClickHouse client initialized");

    // Create OnlineFeatureStore
    let online_store = Arc::new(OnlineFeatureStore::new(redis_manager));
    info!("OnlineFeatureStore initialized");

    // Create NearLineFeatureService
    let near_line_service = Arc::new(NearLineFeatureService::new(
        clickhouse_client.clone(),
        pg_pool.clone(),
    ));
    info!("NearLineFeatureService initialized");

    // Create health state
    let health_state = Arc::new(HealthState::new());

    // Create AppState for gRPC service
    let app_state = Arc::new(grpc::AppState::new(
        online_store,
        near_line_service.clone(),
        pg_pool.clone(),
    ));

    // Compute HTTP and gRPC ports
    let http_port = config.http_port;
    let grpc_port = config.grpc_port;

    info!("HTTP port: {}, gRPC port: {}", http_port, grpc_port);

    // Start background health checker
    let health_state_clone = Arc::clone(&health_state);
    let near_line_service_clone = Arc::clone(&near_line_service);
    let pg_pool_clone = pg_pool.clone();
    let redis_manager_for_health = redis_pool.manager();

    tokio::spawn(async move {
        loop {
            // Check Redis
            let redis_ok = {
                let mut conn = redis_manager_for_health.lock().await;
                redis::cmd("PING")
                    .query_async::<_, String>(&mut *conn)
                    .await
                    .is_ok()
            };
            *health_state_clone.redis_healthy.write().await = redis_ok;

            // Check ClickHouse
            let clickhouse_ok = near_line_service_clone.health_check().await.unwrap_or(false);
            *health_state_clone.clickhouse_healthy.write().await = clickhouse_ok;

            // Check PostgreSQL
            let postgres_ok = sqlx::query("SELECT 1")
                .fetch_one(&pg_pool_clone)
                .await
                .is_ok();
            *health_state_clone.postgres_healthy.write().await = postgres_ok;

            tokio::time::sleep(tokio::time::Duration::from_secs(10)).await;
        }
    });

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

        // Load mTLS configuration
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

    let health_state_for_http = Arc::clone(&health_state);

    HttpServer::new(move || {
        let health_state = Arc::clone(&health_state_for_http);
        App::new()
            .app_data(web::Data::new(health_state))
            .route("/health", web::get().to(health_check))
            .route("/ready", web::get().to(readiness_check))
            .route("/metrics", web::get().to(metrics_handler))
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

async fn readiness_check(health_state: web::Data<Arc<HealthState>>) -> actix_web::HttpResponse {
    let redis = *health_state.redis_healthy.read().await;
    let clickhouse = *health_state.clickhouse_healthy.read().await;
    let postgres = *health_state.postgres_healthy.read().await;

    let is_ready = redis && clickhouse && postgres;

    let response = serde_json::json!({
        "status": if is_ready { "ready" } else { "not_ready" },
        "service": "feature-store",
        "checks": {
            "redis": if redis { "healthy" } else { "unhealthy" },
            "clickhouse": if clickhouse { "healthy" } else { "unhealthy" },
            "postgres": if postgres { "healthy" } else { "unhealthy" }
        }
    });

    if is_ready {
        actix_web::HttpResponse::Ok().json(response)
    } else {
        actix_web::HttpResponse::ServiceUnavailable().json(response)
    }
}

async fn metrics_handler() -> actix_web::HttpResponse {
    // TODO: Integrate with prometheus metrics
    // For now, return basic metrics in Prometheus format
    let metrics = r#"
# HELP feature_store_up Feature store service is up
# TYPE feature_store_up gauge
feature_store_up 1
"#;
    actix_web::HttpResponse::Ok()
        .content_type("text/plain; version=0.0.4")
        .body(metrics)
}
