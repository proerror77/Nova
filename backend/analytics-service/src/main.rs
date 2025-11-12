use actix_web::{web, App, HttpServer};
use analytics_service::services::{OutboxConfig, OutboxPublisher};
use anyhow::{Context, Result};
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use std::sync::Arc;
use tonic::transport::Server as GrpcServer;
use tonic_health::server::health_reporter;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[actix_web::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=debug,analytics_service=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting analytics-service");

    // Initialize database (standardized pool)
    let mut cfg = DbPoolConfig::for_service("analytics-service");
    if cfg.database_url.is_empty() {
        cfg.database_url = std::env::var("DATABASE_URL").unwrap_or_default();
    }
    if cfg.max_connections < 20 {
        cfg.max_connections = 20;
    }
    cfg.log_config();

    let db_pool = create_pg_pool(cfg)
        .await
        .context("Failed to create database pool")?;

    tracing::info!("Database pool created successfully");

    // Run migrations
    tracing::info!("Running database migrations...");
    sqlx::migrate!("./migrations")
        .run(&db_pool)
        .await
        .context("Failed to run migrations")?;
    tracing::info!("Migrations completed successfully");

    // Create AppState for gRPC service
    let app_state = Arc::new(analytics_service::grpc::AppState::new(db_pool.clone()));

    // Start OutboxPublisher in background
    let outbox_config = OutboxConfig::from_env();
    tracing::info!(
        "Starting OutboxPublisher (brokers: {}, batch_size: {})",
        outbox_config.kafka_brokers,
        outbox_config.batch_size
    );

    let publisher = match OutboxPublisher::new(db_pool.clone(), outbox_config) {
        Ok(p) => Arc::new(p),
        Err(e) => {
            tracing::error!("Failed to create OutboxPublisher: {:?}", e);
            tracing::warn!("Events service will run without Kafka publishing");
            // Continue without publisher - events will be saved to outbox but not published
            return Ok(());
        }
    };

    // Spawn OutboxPublisher background task
    let publisher_clone = Arc::clone(&publisher);
    tokio::spawn(async move {
        tracing::info!("OutboxPublisher task started");
        if let Err(e) = publisher_clone.start().await {
            tracing::error!("OutboxPublisher failed: {:?}", e);
        }
    });

    // Compute HTTP and gRPC ports
    let http_port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8000);
    let grpc_port: u16 = http_port + 1000;

    tracing::info!("HTTP port: {}, gRPC port: {}", http_port, grpc_port);

    // Start gRPC server in background on http_port + 1000
    let grpc_addr: std::net::SocketAddr = format!("0.0.0.0:{}", grpc_port)
        .parse()
        .expect("Failed to parse gRPC address - this is a configuration error and should never happen with valid port number");
    let app_state_clone = Arc::clone(&app_state);

    tokio::spawn(async move {
        let (mut health, health_service) = health_reporter();
        health.set_serving::<analytics_service::grpc::nova::events_service::v1::events_service_server::EventsServiceServer<analytics_service::grpc::EventsServiceImpl>>().await;

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
                tracing::info!("mTLS enabled - service-to-service authentication active");
                Some(config)
            }
            Err(e) => {
                tracing::warn!("mTLS disabled - TLS config not found: {}. Using development mode for testing only.", e);
                if cfg!(debug_assertions) {
                    tracing::info!("Development mode: Starting without TLS (NOT FOR PRODUCTION)");
                    None
                } else {
                    tracing::error!("Production requires mTLS - GRPC_SERVER_CERT_PATH must be set");
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
                        tracing::info!("gRPC server TLS configured successfully");
                    }
                    Err(e) => {
                        tracing::error!("Failed to configure TLS on gRPC server: {}", e);
                        return;
                    }
                },
                Err(e) => {
                    tracing::error!("Failed to build server TLS config: {}", e);
                    return;
                }
            }
        }

        let svc = analytics_service::grpc::EventsServiceImpl::new(app_state_clone);

        tracing::info!("Starting gRPC server on {}", grpc_addr);

        if let Err(e) = server_builder
            .add_service(health_service)
            .add_service(
                analytics_service::grpc::nova::events_service::v1::events_service_server::EventsServiceServer::with_interceptor(
                    svc,
                    server_interceptor
                )
            )
            .serve(grpc_addr)
            .await
        {
            tracing::error!("analytics-service gRPC server error: {}", e);
        }
    });

    // Start HTTP server
    tracing::info!("Starting HTTP server on 0.0.0.0:{}", http_port);

    HttpServer::new(move || {
        App::new()
            .route("/health", web::get().to(|| async { "OK" }))
            .route("/ready", web::get().to(|| async { "READY" }))
    })
    .bind(("0.0.0.0", http_port))
    .context("Failed to bind HTTP server")?
    .run()
    .await
    .context("HTTP server error")
}
