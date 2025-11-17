mod config;
mod domain;
mod grpc;
mod repository;

use anyhow::{anyhow, Context, Result};
use config::Config;
use grpc::server::graph::graph_service_server::GraphServiceServer;
use grpc::GraphServiceImpl;
use once_cell::sync::OnceCell;
use repository::GraphRepository;
use tonic::{metadata::MetadataValue, transport::Server, Request, Status};
use tonic_health::server::health_reporter;
use tracing::{error, info, warn};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use uuid::Uuid;

static INTERNAL_GRPC_API_KEY: OnceCell<Option<String>> = OnceCell::new();

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
        .add_service(health_service)
        .add_service(GraphServiceServer::with_interceptor(
            graph_service,
            grpc_server_interceptor,
        ))
        .serve(addr)
        .await
        .context("gRPC server failed")?;

    Ok(())
}

fn grpc_server_interceptor(mut req: Request<()>) -> Result<Request<()>, Status> {
    const CORRELATION_HEADER: &str = "x-correlation-id";
    if let Some(existing) = req.metadata().get(CORRELATION_HEADER) {
        if let Ok(val) = existing.to_str() {
            req.extensions_mut().insert::<String>(val.to_string());
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
