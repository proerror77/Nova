use actix_web::{middleware, web, App, HttpServer};
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use notification_service::{
    handlers::{
        devices::register_routes as register_devices,
        notifications::register_routes as register_notifications,
        preferences::register_routes as register_preferences,
        websocket::register_routes as register_websocket,
    },
    metrics, ConnectionManager, NotificationService,
};
use std::io;
use std::sync::Arc;
use tonic::transport::Server as GrpcServer;
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

    tracing::info!("Starting notification service");

    // Initialize database
    let db_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://user:password@localhost/nova".to_string());

    let mut cfg = DbPoolConfig::from_env().unwrap_or_default();
    if cfg.database_url.is_empty() {
        cfg.database_url = db_url.clone();
    }
    if cfg.max_connections < 20 {
        cfg.max_connections = 20;
    }
    let db_pool = match create_pg_pool(cfg).await {
        Ok(pool) => {
            tracing::info!("Successfully connected to database");
            pool
        }
        Err(e) => {
            tracing::warn!(
                "Failed to connect to database: {}. Running in offline mode",
                e
            );
            tracing::info!("Some features will not work without database connection");
            return Err(io::Error::new(
                io::ErrorKind::Other,
                "Database connection failed",
            ));
        }
    };

    // Initialize FCM and APNs clients (optional - for now, disabled)
    // These would need proper credential configuration

    let notification_service = Arc::new(NotificationService::new(
        db_pool.clone(),
        None, // FCM client
        None, // APNs client
    ));

    // Initialize WebSocket connection manager
    let connection_manager = Arc::new(ConnectionManager::new());
    tracing::info!("WebSocket connection manager initialized");

    let port = std::env::var("PORT").unwrap_or_else(|_| "8000".to_string());
    let addr = format!("0.0.0.0:{}", port);

    tracing::info!("Starting HTTP server on {}", addr);

    // Start gRPC server in background on port + 1000
    let http_port_u16 = port.parse::<u16>().unwrap_or(8000);
    let grpc_addr: std::net::SocketAddr = format!("0.0.0.0:{}", http_port_u16 + 1000)
        .parse()
        .expect("Invalid gRPC address");

    let grpc_db_pool = db_pool.clone();
    let grpc_notification_service = notification_service.clone();
    tokio::spawn(async move {
        use notification_service::grpc::{
            nova::notification_service::v1::notification_service_server::NotificationServiceServer,
            NotificationServiceImpl,
        };
        use notification_service::services::PushSender;

        // Server-side correlation-id extractor interceptor
        fn server_interceptor(
            mut req: tonic::Request<()>,
        ) -> Result<tonic::Request<()>, tonic::Status> {
            let correlation_id = req
                .metadata()
                .get("correlation-id")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string());

            if let Some(id) = correlation_id {
                req.extensions_mut().insert::<String>(id);
            }
            Ok(req)
        }

        let push_sender = Arc::new(PushSender::new(grpc_db_pool.clone(), None, None));
        let svc =
            NotificationServiceImpl::new(grpc_db_pool, grpc_notification_service, push_sender);

        tracing::info!("gRPC server listening on {}", grpc_addr);
        if let Err(e) = GrpcServer::builder()
            .add_service(NotificationServiceServer::with_interceptor(
                svc,
                server_interceptor,
            ))
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
            .route(
                "/metrics",
                web::get().to(notification_service::metrics::serve_metrics),
            )
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
