use actix_web::{web, App, HttpServer};
use tonic::transport::Server as GrpcServer;
use tonic_health::server::health_reporter;
use std::io;
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
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

    tracing::info!("Starting service");

    // Initialize database (standardized pool)
    let mut cfg = DbPoolConfig::from_env().unwrap_or_default();
    if cfg.database_url.is_empty() {
        cfg.database_url = std::env::var("DATABASE_URL").unwrap_or_default();
    }
    if cfg.max_connections < 20 { cfg.max_connections = 20; }
    cfg.log_config();
    let db_pool = create_pg_pool(cfg).await.ok();

    // Compute HTTP and gRPC ports
    let http_port: u16 = std::env::var("PORT").ok().and_then(|s| s.parse().ok()).unwrap_or(8000);
    let grpc_port: u16 = http_port + 1000;
    // Start gRPC server in background on http_port + 1000
    let grpc_addr: std::net::SocketAddr = format!("0.0.0.0:{}", grpc_port).parse().unwrap();
    tokio::spawn(async move {
        let (mut health, health_service) = health_reporter();
        health.set_serving::<events_service::grpc::nova::events_service::v1::events_service_server::EventsServiceServer<events_service::grpc::EventsServiceImpl>>().await;

        // Server-side correlation-id extractor interceptor
        fn server_interceptor(mut req: tonic::Request<()>) -> Result<tonic::Request<()>, tonic::Status> {
            if let Some(val) = req.metadata().get("correlation-id") {
                if let Ok(s) = val.to_str() { req.extensions_mut().insert::<String>(s.to_string()); }
            }
            Ok(req)
        }

        let svc = events_service::grpc::EventsServiceImpl::default();
        if let Err(e) = GrpcServer::builder()
            .add_service(health_service)
            .add_service(events_service::grpc::nova::events_service::v1::events_service_server::EventsServiceServer::with_interceptor(svc, server_interceptor))
            .serve(grpc_addr)
            .await
        {
            tracing::error!("events-service gRPC server error: {}", e);
        }
    });

    // Start HTTP server
    HttpServer::new(move || App::new().route("/health", web::get().to(|| async { "OK" })))
        .bind(("0.0.0.0", http_port))?
        .run()
        .await
}
