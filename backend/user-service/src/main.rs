use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpServer};
use std::io;
use std::sync::Arc;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use user_service::{
    config::Config,
    db::{create_pool, run_migrations},
    handlers,
    middleware::JwtAuthMiddleware,
    services::{job_queue, s3_service},
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
    let config = Config::from_env().expect("Failed to load configuration");

    tracing::info!("Starting user-service v{}", env!("CARGO_PKG_VERSION"));
    tracing::info!("Environment: {}", config.app.env);

    // ========================================
    // Initialize JWT keys from environment
    // ========================================
    user_service::security::jwt::initialize_keys(&config.jwt.private_key_pem, &config.jwt.public_key_pem)
        .expect("Failed to initialize JWT keys from environment variables");
    tracing::info!("JWT keys initialized from environment variables");

    // Create database connection pool
    let db_pool = create_pool(&config.database.url, config.database.max_connections)
        .await
        .expect("Failed to create database pool");

    tracing::info!(
        "Database pool created with {} max connections",
        config.database.max_connections
    );

    // Run migrations
    if !config.is_production() {
        tracing::info!("Running database migrations...");
        run_migrations(&db_pool)
            .await
            .expect("Failed to run migrations");
        tracing::info!("Database migrations completed");
    }

    // Create Redis connection manager
    let redis_client =
        redis::Client::open(config.redis.url.as_str()).expect("Failed to create Redis client");

    let redis_manager = redis_client
        .get_connection_manager()
        .await
        .expect("Failed to create Redis connection manager");

    tracing::info!("Redis connection established");

    // ========================================
    // Initialize image processing job queue
    // ========================================
    let (job_sender, job_receiver) = job_queue::create_job_queue(100);
    tracing::info!("Image processing job queue created (capacity: 100)");

    // Create S3 client for worker
    let s3_client = s3_service::get_s3_client(&config.s3)
        .await
        .expect("Failed to create S3 client for worker");
    tracing::info!("S3 client initialized for image processor");

    // Spawn image processor worker task
    let worker_handle = job_queue::spawn_image_processor_worker(
        db_pool.clone(),
        s3_client,
        Arc::new(config.s3.clone()),
        job_receiver,
    );
    tracing::info!("Image processor worker spawned");

    // Clone config for server closure
    let server_config = config.clone();
    let bind_address = format!("{}:{}", config.app.host, config.app.port);

    tracing::info!("Starting HTTP server at {}", bind_address);

    // Clone job_sender for graceful shutdown (will be dropped after server stops)
    let job_sender_shutdown = job_sender.clone();

    // Create and run HTTP server
    let server = HttpServer::new(move || {
        // Build CORS configuration from allowed_origins
        let cors_builder = Cors::default();

        // Parse and apply allowed origins
        let mut cors = cors_builder;
        for origin in server_config.cors.allowed_origins.split(',') {
            let origin = origin.trim();
            if origin == "*" {
                // Allow any origin (use cautiously - NOT recommended for production)
                cors = cors.allow_any_origin();
            } else {
                // Allow specific origin
                cors = cors.allowed_origin(origin);
            }
        }

        cors = cors.allow_any_method().allow_any_header().max_age(3600);

        App::new()
            .app_data(web::Data::new(db_pool.clone()))
            .app_data(web::Data::new(redis_manager.clone()))
            .app_data(web::Data::new(server_config.clone()))
            .app_data(web::Data::new(job_sender.clone()))
            .wrap(cors)
            .wrap(Logger::default())
            .wrap(tracing_actix_web::TracingLogger::default())
            .service(
                web::scope("/api/v1")
                    // Health check endpoints
                    .route("/health", web::get().to(handlers::health_check))
                    .route("/health/ready", web::get().to(handlers::readiness_check))
                    .route("/health/live", web::get().to(handlers::liveness_check))
                    // Auth endpoints
                    .service(
                        web::scope("/auth")
                            .route("/register", web::post().to(handlers::register))
                            .route("/login", web::post().to(handlers::login))
                            .route("/verify-email", web::post().to(handlers::verify_email))
                            .route("/logout", web::post().to(handlers::logout))
                            .route("/refresh", web::post().to(handlers::refresh_token)),
                    )
                    // Posts endpoints (protected with JWT authentication)
                    .service(
                        web::scope("/posts")
                            .wrap(JwtAuthMiddleware)
                            .route(
                                "/upload/init",
                                web::post().to(handlers::upload_init_request),
                            )
                            .route(
                                "/upload/complete",
                                web::post().to(handlers::upload_complete_request),
                            )
                            .route("/{id}", web::get().to(handlers::get_post_request)),
                    ),
            )
    })
    .bind(&bind_address)?
    .workers(4)
    .run();

    // Gracefully shutdown worker on server exit
    // The server will run until Ctrl+C or other shutdown signal
    let result = server.await;

    // ========================================
    // Cleanup: Graceful worker shutdown
    // ========================================
    tracing::info!("Server shutting down. Closing job queue...");

    // Close job queue channel to stop worker
    drop(job_sender_shutdown);

    // Wait for worker to finish processing remaining jobs
    match tokio::time::timeout(std::time::Duration::from_secs(30), worker_handle).await {
        Ok(Ok(())) => {
            tracing::info!("Image processor worker shut down gracefully");
        }
        Ok(Err(e)) => {
            tracing::error!("Image processor worker panicked: {:?}", e);
        }
        Err(_) => {
            tracing::warn!("Image processor worker did not shut down within timeout");
        }
    }

    tracing::info!("All workers stopped. Server shutdown complete.");

    result
}
