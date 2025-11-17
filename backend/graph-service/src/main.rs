mod config;
mod domain;
mod grpc;
mod repository;

use anyhow::{Context, Result};
use config::Config;
use grpc::server::graph::graph_service_server::GraphServiceServer;
use grpc::GraphServiceImpl;
use repository::GraphRepository;
use tonic::transport::Server;
use tonic_health::server::health_reporter;
use tracing::{error, info};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<()> {
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
    let graph_service = GraphServiceImpl::new(repo);

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

    // Start gRPC server
    Server::builder()
        .add_service(health_service)
        .add_service(GraphServiceServer::new(graph_service))
        .serve(addr)
        .await
        .context("gRPC server failed")?;

    Ok(())
}
