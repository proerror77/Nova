use actix_web::{middleware, web, App, HttpServer};
use tonic::transport::Server as GrpcServer;
use std::io;
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use std::sync::Arc;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use notification_service::{
    NotificationService,
    ConnectionManager,
    metrics,
    handlers::{
        notifications::register_routes as register_notifications,
        devices::register_routes as register_devices,
        preferences::register_routes as register_preferences,
        websocket::register_routes as register_websocket,
    },
};

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

    tracing::info!("Starting notification service");

    // Initialize database
    let db_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://user:password@localhost/nova".to_string());

    let mut cfg = DbPoolConfig::from_env().unwrap_or_default();
    if cfg.database_url.is_empty() { cfg.database_url = db_url.clone(); }
    if cfg.max_connections < 20 { cfg.max_connections = 20; }
    let db_pool = match create_pg_pool(cfg).await {
        Ok(pool) => {
            tracing::info!("Successfully connected to database");
            pool
        }
        Err(e) => {
            tracing::warn!("Failed to connect to database: {}. Running in offline mode", e);
            tracing::info!("Some features will not work without database connection");
            return Err(io::Error::new(io::ErrorKind::Other, "Database connection failed"));
        }
    };

    // Initialize FCM and APNs clients (optional - for now, disabled)
    // These would need proper credential configuration

    let notification_service = Arc::new(NotificationService::new(
        db_pool,
        None, // FCM client
        None, // APNs client
    ));

    // Initialize WebSocket connection manager
    let connection_manager = Arc::new(ConnectionManager::new());
    tracing::info!("WebSocket connection manager initialized");

    let port = std::env::var("PORT")
        .unwrap_or_else(|_| "8000".to_string());
    let addr = format!("0.0.0.0:{}", port);

    tracing::info!("Starting HTTP server on {}", addr);

    // Start gRPC server in background on port +1000
    let grpc_addr: std::net::SocketAddr = format!(
        "0.0.0.0:{}",
        port.parse::<u16>().unwrap_or(8000) + 1000
    )
    .parse()
    .expect("Invalid gRPC address");
    tokio::spawn(async move {
        let svc = notification_service::grpc::NotificationServiceImpl::default();
        tracing::info!("gRPC server listening on {}", grpc_addr);
        if let Err(e) = GrpcServer::builder()
            .add_service(
                notification_service::grpc::nova::notification_service::v1::notification_service_server::NotificationServiceServer::new(
                    svc,
                ),
            )
            .serve(grpc_addr)
            .await
        {
            tracing::error!("gRPC server error: {}", e);
        }
    });

    // Start HTTP server
    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(notification_service.clone()))
            .app_data(web::Data::new(connection_manager.clone()))
            .wrap(middleware::Logger::default())
            .wrap(metrics::MetricsMiddleware)
            .route("/health", web::get().to(|| async { "OK" }))
            .route("/metrics", web::get().to(notification_service::metrics::serve_metrics))
            .route("/", web::get().to(|| async { "Notification Service v1.0" }))
            .configure(|cfg| {
                register_notifications(cfg);
                register_devices(cfg);
                register_preferences(cfg);
                register_websocket(cfg);
            })
    })
        .bind(&addr)?
        .run()
        .await
}
