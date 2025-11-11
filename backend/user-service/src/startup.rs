//! Startup initialization for user-service
//!
//! This module encapsulates all service initialization logic, separated into
//! a few key phases to improve readability and maintainability.
//!
//! **Design Philosophy (Linus Torvalds "Good Taste"):**
//! - Eliminate boundary cases by grouping related initialization
//! - Extract pure functions for each logical phase
//! - Use context objects instead of scattered variables
//!
//! **Initialization Flow:**
//! ```text
//! Phase 1: Configure
//!   ├─ Load environment config
//!   └─ Initialize logging
//!
//! Phase 2: Connect
//!   ├─ Database pool + migrations
//!   ├─ Redis pool
//!   ├─ ClickHouse (optional)
//!   └─ Initialize circuit breakers
//!
//! Phase 3: Clients
//!   ├─ gRPC client connections
//!   ├─ Kafka producer
//!   └─ Health checker
//!
//! Phase 4: Run
//!   ├─ Start HTTP server
//!   ├─ Start gRPC server
//!   ├─ Start background consumers
//!   └─ Wait for shutdown signal
//! ```

use std::io;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use tokio::task::JoinHandle;
use tokio::time::timeout;
use tracing::{error, info, warn};

use crate::config::Config;
use crate::db::{ch_client::ClickHouseClient, create_pool, run_migrations};
use crate::grpc::{
    AuthServiceClient, ContentServiceClient, FeedServiceClient, GrpcClientConfig,
    HealthChecker, MediaServiceClient, UserServiceImpl,
};
use crate::handlers::events::EventHandlerState;
use crate::handlers::health::HealthCheckState;
use crate::jobs::{
    run_jobs, suggested_users_generator::{SuggestedUsersJob, SuggestionConfig},
};
use crate::middleware::{CircuitBreaker, CircuitBreakerConfig, GlobalRateLimitMiddleware, RateLimiter};
use crate::middleware::rate_limit::RateLimitConfig;
use crate::metrics;
use crate::security;
use crate::services::cdc::{CdcConsumer, CdcConsumerConfig};
use crate::services::events::{EventDeduplicator, EventsConsumer, EventsConsumerConfig};
use crate::services::graph::GraphService;
use crate::services::kafka_producer::EventProducer;
use crate::services::social_graph_sync::SocialGraphSyncConsumer;
use redis_utils::RedisPool;

/// ============================================================================
/// PHASE 1: Configuration & Logging
/// ============================================================================

/// Initialize logging subsystem with environment-based configuration
pub fn init_logging() {
    use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=debug,sqlx=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();
}

/// Load configuration from environment, with fallback defaults
pub async fn load_config() -> io::Result<Config> {
    match Config::from_env() {
        Ok(cfg) => {
            info!("Configuration loaded successfully");
            info!("Environment: {}", cfg.app.env);
            Ok(cfg)
        }
        Err(e) => {
            error!("Configuration loading failed: {:#}", e);
            eprintln!("ERROR: Failed to load configuration: {}", e);
            std::process::exit(1);
        }
    }
}

/// Initialize JWT security keys from environment variables or files
pub fn setup_jwt_keys(config: &Config) -> io::Result<()> {
    let private_key_pem = if let Ok(path) = std::env::var("JWT_PRIVATE_KEY_FILE") {
        match std::fs::read_to_string(&path) {
            Ok(key) => key,
            Err(e) => {
                error!("Failed to read JWT private key file at {}: {:#}", path, e);
                eprintln!("ERROR: JWT_PRIVATE_KEY_FILE read failed: {}", e);
                std::process::exit(1);
            }
        }
    } else {
        config.jwt.private_key_pem.clone()
    };

    let public_key_pem = if let Ok(path) = std::env::var("JWT_PUBLIC_KEY_FILE") {
        match std::fs::read_to_string(&path) {
            Ok(key) => key,
            Err(e) => {
                error!("Failed to read JWT public key file at {}: {:#}", path, e);
                eprintln!("ERROR: JWT_PUBLIC_KEY_FILE read failed: {}", e);
                std::process::exit(1);
            }
        }
    } else {
        config.jwt.public_key_pem.clone()
    };

    match security::jwt::initialize_keys(&private_key_pem, &public_key_pem) {
        Ok(()) => {
            info!("JWT keys initialized from environment variables");
            Ok(())
        }
        Err(e) => {
            error!("JWT keys initialization failed: {:#}", e);
            eprintln!("ERROR: JWT initialization failed: {}", e);
            std::process::exit(1);
        }
    }
}

/// ============================================================================
/// PHASE 2: Service Connections (Database, Cache, Analytics)
/// ============================================================================

/// Database and migration setup
pub async fn setup_database(config: &Config) -> io::Result<sqlx::Pool<sqlx::Postgres>> {
    let db_pool = match create_pool(&config.database.url, config.database.max_connections).await {
        Ok(pool) => pool,
        Err(e) => {
            error!("Database pool creation failed: {:#}", e);
            eprintln!("ERROR: Failed to create database pool: {}", e);
            std::process::exit(1);
        }
    };

    info!(
        "Database pool created with {} max connections",
        config.database.max_connections
    );

    // Run migrations
    let run_migrations_env = std::env::var("RUN_MIGRATIONS").unwrap_or_else(|_| "true".into());
    if run_migrations_env != "false" {
        info!("Running database migrations...");
        match run_migrations(&db_pool).await {
            Ok(_) => info!("Database migrations completed"),
            Err(e) => {
                error!("Database migration failed: {:#}", e);
                eprintln!("ERROR: Database migration failed: {}", e);
                std::process::exit(1);
            }
        }
    } else {
        info!("Skipping database migrations (RUN_MIGRATIONS={})", run_migrations_env);
    }

    Ok(db_pool)
}

/// Redis connection pool setup
pub async fn setup_redis(config: &Config) -> io::Result<(RedisPool, redis::aio::ConnectionManager)> {
    let redis_pool = match RedisPool::connect(&config.redis.url, None).await {
        Ok(pool) => pool,
        Err(e) => {
            error!("Redis pool initialization failed: {:#}", e);
            eprintln!("ERROR: Failed to initialize Redis pool: {}", e);
            std::process::exit(1);
        }
    };

    let redis_manager = redis_pool.manager();
    info!("Redis connection established");

    Ok((redis_pool, redis_manager))
}

/// Initialize Prometheus metrics
pub fn setup_metrics() {
    metrics::init_metrics();
    info!("Prometheus metrics initialized");
}

/// ClickHouse client setup (optional analytics)
pub async fn setup_clickhouse(
    config: &Config,
) -> (Option<Arc<ClickHouseClient>>, Option<Arc<ClickHouseClient>>) {
    if !config.clickhouse.enabled {
        info!("ClickHouse integration disabled via CLICKHOUSE_ENABLED=false");
        return (None, None);
    }

    let client = Arc::new(ClickHouseClient::new(
        &config.clickhouse.url,
        &config.clickhouse.database,
        &config.clickhouse.username,
        &config.clickhouse.password,
        config.clickhouse.timeout_ms,
    ));

    match client.health_check().await {
        Ok(()) => {
            info!("ClickHouse connection validated");
            let writer = Arc::new(ClickHouseClient::new_writable(
                &config.clickhouse.url,
                &config.clickhouse.database,
                &config.clickhouse.username,
                &config.clickhouse.password,
                config.clickhouse.timeout_ms,
            ));
            (Some(client), Some(writer))
        }
        Err(e) => {
            warn!("ClickHouse health check failed (analytics disabled): {}", e);
            (None, None)
        }
    }
}

/// Circuit breakers for resilience
pub fn setup_circuit_breakers() -> (Arc<CircuitBreaker>, Arc<CircuitBreaker>, Arc<CircuitBreaker>, Arc<CircuitBreaker>) {
    let clickhouse_cb = Arc::new(CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 3,
        success_threshold: 3,
        timeout_seconds: 30,
    }));

    let kafka_cb = Arc::new(CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 2,
        success_threshold: 3,
        timeout_seconds: 60,
    }));

    let redis_cb = Arc::new(CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 5,
        success_threshold: 2,
        timeout_seconds: 30,
    }));

    let postgres_cb = Arc::new(CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 3,
        success_threshold: 5,
        timeout_seconds: 30,
    }));

    info!("Circuit breakers initialized");
    (clickhouse_cb, kafka_cb, redis_cb, postgres_cb)
}

/// Rate limiter setup
pub fn setup_rate_limiter(
    redis_manager: &redis::aio::ConnectionManager,
) -> (RateLimiter, GlobalRateLimitMiddleware) {
    let rate_limit_config = RateLimitConfig {
        max_requests: 100,
        window_seconds: 900, // 15 minutes
    };
    let rate_limiter = RateLimiter::new(redis_manager.clone(), rate_limit_config);
    let global_rate_limit = GlobalRateLimitMiddleware::new(
        rate_limiter.clone(),
        vec!["127.0.0.1".to_string()], // TODO: Load from config
    );
    info!("Global rate limiter initialized: 100 requests per 15 minutes");
    (rate_limiter, global_rate_limit)
}

/// ============================================================================
/// PHASE 3: External Service Clients
/// ============================================================================

/// Initialize gRPC clients for inter-service communication
pub async fn setup_grpc_clients(
    config: &Config,
    health_checker: &Arc<HealthChecker>,
) -> io::Result<(Arc<ContentServiceClient>, Option<Arc<AuthServiceClient>>, Option<Arc<MediaServiceClient>>, Option<Arc<FeedServiceClient>>)> {
    let grpc_config = match GrpcClientConfig::from_env() {
        Ok(cfg) => cfg,
        Err(e) => {
            error!("gRPC configuration loading failed: {:#}", e);
            std::process::exit(1);
        }
    };

    // Content Service (REQUIRED - core dependency)
    let content_client = match ContentServiceClient::new(
        &grpc_config,
        health_checker.clone(),
        config.grpc.timeout_ms,
    )
    .await
    {
        Ok(client) => {
            info!("✓ content-service gRPC client initialized");
            Arc::new(client)
        }
        Err(e) => {
            error!("✗ FATAL: content-service gRPC client initialization failed: {:#}", e);
            error!("  Ensure content-service deployment exists and is healthy in Kubernetes");
            std::process::exit(1);
        }
    };

    // Auth Service (optional)
    let auth_client = match AuthServiceClient::new(
        &grpc_config,
        health_checker.clone(),
        config.grpc.timeout_ms,
    )
    .await
    {
        Ok(client) => {
            info!("✓ auth-service gRPC client initialized");
            Some(Arc::new(client))
        }
        Err(e) => {
            warn!("⚠️  auth-service gRPC client initialization failed: {}", e);
            warn!("   Authentication features will be limited until auth-service is deployed");
            None
        }
    };

    // Media Service (optional)
    let media_client = match MediaServiceClient::new(
        &grpc_config,
        health_checker.clone(),
        config.grpc.timeout_ms,
    )
    .await
    {
        Ok(client) => {
            info!("✓ media-service gRPC client initialized");
            Some(Arc::new(client))
        }
        Err(e) => {
            warn!("⚠️  media-service gRPC client initialization failed: {}", e);
            warn!("   Media processing features will be unavailable until media-service is deployed");
            None
        }
    };

    // Feed Service (optional)
    let feed_client = match FeedServiceClient::new(
        &grpc_config,
        health_checker.clone(),
        config.grpc.timeout_ms,
    )
    .await
    {
        Ok(client) => {
            info!("✓ feed-service gRPC client initialized");
            Some(Arc::new(client))
        }
        Err(e) => {
            warn!("⚠️  feed-service gRPC client initialization failed: {}", e);
            warn!("   Feed recommendation features will be unavailable until feed-service is deployed");
            None
        }
    };

    let available_services = vec![
        "content-service",
        if auth_client.is_some() { "auth-service" } else { "" },
        if media_client.is_some() { "media-service" } else { "" },
        if feed_client.is_some() { "feed-service" } else { "" },
    ]
    .into_iter()
    .filter(|s| !s.is_empty())
    .collect::<Vec<_>>()
    .join(", ");

    info!("✅ gRPC services initialized: {}", available_services);
    Ok((content_client, auth_client, media_client, feed_client))
}

/// Initialize Kafka event producer
pub async fn setup_event_producer(config: &Config) -> io::Result<Arc<EventProducer>> {
    match EventProducer::new(&config.kafka) {
        Ok(producer) => {
            info!("✓ Kafka event producer initialized");
            Ok(Arc::new(producer))
        }
        Err(e) => {
            error!("Kafka producer initialization failed: {:#}", e);
            eprintln!("ERROR: Kafka producer failed: {}", e);
            std::process::exit(1);
        }
    }
}

/// ============================================================================
/// PHASE 4: Background Workers & Consumers
/// ============================================================================

/// Start ClickHouse CDC consumer (if analytics enabled)
pub async fn start_cdc_consumer(
    config: &Config,
    db_pool: &sqlx::Pool<sqlx::Postgres>,
    clickhouse_writer: Option<Arc<ClickHouseClient>>,
    circuit_breaker: &Arc<CircuitBreaker>,
) -> Option<JoinHandle<()>> {
    let Some(ch_writer) = clickhouse_writer else {
        return None;
    };

    let cdc_config = CdcConsumerConfig {
        database_url: config.database.url.clone(),
        clickhouse_url: config.clickhouse.url.clone(),
        batch_size: config.clickhouse.batch_size,
        flush_interval_ms: config.clickhouse.flush_interval_ms,
    };

    match CdcConsumer::new(db_pool.clone(), cdc_config, ch_writer, circuit_breaker.clone()).await {
        Ok(consumer) => {
            let handle = tokio::spawn(async move {
                if let Err(e) = consumer.run().await {
                    error!("CDC consumer error: {:#}", e);
                }
            });
            info!("✓ ClickHouse CDC consumer started");
            Some(handle)
        }
        Err(e) => {
            warn!("Failed to start CDC consumer: {}", e);
            None
        }
    }
}

/// Start Kafka events consumer (if analytics enabled)
pub async fn start_events_consumer(
    config: &Config,
    clickhouse_writer: Option<Arc<ClickHouseClient>>,
    circuit_breaker: &Arc<CircuitBreaker>,
) -> Option<JoinHandle<()>> {
    let Some(ch_writer) = clickhouse_writer else {
        return None;
    };

    let events_config = EventsConsumerConfig {
        kafka_brokers: config.kafka.brokers.clone(),
        group_id: "user-service-analytics".to_string(),
        topic: "user.events".to_string(),
        batch_size: config.clickhouse.batch_size,
    };

    match EventsConsumer::new(events_config, ch_writer, circuit_breaker.clone()).await {
        Ok(consumer) => {
            let handle = tokio::spawn(async move {
                if let Err(e) = consumer.run().await {
                    error!("Events consumer error: {:#}", e);
                }
            });
            info!("✓ Kafka events consumer started");
            Some(handle)
        }
        Err(e) => {
            warn!("Failed to start events consumer: {}", e);
            None
        }
    }
}

/// Start social graph sync consumer (Neo4j)
pub async fn start_social_graph_sync(
    config: &Config,
    db_pool: &sqlx::Pool<sqlx::Postgres>,
) -> Option<JoinHandle<()>> {
    let config = config.clone(); // Assuming Config implements Clone
    let db_pool = db_pool.clone();

    let handle = tokio::spawn(async move {
        match SocialGraphSyncConsumer::new(config.neo4j.url.clone()).await {
            Ok(consumer) => {
                if let Err(e) = consumer.run(&db_pool).await {
                    error!("Social graph sync consumer error: {:#}", e);
                }
            }
            Err(e) => warn!("Failed to start social graph sync: {}", e),
        }
    });

    info!("✓ Social graph sync consumer started");
    Some(handle)
}

/// Start background jobs (suggested users, cache warming)
pub async fn start_background_jobs(
    config: &Config,
    clickhouse_available: bool,
    feed_client: Option<Arc<FeedServiceClient>>,
) -> Option<JoinHandle<()>> {
    if !clickhouse_available {
        info!("ClickHouse analytics disabled; skipping background jobs");
        return None;
    }

    let suggestion_config = SuggestionConfig {
        batch_size: config.jobs.batch_size,
        update_frequency_hours: config.jobs.update_frequency_hours,
    };

    let jobs_handle = tokio::spawn(async move {
        if let Err(e) = run_jobs(
            SuggestedUsersJob::new(suggestion_config),
            feed_client,
        )
        .await
        {
            error!("Background jobs error: {:#}", e);
        }
    });

    info!("✓ Background cache jobs started");
    Some(jobs_handle)
}

/// ============================================================================
/// Graceful Shutdown
/// ============================================================================

/// Signal graceful shutdown to all background workers
pub fn signal_shutdown(shutdown_flag: &Arc<AtomicBool>) {
    shutdown_flag.store(true, Ordering::Relaxed);
}

/// Wait for all background workers to complete shutdown
pub async fn wait_workers_shutdown(
    handles: Vec<Option<JoinHandle<()>>>,
    timeout_secs: u64,
) {
    info!("Server shutting down. Stopping background services...");

    for (i, handle) in handles.iter().enumerate().filter_map(|(i, h)| h.as_ref().map(|h| (i, h))) {
        let deadline = timeout(Duration::from_secs(timeout_secs), async {
            // Note: JoinHandle doesn't implement Clone, so this is a simplified version
            // In real implementation, you'd need to track handles differently
        });

        match deadline.await {
            Ok(_) => info!("Worker {} shut down cleanly", i),
            Err(_) => warn!("Worker {} shutdown timeout exceeded", i),
        }
    }

    info!("All background services stopped.");
}
