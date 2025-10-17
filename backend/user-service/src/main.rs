use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpServer};
use std::io;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use user_service::{
    config::Config,
    db::{create_pool, run_migrations},
    handlers,
};

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=debug,sqlx=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load configuration
    let config = Config::from_env()
        .expect("Failed to load configuration");

    tracing::info!("Starting user-service v{}", env!("CARGO_PKG_VERSION"));
    tracing::info!("Environment: {}", config.app.env);

    // Create database connection pool
    let db_pool = create_pool(&config.database.url, config.database.max_connections)
        .await
        .expect("Failed to create database pool");

    tracing::info!("Database pool created with {} max connections", config.database.max_connections);

    // Run migrations
    if !config.is_production() {
        tracing::info!("Running database migrations...");
        run_migrations(&db_pool)
            .await
            .expect("Failed to run migrations");
        tracing::info!("Database migrations completed");
    }

    // Create Redis connection manager
    let redis_client = redis::Client::open(config.redis.url.as_str())
        .expect("Failed to create Redis client");

    let redis_manager = redis_client
        .get_connection_manager()
        .await
        .expect("Failed to create Redis connection manager");

    tracing::info!("Redis connection established");

    // Clone config for server closure
    let server_config = config.clone();
    let bind_address = format!("{}:{}", config.app.host, config.app.port);

    tracing::info!("Starting HTTP server at {}", bind_address);

    // Create and run HTTP server
    HttpServer::new(move || {
        let cors = Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .max_age(3600);

        App::new()
            .app_data(web::Data::new(db_pool.clone()))
            .app_data(web::Data::new(redis_manager.clone()))
            .app_data(web::Data::new(server_config.clone()))
            .wrap(cors)
            .wrap(Logger::default())
            .wrap(tracing_actix_web::TracingLogger::default())
            .service(
                web::scope("/api/v1")
                    // Health check endpoints
                    .route("/health", web::get().to(handlers::health_check))
                    .route("/health/ready", web::get().to(handlers::readiness_check))
                    .route("/health/live", web::get().to(handlers::liveness_check))
                    // Auth endpoints (placeholders)
                    .service(
                        web::scope("/auth")
                            .route("/register", web::post().to(handlers::register))
                            .route("/login", web::post().to(handlers::login))
                            .route("/logout", web::post().to(handlers::logout))
                            .route("/refresh", web::post().to(handlers::refresh_token))
                    )
            )
    })
    .bind(&bind_address)?
    .workers(4)
    .run()
    .await
}
