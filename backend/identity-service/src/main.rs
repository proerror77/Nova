/// Identity Service Main Entry Point
///
/// Starts gRPC server with:
/// - PostgreSQL connection pool
/// - Redis connection manager
/// - Kafka event producer
/// - Email service (SMTP)
/// - Outbox consumer (background task)
use anyhow::{anyhow, Context, Result};
use identity_service::{
    config::Settings,
    grpc::{nova::auth_service::auth_service_server::AuthServiceServer, IdentityServiceServer},
    security::initialize_jwt_keys,
    services::{spawn_outbox_consumer, EmailService, KafkaEventProducer, OutboxConsumerConfig},
};
use once_cell::sync::OnceCell;
use opentelemetry_config::{init_tracing, TracingConfig};
use redis_utils::RedisPool;
use sqlx::postgres::PgPoolOptions;
use std::time::Duration;
use tokio::signal;
use tonic::{metadata::MetadataValue, transport::Server, Request, Status};
use tracing::{error, info, warn};
use uuid::Uuid;

static INTERNAL_GRPC_API_KEY: OnceCell<Option<String>> = OnceCell::new();

#[tokio::main]
async fn main() -> Result<()> {
    // rustls 0.23 requires selecting a CryptoProvider at runtime
    if let Err(err) = rustls::crypto::aws_lc_rs::default_provider().install_default() {
        eprintln!("Failed to install rustls crypto provider: {:?}", err);
        return Err(anyhow!("Unable to install TLS crypto provider: {:?}", err));
    }

    // Initialize OpenTelemetry tracing (if enabled)
    let tracing_config = TracingConfig::from_env();
    if tracing_config.enabled {
        match init_tracing("identity-service", tracing_config) {
            Ok(_tracer) => {
                info!("OpenTelemetry distributed tracing initialized for identity-service");
            }
            Err(e) => {
                eprintln!("Failed to initialize OpenTelemetry tracing: {}", e);
                // Initialize fallback tracing
                tracing_subscriber::fmt()
                    .with_env_filter(
                        std::env::var("RUST_LOG")
                            .unwrap_or_else(|_| "identity_service=info,info".into()),
                    )
                    .with_target(false)
                    .json()
                    .init();
            }
        }
    } else {
        // Initialize fallback tracing without OpenTelemetry
        tracing_subscriber::fmt()
            .with_env_filter(
                std::env::var("RUST_LOG").unwrap_or_else(|_| "identity_service=info,info".into()),
            )
            .with_target(false)
            .json()
            .init();
    }

    info!("Starting Identity Service");

    // Load configuration
    let settings = Settings::load()
        .await
        .context("Failed to load configuration")?;
    info!("Configuration loaded successfully");

    // Initialize JWT keys (RS256)
    let public_key = settings
        .jwt
        .validation_key
        .as_ref()
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
    let email_service =
        EmailService::new(&settings.email).context("Failed to initialize email service")?;

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

    // Initialize AWS SNS client for SMS invites (optional)
    let sns_client = if std::env::var("AWS_REGION").is_ok() {
        match aws_config::load_defaults(aws_config::BehaviorVersion::latest()).await {
            config => {
                let client = aws_sdk_sns::Client::new(&config);
                info!("AWS SNS client initialized for invite SMS delivery");
                Some(client)
            }
        }
    } else {
        info!("AWS region not configured; SMS invite delivery disabled");
        None
    };

    // Build gRPC server
    let identity_service = IdentityServiceServer::new(
        db_pool.clone(),
        redis.clone(),
        email_service,
        kafka_producer,
        sns_client,
        settings.oauth.clone(),
    );

    let addr = format!("{}:{}", settings.server.host, settings.server.port)
        .parse()
        .context("Invalid server address")?;

    info!("Starting gRPC server on {}", addr);

    let tls_required = matches!(
        std::env::var("APP_ENV")
            .unwrap_or_else(|_| "development".to_string())
            .to_ascii_lowercase()
            .as_str(),
        "production" | "staging"
    );

    let tls_config = match grpc_tls::GrpcServerTlsConfig::from_env() {
        Ok(cfg) => {
            info!("gRPC TLS configuration loaded for identity-service");
            Some(cfg)
        }
        Err(err) => {
            if tls_required {
                return Err(anyhow!(
                    "TLS is required in production/staging but failed to load: {err}"
                ));
            }
            warn!(
                error=%err,
                "TLS configuration missing - starting without TLS (development only)"
            );
            None
        }
    };

    let mut server_builder = Server::builder();
    if let Some(cfg) = tls_config {
        let server_tls = cfg
            .build_server_tls()
            .context("Failed to build server TLS config")?;
        server_builder = server_builder
            .tls_config(server_tls)
            .context("Failed to configure gRPC TLS")?;
    }

    server_builder
        .add_service(AuthServiceServer::with_interceptor(
            identity_service,
            grpc_server_interceptor,
        ))
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
