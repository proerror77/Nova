mod config;
mod domain;
mod grpc;
mod repository;

use anyhow::{anyhow, Context, Result};
use config::Config;
use grpc::server::graph::graph_service_server::GraphServiceServer;
use grpc::GraphServiceImpl;
use repository::{DualWriteRepository, GraphRepository, PostgresGraphRepository};
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
    dotenv::dotenv().ok();
    let config = Config::from_env().context("Failed to load configuration")?;

    info!(
        "Configuration loaded: gRPC port = {}, Neo4j URI = {}, Dual-write = {}",
        config.server.grpc_port, config.neo4j.uri, config.enable_dual_write
    );

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
        let postgres_repo = PostgresGraphRepository::new(pg_pool);

        // Create dual-write repository (non-strict mode: Neo4j failures don't break writes)
        let dual_repo = DualWriteRepository::new(
            postgres_repo,
            Arc::new(neo4j_repo),
            false, // strict_mode = false (continue on Neo4j errors)
        );

        // Verify health
        let (pg_healthy, neo4j_healthy) = dual_repo.health_check().await?;
        info!("Health check: PostgreSQL = {}, Neo4j = {}", pg_healthy, neo4j_healthy);

        if !pg_healthy {
            error!("PostgreSQL health check failed - aborting");
            return Err(anyhow!("PostgreSQL is not healthy"));
        }

        if !neo4j_healthy {
            warn!("Neo4j health check failed - will fallback to PostgreSQL");
        }

        // Create gRPC service with dual-write repository
        let graph_service = GraphServiceImpl::new_with_trait(
            Arc::new(dual_repo),
            config.internal_write_token.clone(),
        );

        info!("🚀 Graph service initialized with dual-write");

        // Setup and start server (rest of the code continues below)
        start_grpc_server(graph_service, &config).await?;
    } else {
        info!("⚠️  Dual-write mode DISABLED - Neo4j only (legacy mode)");

        // Initialize Neo4j repository only (legacy mode)
        let repo = GraphRepository::new(
            &config.neo4j.uri,
            &config.neo4j.user,
            &config.neo4j.password,
        )
        .await
        .context("Failed to initialize Neo4j repository")?;

        info!("Connected to Neo4j successfully");

        // Verify Neo4j connection
        if let Err(e) = repo.health_check().await {
            error!("Neo4j health check failed: {}", e);
            return Err(e);
        }

        info!("Neo4j health check passed");

        // Create gRPC service (legacy mode)
        let graph_service = GraphServiceImpl::new(repo, config.internal_write_token.clone());

        // Setup and start server
        start_grpc_server(graph_service, &config).await?;
    }

    Ok(())
}

async fn start_grpc_server(
    graph_service: GraphServiceImpl,
    config: &Config,
) -> Result<()> {

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
