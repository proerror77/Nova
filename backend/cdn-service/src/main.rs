use actix_web::{web, App, HttpServer};
use cdn_service::services::{AssetManager, CacheInvalidator, UrlSigner};
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use std::io;
use std::sync::Arc;
use tonic::transport::Server as GrpcServer;
use tonic_health::server::health_reporter;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting cdn-service");

    // Initialize database (standardized pool)
    let mut cfg = DbPoolConfig::from_env().unwrap_or_default();
    if cfg.database_url.is_empty() {
        cfg.database_url = std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://postgres:postgres@localhost/nova".into());
    }
    if cfg.max_connections < 20 {
        cfg.max_connections = 20;
    }
    let db_pool = Arc::new(
        create_pg_pool(cfg)
            .await
            .expect("Failed to create database pool"),
    );

    // Initialize AWS S3 client
    let aws_config = aws_config::defaults(aws_config::BehaviorVersion::latest())
        .load()
        .await;
    let s3_client = Arc::new(aws_sdk_s3::Client::new(&aws_config));
    let s3_bucket = std::env::var("S3_BUCKET").unwrap_or_else(|_| "nova-cdn".into());

    // Initialize Redis client
    let redis_url = std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".into());
    let redis_client =
        Arc::new(redis::Client::open(redis_url).expect("Failed to create Redis client"));

    // Initialize services
    let cdn_domain = std::env::var("CDN_DOMAIN").unwrap_or_else(|_| "cdn.nova.dev".into());
    let secret_key = std::env::var("CDN_SECRET_KEY")
        .unwrap_or_else(|_| "default-secret-key-change-in-production".into());

    let url_signer = Arc::new(UrlSigner::new(secret_key, cdn_domain));
    let asset_manager = Arc::new(AssetManager::new(
        db_pool.clone(),
        s3_client,
        s3_bucket,
        url_signer.clone(),
    ));
    let cache_invalidator = Arc::new(CacheInvalidator::new(db_pool.clone(), redis_client));

    // Compute HTTP and gRPC ports
    let http_port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8000);
    let grpc_port: u16 = http_port + 1000;

    // Start gRPC server in background on http_port + 1000
    let grpc_addr: std::net::SocketAddr = format!("0.0.0.0:{}", grpc_port).parse().unwrap();

    let grpc_asset_manager = asset_manager.clone();
    let grpc_cache_invalidator = cache_invalidator.clone();
    let grpc_url_signer = url_signer.clone();

    tokio::spawn(async move {
        let (mut health, health_service) = health_reporter();
        health.set_serving::<cdn_service::grpc::nova::cdn_service::v1::cdn_service_server::CdnServiceServer<cdn_service::grpc::CdnServiceImpl>>().await;

        // Server-side correlation-id extractor interceptor
        fn server_interceptor(
            mut req: tonic::Request<()>,
        ) -> Result<tonic::Request<()>, tonic::Status> {
            let correlation_id = req
                .metadata()
                .get("correlation-id")
                .and_then(|val| val.to_str().ok())
                .map(|s| s.to_string());

            if let Some(id) = correlation_id {
                req.extensions_mut().insert::<String>(id);
            }
            Ok(req)
        }

        let svc = cdn_service::grpc::CdnServiceImpl::new(
            grpc_asset_manager,
            grpc_cache_invalidator,
            grpc_url_signer,
        );

        tracing::info!("cdn-service gRPC listening on {}", grpc_addr);

        if let Err(e) = GrpcServer::builder()
            .add_service(health_service)
            .add_service(
                cdn_service::grpc::nova::cdn_service::v1::cdn_service_server::CdnServiceServer::with_interceptor(
                    svc,
                    server_interceptor,
                ),
            )
            .serve(grpc_addr)
            .await
        {
            tracing::error!("cdn-service gRPC server error: {}", e);
        }
    });

    // Start HTTP server
    tracing::info!("cdn-service HTTP listening on 0.0.0.0:{}", http_port);
    HttpServer::new(move || App::new().route("/health", web::get().to(|| async { "OK" })))
        .bind(("0.0.0.0", http_port))?
        .run()
        .await
}
