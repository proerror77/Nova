use actix_web::{web, App, HttpServer};
use anyhow::{Context, Result};
use sqlx::postgres::PgPoolOptions;
use std::sync::Arc;
use std::time::Duration;
use tokio::task::JoinSet;
use tonic::transport::Server;
use tracing::info;

mod config;
mod error;
mod domain;
mod grpc;
mod handlers;
mod repositories;
mod repository;
mod services;

use config::Config;
use grpc::server_v2::{social::social_service_server::SocialServiceServer, AppState, SocialServiceImpl};
use services::CounterService;
use transactional_outbox::SqlxOutboxRepository;

async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};

        let mut terminate =
            signal(SignalKind::terminate()).expect("Failed to install SIGTERM handler");

        tokio::select! {
            _ = tokio::signal::ctrl_c() => {},
            _ = terminate.recv() => {},
        }
    }

    #[cfg(not(unix))]
    {
        tokio::signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize rustls crypto provider
    if let Err(err) = rustls::crypto::aws_lc_rs::default_provider().install_default() {
        eprintln!("ERROR: failed to install rustls crypto provider: {:?}", err);
        return Err(anyhow::anyhow!("failed to install rustls crypto provider"));
    }

    // Initialize tracing
    tracing_subscriber::fmt::init();

    info!("🔧 Starting social-service");

    // Load configuration
    let config = Config::from_env().context("Failed to load configuration")?;
    info!(
        "✅ Configuration loaded: env={}, http_port={}, grpc_port={}",
        config.app.env, config.app.http_port, config.grpc.port
    );

    // Initialize database pool
    let pg_pool = PgPoolOptions::new()
        .max_connections(config.database.max_connections)
        .min_connections(config.database.min_connections)
        .acquire_timeout(Duration::from_secs(10))
        .idle_timeout(Duration::from_secs(600))
        .max_lifetime(Duration::from_secs(1800))
        .connect(&config.database.url)
        .await
        .context("Failed to connect to database")?;

    // Verify database connection
    sqlx::query("SELECT 1")
        .execute(&pg_pool)
        .await
        .context("Failed to verify database connection")?;
    info!("✅ Database pool created and verified");

    // Run database migrations
    sqlx::migrate!("./migrations")
        .run(&pg_pool)
        .await
        .context("Failed to run database migrations")?;
    info!("✅ Database migrations completed");

    // Initialize Redis connection
    let redis_client = redis::Client::open(config.redis.url.as_str())
        .context("Failed to create Redis client")?;
    let redis_conn = redis::aio::ConnectionManager::new(redis_client)
        .await
        .context("Failed to connect to Redis")?;
    info!("✅ Redis connection established");

    // Initialize Outbox repository
    let outbox_repo = Arc::new(SqlxOutboxRepository::new(pg_pool.clone()));
    info!("✅ Outbox repository initialized");

    // Initialize Counter service
    let counter_service = CounterService::new(redis_conn.clone(), pg_pool.clone());
    info!("✅ Counter service initialized");

    // Create AppState
    let app_state = Arc::new(AppState::new(pg_pool.clone(), counter_service, outbox_repo));
    info!("✅ AppState created");

    // gRPC server address
    let grpc_addr = format!("{}:{}", config.app.host, config.grpc.port)
        .parse()
        .context("Invalid gRPC address")?;

    // HTTP health check address
    let http_addr = format!("{}:{}", config.app.host, config.app.http_port);

    info!("🚀 Starting servers:");
    info!("  - HTTP health checks: http://{}", http_addr);
    info!("  - gRPC service: grpc://{}", grpc_addr);

    let mut join_set = JoinSet::new();

    // Spawn HTTP server task
    let http_server = HttpServer::new(move || {
        App::new()
            .route("/health", web::get().to(|| async { "OK" }))
            .route("/ready", web::get().to(|| async { "READY" }))
    })
    .bind(&http_addr)
    .context("Failed to bind HTTP server")?
    .run();

    join_set.spawn(async move {
        http_server.await.map_err(|e| anyhow::anyhow!("HTTP server error: {}", e))
    });
    info!("✅ HTTP health check server started");

    // Spawn gRPC server task
    let grpc_service = SocialServiceImpl::new(app_state);
    let grpc_config = config.grpc.clone();

    join_set.spawn(async move {
        let mut server_builder = Server::builder();

        // Configure mTLS if certificates are provided
        if let (Some(cert_path), Some(key_path), Some(ca_path)) = (
            &grpc_config.server_cert_path,
            &grpc_config.server_key_path,
            &grpc_config.ca_cert_path,
        ) {
            info!("🔐 Configuring gRPC server with mTLS");

            let cert = tokio::fs::read(cert_path)
                .await
                .context("Failed to read server certificate")?;
            let key = tokio::fs::read(key_path)
                .await
                .context("Failed to read server key")?;
            let ca_cert = tokio::fs::read(ca_path)
                .await
                .context("Failed to read CA certificate")?;

            let server_identity = tonic::transport::Identity::from_pem(cert, key);
            let client_ca_cert = tonic::transport::Certificate::from_pem(ca_cert);

            let tls_config = tonic::transport::ServerTlsConfig::new()
                .identity(server_identity)
                .client_ca_root(client_ca_cert);

            server_builder = Server::builder()
                .tls_config(tls_config)
                .context("Failed to configure TLS")?;

            info!("✅ mTLS configuration applied");
        } else {
            info!("⚠️  Running gRPC server without mTLS (development mode)");
        }

        server_builder
            .add_service(SocialServiceServer::new(grpc_service))
            .serve_with_shutdown(grpc_addr, shutdown_signal())
            .await
            .map_err(|e| anyhow::anyhow!("gRPC server error: {}", e))
    });
    info!("✅ gRPC server started");

    // TODO: Spawn outbox worker task (for future implementation)
    // join_set.spawn(outbox_worker::run(pg_pool.clone(), kafka_producer));

    info!("✅ All services started successfully");
    info!("🎉 social-service is running");

    // Wait for any task to complete (or fail)
    while let Some(result) = join_set.join_next().await {
        match result {
            Ok(Ok(())) => {
                info!("Task completed successfully");
            }
            Ok(Err(e)) => {
                tracing::error!("Task failed: {:#}", e);
                return Err(e);
            }
            Err(e) => {
                tracing::error!("Task panicked: {:#}", e);
                return Err(anyhow::anyhow!("Task panicked: {}", e));
            }
        }
    }

    info!("🛑 social-service shutting down");
    Ok(())
}
