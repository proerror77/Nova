/// Identity Service Main Entry Point
///
/// Starts gRPC server with:
/// - PostgreSQL connection pool
/// - Redis connection manager
/// - Kafka event producer
/// - Email service (SMTP)
/// - Outbox consumer (background task)
use anyhow::{Context, Result};
use identity_service::{
    config::Settings,
    grpc::{nova::auth_service::auth_service_server::AuthServiceServer, IdentityServiceServer},
    security::initialize_jwt_keys,
    services::{spawn_outbox_consumer, EmailService, KafkaEventProducer, OutboxConsumerConfig},
};
use redis_utils::RedisPool;
use sqlx::postgres::PgPoolOptions;
use std::time::Duration;
use tokio::signal;
use tonic::transport::Server;
use tracing::{error, info};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "identity_service=info,info".into()),
        )
        .with_target(false)
        .json()
        .init();

    info!("Starting Identity Service");

    // Load configuration
    let settings = Settings::load().await.context("Failed to load configuration")?;
    info!("Configuration loaded successfully");

    // Initialize JWT keys (RS256)
    let public_key = settings.jwt.validation_key.as_ref()
        .unwrap_or(&settings.jwt.signing_key);
    initialize_jwt_keys(&settings.jwt.signing_key, public_key)
        .context("Failed to initialize JWT keys")?;
    info!("JWT keys initialized");

    // Initialize database connection pool
    let db_pool = PgPoolOptions::new()
        .max_connections(settings.database.max_connections)
        .acquire_timeout(Duration::from_secs(5))
        .connect(&settings.database.url)
        .await
        .context("Failed to connect to PostgreSQL")?;

    info!(
        "Database pool initialized with {} max connections",
        settings.database.max_connections
    );

    // Run database migrations
    sqlx::migrate!("./migrations")
        .run(&db_pool)
        .await
        .context("Failed to run database migrations")?;
    info!("Database migrations completed");

    // Initialize Redis connection pool
    let redis_pool = RedisPool::connect(&settings.redis.url, None)
        .await
        .context("Failed to connect to Redis")?;
    let redis = redis_pool.manager();
    info!("Redis connection manager initialized");

    // Initialize Kafka producer (optional)
    let kafka_producer = if settings.kafka.brokers.is_empty() {
        info!("Kafka brokers not configured; running without event publishing");
        None
    } else {
        let brokers = settings.kafka.brokers.join(",");
        match KafkaEventProducer::new(&brokers, &settings.kafka.topic_prefix) {
            Ok(producer) => {
                info!("Kafka producer initialized");
                Some(producer)
            }
            Err(err) => {
                error!("Failed to initialize Kafka producer: {:?}", err);
                None
            }
        }
    };

    // Initialize email service
    let email_service = EmailService::new(&settings.email)
        .context("Failed to initialize email service")?;

    if email_service.is_enabled() {
        info!("Email service initialized with SMTP");
    } else {
        info!("Email service running in no-op mode (SMTP not configured)");
    }

    // Spawn outbox consumer (background task)
    let _outbox_handle = if kafka_producer.is_some() {
        let consumer_config = OutboxConsumerConfig::default();
        info!("Starting outbox consumer");
        Some(spawn_outbox_consumer(
            db_pool.clone(),
            kafka_producer.clone(),
            consumer_config,
        ))
    } else {
        info!("Skipping outbox consumer (Kafka not available)");
        None
    };

    // Build gRPC server
    let identity_service = IdentityServiceServer::new(
        db_pool.clone(),
        redis.clone(),
        email_service,
        kafka_producer,
    );

    let addr = format!("{}:{}", settings.server.host, settings.server.port)
        .parse()
        .context("Invalid server address")?;

    info!("Starting gRPC server on {}", addr);

    // Start gRPC server with graceful shutdown
    Server::builder()
        .add_service(AuthServiceServer::new(identity_service))
        .serve_with_shutdown(addr, shutdown_signal())
        .await
        .context("gRPC server error")?;

    info!("Identity service shutdown complete");

    Ok(())
}

/// Wait for shutdown signal (Ctrl+C or SIGTERM)
async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("Failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {
            info!("Received Ctrl+C signal");
        },
        _ = terminate => {
            info!("Received SIGTERM signal");
        },
    }

    info!("Shutting down gracefully...");
}
