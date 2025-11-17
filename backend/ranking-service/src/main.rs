use once_cell::sync::OnceCell;
use ranking_service::{
    grpc::{ranking_proto::ranking_service_server::RankingServiceServer, RankingServiceImpl},
    Config, DiversityLayer, RankingLayer, RecallLayer,
};
use tonic::{metadata::MetadataValue, transport::Server, Request, Status};
use tracing::{error, info, warn};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};
use uuid::Uuid;

static INTERNAL_GRPC_API_KEY: OnceCell<Option<String>> = OnceCell::new();

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
    let redis_client =
        redis::Client::open(config.redis.url.clone()).expect("Failed to create Redis client");

    // Initialize gRPC clients
    let graph_client =
        tonic::transport::Channel::from_shared(config.grpc_clients.graph_service_url.clone())
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
                return Err(err.into());
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
        let server_tls = cfg.build_server_tls()?;
        server_builder = server_builder.tls_config(server_tls)?;
    }

    server_builder
        .add_service(RankingServiceServer::with_interceptor(
            ranking_service,
            grpc_server_interceptor,
        ))
        .serve(addr)
        .await
        .map_err(|e| {
            error!("gRPC server error: {}", e);
            e
        })?;

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
