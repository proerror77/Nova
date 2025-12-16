mod config;
mod consumers;
mod domain;
mod grpc;
mod repository;

use anyhow::{anyhow, Context, Result};
use config::Config;
use consumers::{IdentityEventsConsumer, SocialEventsConsumer};
use grpc::server::graph::graph_service_server::GraphServiceServer;
use grpc::GraphServiceImpl;
use nova_cache::NovaCache;
use redis_utils::RedisPool;
use repository::{
    CachedGraphRepository, DualWriteRepository, GraphRepository, PostgresGraphRepository,
};
use sqlx::PgPool;
use std::sync::Arc;
use tonic::transport::Server;
use tonic_health::server::health_reporter;
use tracing::{error, info, warn};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<()> {
    // rustls 0.23 requires selecting a CryptoProvider at runtime
    if let Err(err) = rustls::crypto::aws_lc_rs::default_provider().install_default() {
        eprintln!("Failed to install rustls crypto provider: {:?}", err);
        return Err(anyhow!("Unable to install TLS crypto provider: {:?}", err));
    }

    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "graph_service=info,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    info!("Starting Graph Service");

    // Load configuration
    dotenvy::dotenv().ok();
    let config = Config::from_env().context("Failed to load configuration")?;

    info!(
        "Configuration loaded: gRPC port = {}, Neo4j URI = {}, Dual-write = {}, Cache = {}",
        config.server.grpc_port, config.neo4j.uri, config.enable_dual_write, config.redis.enabled
    );

    // Initialize Redis connection for caching
    let nova_cache = if config.redis.enabled {
        match RedisPool::connect(&config.redis.url, None).await {
            Ok(pool) => {
                info!("✅ Connected to Redis for caching");
                Some(NovaCache::new(pool.manager()))
            }
            Err(e) => {
                warn!(error = %e, "Failed to connect to Redis - caching disabled");
                None
            }
        }
    } else {
        info!("⚠️  Caching disabled by configuration");
        None
    };

    if config.enable_dual_write {
        info!("🔄 Dual-write mode ENABLED (PostgreSQL + Neo4j)");

        // Initialize PostgreSQL pool
        let pg_pool = PgPool::connect(&config.database_url)
            .await
            .context("Failed to connect to PostgreSQL")?;

        info!("✅ Connected to PostgreSQL successfully");

        // Initialize Neo4j repository
        let neo4j_repo = GraphRepository::new(
            &config.neo4j.uri,
            &config.neo4j.user,
            &config.neo4j.password,
        )
        .await
        .context("Failed to initialize Neo4j repository")?;

        info!("✅ Connected to Neo4j successfully");

        // Create PostgreSQL repository
        let postgres_repo = PostgresGraphRepository::new(pg_pool.clone());
        // Clone for identity events consumer
        let postgres_repo_for_consumer = PostgresGraphRepository::new(pg_pool);

        // Create dual-write repository (non-strict mode: Neo4j failures don't break writes)
        let dual_repo = DualWriteRepository::new(
            postgres_repo,
            Arc::new(neo4j_repo),
            false, // strict_mode = false (continue on Neo4j errors)
        );

        // Verify health
        let (pg_healthy, neo4j_healthy) = dual_repo.health_check().await?;
        info!(
            "Health check: PostgreSQL = {}, Neo4j = {}",
            pg_healthy, neo4j_healthy
        );

        if !pg_healthy {
            error!("PostgreSQL health check failed - aborting");
            return Err(anyhow!("PostgreSQL is not healthy"));
        }

        if !neo4j_healthy {
            warn!("Neo4j health check failed - will fallback to PostgreSQL");
        }

        // Wrap with caching layer if Redis is available
        let repo: Arc<dyn repository::GraphRepositoryTrait + Send + Sync> = match nova_cache.clone()
        {
            Some(cache) => {
                info!("🚀 Graph service initialized with dual-write + caching");
                Arc::new(CachedGraphRepository::new(Arc::new(dual_repo), cache, true))
            }
            None => {
                info!("🚀 Graph service initialized with dual-write (no cache)");
                Arc::new(dual_repo)
            }
        };

        // Clone repo for Kafka consumer
        let repo_for_consumer = repo.clone();

        // Create gRPC service
        let graph_service =
            GraphServiceImpl::new_with_trait(repo, config.internal_write_token.clone());

        // Spawn Kafka consumers for social and identity events if configured
        spawn_kafka_consumers_if_enabled(repo_for_consumer, Some(postgres_repo_for_consumer), &config);

        // Setup and start server (rest of the code continues below)
        start_grpc_server(graph_service, &config).await?;
    } else {
        info!("⚠️  Dual-write mode DISABLED - Neo4j only (legacy mode)");

        // Initialize Neo4j repository only (legacy mode)
        let neo4j_repo = GraphRepository::new(
            &config.neo4j.uri,
            &config.neo4j.user,
            &config.neo4j.password,
        )
        .await
        .context("Failed to initialize Neo4j repository")?;

        info!("Connected to Neo4j successfully");

        // Verify Neo4j connection
        if let Err(e) = neo4j_repo.health_check().await {
            error!("Neo4j health check failed: {}", e);
            return Err(e);
        }

        info!("Neo4j health check passed");

        // Wrap with caching layer if Redis is available
        let graph_service = match nova_cache {
            Some(cache) => {
                info!("🚀 Graph service initialized with Neo4j + caching");
                let cached_repo = CachedGraphRepository::new(Arc::new(neo4j_repo), cache, true);
                let repo: Arc<dyn repository::GraphRepositoryTrait + Send + Sync> =
                    Arc::new(cached_repo);

                // Clone repo for Kafka consumer
                let repo_for_consumer = repo.clone();

                // Spawn Kafka consumers (no PostgreSQL in legacy mode)
                spawn_kafka_consumers_if_enabled(repo_for_consumer, None, &config);

                GraphServiceImpl::new_with_trait(repo, config.internal_write_token.clone())
            }
            None => {
                info!("🚀 Graph service initialized with Neo4j (no cache)");
                let repo: Arc<dyn repository::GraphRepositoryTrait + Send + Sync> =
                    Arc::new(neo4j_repo);

                // Clone repo for Kafka consumer
                let repo_for_consumer = repo.clone();

                // Spawn Kafka consumers (no PostgreSQL in legacy mode)
                spawn_kafka_consumers_if_enabled(repo_for_consumer, None, &config);

                GraphServiceImpl::new_with_trait(repo, config.internal_write_token.clone())
            }
        };

        // Setup and start server
        start_grpc_server(graph_service, &config).await?;
    }

    Ok(())
}

async fn start_grpc_server(graph_service: GraphServiceImpl, config: &Config) -> Result<()> {
    // Setup health reporting
    let (mut health_reporter, health_service) = health_reporter();
    health_reporter
        .set_serving::<GraphServiceServer<GraphServiceImpl>>()
        .await;

    // Build gRPC server address
    let addr = format!("0.0.0.0:{}", config.server.grpc_port)
        .parse()
        .context("Invalid gRPC server address")?;

    info!("Starting gRPC server on {}", addr);

    // Load TLS configuration
    let tls_required = matches!(
        std::env::var("APP_ENV")
            .unwrap_or_else(|_| "development".to_string())
            .to_ascii_lowercase()
            .as_str(),
        "production" | "staging"
    );

    let tls_config = match grpc_tls::GrpcServerTlsConfig::from_env() {
        Ok(cfg) => {
            info!("gRPC TLS configuration loaded for graph-service");
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

    // Build server with optional TLS
    let mut server_builder = Server::builder();
    if let Some(cfg) = tls_config {
        let server_tls = cfg
            .build_server_tls()
            .context("Failed to build server TLS config")?;
        server_builder = server_builder
            .tls_config(server_tls)
            .context("Failed to configure gRPC TLS")?;
    }

    // Start gRPC server
    server_builder
        .add_service(health_service)
        .add_service(GraphServiceServer::new(graph_service))
        .serve(addr)
        .await
        .context("gRPC server failed")?;

    Ok(())
}

/// Spawn Kafka consumers for social and identity events if environment variables are configured
fn spawn_kafka_consumers_if_enabled(
    repo: Arc<dyn repository::GraphRepositoryTrait + Send + Sync>,
    postgres_repo: Option<PostgresGraphRepository>,
    _config: &Config,
) {
    let kafka_enabled = std::env::var("KAFKA_ENABLED")
        .unwrap_or_else(|_| "false".to_string())
        .to_lowercase()
        == "true";

    if !kafka_enabled {
        info!("Kafka consumers disabled (KAFKA_ENABLED not set to true)");
        return;
    }

    let brokers = match std::env::var("KAFKA_BROKERS") {
        Ok(b) if !b.is_empty() => b,
        _ => {
            warn!("KAFKA_BROKERS not set or empty - Kafka consumers disabled");
            return;
        }
    };

    let topic_prefix = std::env::var("KAFKA_TOPIC_PREFIX").unwrap_or_else(|_| "nova".to_string());

    // Spawn Social Events Consumer
    {
        let group_id = std::env::var("KAFKA_CONSUMER_GROUP")
            .unwrap_or_else(|_| "graph-service-social-events".to_string());
        let topic = format!("{}.social.events", topic_prefix);
        let brokers = brokers.clone();
        let repo = repo.clone();

        info!(
            "Starting Social Events Kafka consumer: brokers={}, group={}, topic={}",
            brokers, group_id, topic
        );

        tokio::spawn(async move {
            match SocialEventsConsumer::new(&brokers, &group_id, &topic, repo) {
                Ok(consumer) => {
                    info!("✅ Social Events Kafka consumer initialized");
                    if let Err(e) = consumer.start().await {
                        error!("Social Events Kafka consumer failed: {}", e);
                    }
                }
                Err(e) => {
                    error!("Failed to create Social Events Kafka consumer: {}", e);
                }
            }
        });
    }

    // Spawn Identity Events Consumer (P1: user sync from identity-service)
    if let Some(pg_repo) = postgres_repo {
        let group_id = std::env::var("KAFKA_IDENTITY_CONSUMER_GROUP")
            .unwrap_or_else(|_| "graph-service-identity-events".to_string());
        let topic = format!("{}.identity.events", topic_prefix);

        info!(
            "Starting Identity Events Kafka consumer: brokers={}, group={}, topic={}",
            brokers, group_id, topic
        );

        tokio::spawn(async move {
            match IdentityEventsConsumer::new(&brokers, &group_id, &topic, pg_repo) {
                Ok(consumer) => {
                    info!("✅ Identity Events Kafka consumer initialized (P1: user sync)");
                    if let Err(e) = consumer.start().await {
                        error!("Identity Events Kafka consumer failed: {}", e);
                    }
                }
                Err(e) => {
                    error!("Failed to create Identity Events Kafka consumer: {}", e);
                }
            }
        });
    } else {
        warn!("Identity Events consumer not started (PostgreSQL not available in legacy mode)");
    }
}
