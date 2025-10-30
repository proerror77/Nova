use actix_web::{middleware, web, App, HttpServer};
use std::io;
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

    let db_pool = match sqlx::postgres::PgPoolOptions::new()
        .max_connections(10)
        .connect(&db_url)
        .await
    {
        Ok(pool) => {
            tracing::info!("Successfully connected to database");
            pool
        }
        Err(e) => {
            tracing::warn!("Failed to connect to database: {}. Running in offline mode", e);
            tracing::info!("Some features will not work without database connection");
            // In a real scenario, we might want to exit here
            // For now, we'll create a dummy pool or handle it gracefully
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
