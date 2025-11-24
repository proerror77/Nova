mod config;
mod domain;
mod grpc;
mod repository;

use anyhow::{anyhow, Context, Result};
use config::Config;
use grpc::server::graph::graph_service_server::GraphServiceServer;
use grpc::GraphServiceImpl;
use repository::GraphRepository;
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
        "Configuration loaded: gRPC port = {}, Neo4j URI = {}",
        config.server.grpc_port, config.neo4j.uri
    );

    // Initialize Neo4j repository
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

    // Create gRPC service
    let graph_service = GraphServiceImpl::new(repo, config.internal_write_token.clone());

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
