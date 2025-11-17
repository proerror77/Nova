use actix_web::{web, App, HttpServer};
use anyhow::{Context, Result};
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use once_cell::sync::OnceCell;
use rdkafka::{producer::FutureProducer, ClientConfig};
use redis::aio::ConnectionManager;
use redis::Client as RedisClient;
use social_service::{
    grpc::server::{social::social_service_server::SocialServiceServer, SocialServiceImpl},
    repository::{CommentRepository, LikeRepository, ShareRepository},
    services::CounterService,
};
use std::time::Duration;
use std::{net::SocketAddr, sync::Arc};
use tonic::{metadata::MetadataValue, transport::Server as GrpcServer, Request, Status};
use tonic_health::server::health_reporter;
use tracing::{info, warn};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use transactional_outbox::{KafkaOutboxPublisher, OutboxProcessor, SqlxOutboxRepository};
use uuid::Uuid;

static INTERNAL_GRPC_API_KEY: OnceCell<Option<String>> = OnceCell::new();

#[actix_web::main]
async fn main() -> Result<()> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,social_service=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    info!("Starting social-service");

    let http_port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(8006);
    let grpc_port: u16 = std::env::var("GRPC_PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(9006);
    let grpc_addr: SocketAddr = format!("0.0.0.0:{grpc_port}")
        .parse()
        .context("Invalid gRPC bind address")?;

    // Initialize PostgreSQL connection pool
    let mut db_cfg = DbPoolConfig::for_service("social-service");
    if db_cfg.database_url.is_empty() {
        db_cfg.database_url =
            std::env::var("DATABASE_URL").context("DATABASE_URL must be set for social-service")?;
    }
    db_cfg.log_config();
    let pg_pool = create_pg_pool(db_cfg)
        .await
        .context("Failed to create PostgreSQL pool")?;

    sqlx::migrate!("./migrations")
        .run(&pg_pool)
        .await
        .context("Failed to run social-service migrations")?;
    info!("Database migrations applied");

    // Initialize Redis connection manager
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client =
        RedisClient::open(redis_url.as_str()).context("Failed to create Redis client")?;
    let redis_manager = ConnectionManager::new(redis_client)
        .await
        .context("Failed to create Redis connection manager")?;
    info!("Redis connection established at {}", redis_url);

    let counter_service = CounterService::new(redis_manager, pg_pool.clone());
    spawn_outbox_processor(pg_pool.clone());

    let social_service = SocialServiceImpl::new(
        LikeRepository::new(pg_pool.clone()),
        CommentRepository::new(pg_pool.clone()),
        ShareRepository::new(pg_pool.clone()),
        counter_service,
    );

    let grpc_service = social_service.clone();

    let grpc_task = tokio::spawn(async move {
        let (mut health_reporter, health_service) = health_reporter();
        health_reporter
            .set_serving::<SocialServiceServer<SocialServiceImpl>>()
            .await;

        let tls_required = matches!(
            std::env::var("APP_ENV")
                .unwrap_or_else(|_| "development".to_string())
                .to_ascii_lowercase()
                .as_str(),
            "production" | "staging"
        );

        let tls_config = match grpc_tls::GrpcServerTlsConfig::from_env() {
            Ok(cfg) => Some(cfg),
            Err(err) => {
                if tls_required {
                    return Err(err);
                }
                warn!(
                    error=%err,
                    "TLS configuration missing - starting without TLS (development only)"
                );
                None
            }
        };

        let mut server_builder = GrpcServer::builder();
        if let Some(cfg) = tls_config {
            let server_tls = cfg.build_server_tls()?;
            server_builder = server_builder.tls_config(server_tls)?;
        }

        server_builder
            .add_service(health_service)
            .add_service(SocialServiceServer::with_interceptor(
                grpc_service,
                grpc_server_interceptor,
            ))
            .serve(grpc_addr)
            .await
            .map_err(|e| e.into())
    });

    let http_server = HttpServer::new(|| {
        App::new()
            .route("/health", web::get().to(|| async { "OK" }))
            .route("/ready", web::get().to(|| async { "READY" }))
    })
    .bind(("0.0.0.0", http_port))
    .context("Failed to bind HTTP server")?
    .run();

    tokio::select! {
        http = http_server => {
            http.context("HTTP server error")?;
        }
        grpc = grpc_task => {
            grpc.context("Failed to join gRPC task")??;
        }
    }

    Ok(())
}

fn grpc_server_interceptor(mut req: Request<()>) -> Result<Request<()>, Status> {
    const CORRELATION_HEADER: &str = "x-correlation-id";
    if let Some(existing) = req.metadata().get(CORRELATION_HEADER) {
        if let Ok(val) = existing.to_str() {
            let stored = val.to_string();
            req.extensions_mut().insert::<String>(stored);
        }
    } else {
        let correlation_id = Uuid::new_v4().to_string();
        let value = MetadataValue::try_from(correlation_id.as_str())
            .map_err(|_| Status::internal("failed to set correlation id"))?;
        req.metadata_mut().insert(CORRELATION_HEADER, value);
    }

    if let Some(expected_key) = INTERNAL_GRPC_API_KEY
        .get_or_init(|| std::env::var("INTERNAL_GRPC_API_KEY").ok())
        .as_deref()
    {
        let provided = req
            .metadata()
            .get("x-internal-api-key")
            .and_then(|val| val.to_str().ok())
            .unwrap_or_default();
        if provided != expected_key {
            return Err(Status::unauthenticated("invalid internal api key"));
        }
    }

    Ok(req)
}

fn spawn_outbox_processor(pg_pool: sqlx::PgPool) {
    let kafka_brokers = match std::env::var("KAFKA_BROKERS") {
        Ok(brokers) if !brokers.trim().is_empty() => brokers,
        _ => {
            warn!("KAFKA_BROKERS not set - skipping outbox processor startup");
            return;
        }
    };

    let topic_prefix =
        std::env::var("KAFKA_TOPIC_PREFIX").unwrap_or_else(|_| "nova.social".to_string());
    let poll_interval = std::env::var("OUTBOX_POLL_INTERVAL_SECS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(5);
    let batch_size = std::env::var("OUTBOX_BATCH_SIZE")
        .ok()
        .and_then(|v| v.parse::<i32>().ok())
        .unwrap_or(100);
    let max_retries = std::env::var("OUTBOX_MAX_RETRIES")
        .ok()
        .and_then(|v| v.parse::<i32>().ok())
        .unwrap_or(5);

    tokio::spawn(async move {
        if let Err(err) = run_outbox_processor(
            pg_pool,
            kafka_brokers,
            topic_prefix,
            batch_size,
            poll_interval,
            max_retries,
        )
        .await
        {
            tracing::error!(error = %err, "Outbox processor terminated unexpectedly");
        }
    });
}

async fn run_outbox_processor(
    pg_pool: sqlx::PgPool,
    kafka_brokers: String,
    topic_prefix: String,
    batch_size: i32,
    poll_interval_secs: u64,
    max_retries: i32,
) -> Result<(), anyhow::Error> {
    let producer: FutureProducer = ClientConfig::new()
        .set("bootstrap.servers", &kafka_brokers)
        .set("enable.idempotence", "true")
        .set("compression.type", "zstd")
        .set("message.send.max.retries", "5")
        .set("acks", "all")
        .create()
        .context("Failed to create Kafka producer")?;

    let repository = Arc::new(SqlxOutboxRepository::new(pg_pool));
    let publisher = Arc::new(KafkaOutboxPublisher::new(producer, topic_prefix));
    let processor = OutboxProcessor::new(
        repository,
        publisher,
        batch_size,
        Duration::from_secs(poll_interval_secs),
        max_retries,
    );

    processor
        .start()
        .await
        .context("Outbox processor loop failed")
}
