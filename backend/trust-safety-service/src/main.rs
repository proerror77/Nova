use std::sync::Arc;
use trust_safety_service::{
    config::Config,
    db::ModerationDb,
    grpc::{
        server::trust_safety::trust_safety_service_server::TrustSafetyServiceServer,
        TrustSafetyServiceImpl,
    },
    services::{AppealService, NsfwDetector, SpamDetector, TextModerator},
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_target(false)
        .with_thread_ids(true)
        .with_level(true)
        .with_ansi(true)
        .init();

    tracing::info!("Starting Trust & Safety Service...");

    // Load configuration
    let config = Config::from_env()?;
    tracing::info!(
        service = %config.service_name,
        environment = %config.environment,
        grpc_port = %config.grpc_port,
        "Configuration loaded"
    );

    // Initialize database pool using shared library
    let db =
        Arc::new(db_pool::create_pool(db_pool::DbConfig::for_service(&config.service_name)).await?);
    tracing::info!("Database pool initialized");

    // Run migrations
    tracing::info!("Running database migrations...");
    sqlx::migrate!("./migrations")
        .run(&*db)
        .await
        .map_err(|e| {
            tracing::error!("Migration failed: {}", e);
            e
        })?;
    tracing::info!("Migrations completed successfully");

    // Initialize NSFW detector
    tracing::info!("Loading NSFW detection model...");
    let nsfw_detector = match NsfwDetector::new(&config.nsfw_model_path) {
        Ok(detector) => {
            tracing::info!("NSFW detector initialized");
            Arc::new(detector)
        }
        Err(e) => {
            tracing::warn!(
                "NSFW detector initialization failed: {}. Service will run without NSFW detection.",
                e
            );
            // Create a dummy detector for now (production should fail here)
            return Err(format!("NSFW detector required but failed to load: {}", e).into());
        }
    };

    // Initialize text moderator
    tracing::info!("Loading text moderation rules...");
    let text_moderator = TextModerator::new(&config.sensitive_words_path)?;
    tracing::info!("Text moderator initialized");

    // Initialize spam detector
    let spam_detector = Arc::new(SpamDetector::new());
    tracing::info!("Spam detector initialized");

    // Initialize services
    let moderation_db = Arc::new(ModerationDb::new(db.clone()));
    let appeal_service = Arc::new(AppealService::new(db.clone()));

    // Create gRPC service
    let trust_safety_service = TrustSafetyServiceImpl::new(
        Arc::new(config.clone()),
        nsfw_detector,
        Arc::new(text_moderator),
        spam_detector,
        appeal_service,
        moderation_db,
    );

    // Start health check server (HTTP)
    let health_addr = format!("0.0.0.0:{}", config.health_port);
    let health_addr_clone = health_addr.clone();
    let health_server = tokio::spawn(async move {
        use actix_web::{web, App, HttpResponse, HttpServer};

        HttpServer::new(|| {
            App::new()
                .route(
                    "/health",
                    web::get().to(|| async { HttpResponse::Ok().body("OK") }),
                )
                .route(
                    "/ready",
                    web::get().to(|| async { HttpResponse::Ok().body("READY") }),
                )
        })
        .bind(&health_addr_clone)
        .expect("Failed to bind health check HTTP server address")
        .run()
        .await
    });

    tracing::info!("Health check server started on {}", health_addr);

    // Start gRPC server with mTLS
    let grpc_addr = format!("0.0.0.0:{}", config.grpc_port).parse()?;
    tracing::info!("Loading mTLS configuration...");

    let tls_config = grpc_tls::mtls::load_mtls_server_config()
        .await
        .map_err(|e| {
            tracing::error!("Failed to load mTLS config: {}", e);
            e
        })?;

    tracing::info!("mTLS configuration loaded successfully");
    tracing::info!("Starting gRPC server on {}...", grpc_addr);

    // Create gRPC server with health check
    let (mut health_reporter, health_service) = tonic_health::server::health_reporter();
    health_reporter
        .set_serving::<TrustSafetyServiceServer<TrustSafetyServiceImpl>>()
        .await;

    let grpc_server = tonic::transport::Server::builder()
        .tls_config(tls_config)?
        .add_service(health_service)
        .add_service(TrustSafetyServiceServer::new(trust_safety_service))
        .serve(grpc_addr);

    tracing::info!("🚀 Trust & Safety Service is running");
    tracing::info!("   gRPC: {}", grpc_addr);
    tracing::info!("   Health: http://0.0.0.0:{}", config.health_port);

    // Run both servers concurrently
    tokio::select! {
        result = grpc_server => {
            if let Err(e) = result {
                tracing::error!("gRPC server error: {}", e);
            }
        }
        result = health_server => {
            if let Err(e) = result {
                tracing::error!("Health server error: {}", e);
            }
        }
    }

    Ok(())
}
