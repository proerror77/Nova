use ranking_service::{
    grpc::{ranking_proto::ranking_service_server::RankingServiceServer, RankingServiceImpl},
    Config, DiversityLayer, RankingLayer, RecallLayer,
};
use tonic::transport::Server;
use tracing::{error, info};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
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
    let redis_client = redis::Client::open(config.redis.url.clone())
        .expect("Failed to create Redis client");

    // Initialize gRPC clients
    let graph_client = tonic::transport::Channel::from_shared(
        config.grpc_clients.graph_service_url.clone(),
    )
    .expect("Invalid graph service URL")
    .connect_lazy();

    // Initialize layers
    let recall_layer = RecallLayer::new(graph_client, redis_client, config.recall.clone());
    let ranking_layer = RankingLayer::new();
    let diversity_layer = DiversityLayer::new(0.7); // lambda = 0.7

    // Create gRPC service
    let ranking_service = RankingServiceImpl::new(recall_layer, ranking_layer, diversity_layer);

    // Start gRPC server
    let addr = format!("0.0.0.0:{}", config.service.grpc_port)
        .parse()
        .expect("Invalid gRPC address");

    info!("gRPC server listening on {}", addr);

    Server::builder()
        .add_service(RankingServiceServer::new(ranking_service))
        .serve(addr)
        .await
        .map_err(|e| {
            error!("gRPC server error: {}", e);
            e
        })?;

    Ok(())
}
