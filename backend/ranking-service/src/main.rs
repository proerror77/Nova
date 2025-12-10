use anyhow::{anyhow, Context, Result};
use ranking_service::{
    grpc::{ranking_proto::ranking_service_server::RankingServiceServer, RankingServiceImpl},
    Config, DiversityLayer, RankingLayer, RecallLayer,
};
use tonic::transport::Server;
use tracing::{error, info, warn};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // rustls 0.23 requires selecting a CryptoProvider at runtime
    if let Err(err) = rustls::crypto::aws_lc_rs::default_provider().install_default() {
        eprintln!("Failed to install rustls crypto provider: {:?}", err);
        return Err(anyhow!("Unable to install TLS crypto provider: {:?}", err).into());
    }

    // Initialize tracing
    tracing_subscriber::registry()
        .with(fmt::layer())
        .with(EnvFilter::from_default_env())
        .init();

    // Load config
    let config = Config::from_env().expect("Failed to load config");

    info!(
        "Starting {} on HTTP:{}, gRPC:{}",
        config.service.service_name, config.service.http_port, config.service.grpc_port
    );

    // Initialize Redis client
    let redis_client =
        redis::Client::open(config.redis.url.clone()).expect("Failed to create Redis client");

    // Initialize gRPC clients
    let graph_client =
        tonic::transport::Channel::from_shared(config.grpc_clients.graph_service_url.clone())
            .expect("Invalid graph service URL")
            .connect_lazy();

    let content_client =
        tonic::transport::Channel::from_shared(config.grpc_clients.content_service_url.clone())
            .expect("Invalid content service URL")
            .connect_lazy();

    // Initialize layers
    let recall_layer = RecallLayer::new(graph_client, content_client, redis_client, config.recall.clone());
    let ranking_layer = RankingLayer::new();
    let diversity_layer = DiversityLayer::new(0.7); // lambda = 0.7

    // Create gRPC service
    let ranking_service = RankingServiceImpl::new(recall_layer, ranking_layer, diversity_layer);

    // Start gRPC server
    let addr = format!("0.0.0.0:{}", config.service.grpc_port)
        .parse()
        .expect("Invalid gRPC address");

    info!("gRPC server listening on {}", addr);

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
            info!("gRPC TLS configuration loaded for ranking-service");
            Some(cfg)
        }
        Err(err) => {
            if tls_required {
                return Err(anyhow!(
                    "TLS is required in production/staging but failed to load: {err}"
                )
                .into());
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

    server_builder
        .add_service(RankingServiceServer::new(ranking_service))
        .serve(addr)
        .await
        .map_err(|e| {
            error!("gRPC server error: {}", e);
            e
        })?;

    Ok(())
}
