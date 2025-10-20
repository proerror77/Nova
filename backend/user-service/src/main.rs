use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer};
use std::io;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use user_service::{
    cache::FeedCache,
    config::Config,
    db::{ch_client::ClickHouseClient, create_pool, run_migrations},
    handlers,
    handlers::{events::EventHandlerState, feed::FeedHandlerState},
    metrics,
    middleware::{JwtAuthMiddleware, MetricsMiddleware},
    services::{
        cdc::{CdcConsumer, CdcConsumerConfig},
        events::{EventDeduplicator, EventsConsumer, EventsConsumerConfig},
        feed_ranking::FeedRankingService,
        job_queue,
        kafka_producer::EventProducer,
        s3_service,
    },
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
    user_service::security::jwt::initialize_keys(
        &config.jwt.private_key_pem,
        &config.jwt.public_key_pem,
    )
    .expect("Failed to initialize JWT keys from environment variables");
    tracing::info!("JWT keys initialized from environment variables");

    // ========================================
    // Initialize Prometheus metrics
    // ========================================
    metrics::init_metrics();
    tracing::info!("Prometheus metrics initialized");

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
    // Initialize ClickHouse client & feed services
    // ========================================
    let clickhouse_client = Arc::new(ClickHouseClient::new(
        &config.clickhouse.url,
        &config.clickhouse.database,
        &config.clickhouse.username,
        &config.clickhouse.password,
        config.clickhouse.timeout_ms,
    ));

    if let Err(e) = clickhouse_client.health_check().await {
        tracing::warn!("ClickHouse health check failed: {}", e);
    } else {
        tracing::info!("ClickHouse connection validated");
    }

    let feed_cache = FeedCache::new(redis_manager.clone(), 120);
    let feed_cache = Arc::new(Mutex::new(feed_cache));
    let feed_ranking = Arc::new(FeedRankingService::new(
        Default::default(), // Use default config
    ));

    let feed_state = web::Data::new(FeedHandlerState {
        feed_ranking: feed_ranking.clone(),
    });

    // ========================================
    // Initialize Kafka producer for events
    // ========================================
    let event_producer = Arc::new(
        EventProducer::new(&config.kafka.brokers, config.kafka.events_topic.clone())
            .expect("Failed to create Kafka producer"),
    );

    let events_state = web::Data::new(EventHandlerState {
        producer: event_producer.clone(),
    });

    // ========================================
    // Initialize CDC Consumer (PostgreSQL → Kafka → ClickHouse)
    // ========================================
    let ch_writable = Arc::new(ClickHouseClient::new_writable(
        &config.clickhouse.url,
        &config.clickhouse.database,
        &config.clickhouse.username,
        &config.clickhouse.password,
        config.clickhouse.timeout_ms,
    ));

    let cdc_config = CdcConsumerConfig {
        brokers: config.kafka.brokers.clone(),
        group_id: "nova-cdc-consumer-v1".to_string(),
        topics: vec![
            "cdc.posts".to_string(),
            "cdc.follows".to_string(),
            "cdc.comments".to_string(),
            "cdc.likes".to_string(),
        ],
        max_concurrent_inserts: 10,
    };

    let cdc_consumer = CdcConsumer::new(cdc_config, ch_writable.as_ref().clone(), db_pool.clone())
        .await
        .expect("Failed to create CDC consumer");

    let cdc_handle = tokio::spawn(async move {
        if let Err(e) = cdc_consumer.run().await {
            tracing::error!("CDC consumer error: {}", e);
        }
    });
    tracing::info!("CDC consumer spawned");

    // ========================================
    // Initialize Events Consumer (Kafka → ClickHouse for analytics)
    // ========================================
    let event_deduplicator = EventDeduplicator::new(redis_client.clone(), 3600);

    let events_config = EventsConsumerConfig {
        brokers: config.kafka.brokers.clone(),
        group_id: "nova-events-consumer-v1".to_string(),
        topic: config.kafka.events_topic.clone(),
        batch_size: 100,
        max_concurrent_inserts: 5,
    };

    let events_consumer = EventsConsumer::new(
        events_config,
        ch_writable.as_ref().clone(),
        event_deduplicator,
    )
    .expect("Failed to create Events consumer");

    let events_handle = tokio::spawn(async move {
        if let Err(e) = events_consumer.run().await {
            tracing::error!("Events consumer error: {}", e);
        }
    });
    tracing::info!("Events consumer spawned");

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
        let feed_state = feed_state.clone();
        let events_state = events_state.clone();
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
            .app_data(feed_state.clone())
            .app_data(events_state.clone())
            .wrap(cors)
            .wrap(Logger::default())
            .wrap(tracing_actix_web::TracingLogger::default())
            .wrap(MetricsMiddleware) // Add metrics middleware
            // Prometheus metrics endpoint
            .route(
                "/metrics",
                web::get().to(|| async {
                    HttpResponse::Ok()
                        .content_type("text/plain; version=0.0.4")
                        .body(metrics::gather_metrics())
                }),
            )
            // JWKS public key endpoint
            .route("/.well-known/jwks.json", web::get().to(handlers::get_jwks))
            .service(
                web::scope("/api/v1")
                    // Health check endpoints
                    .route("/health", web::get().to(handlers::health_check))
                    .route("/health/ready", web::get().to(handlers::readiness_check))
                    .route("/health/live", web::get().to(handlers::liveness_check))
                    .service(
                        web::scope("/feed")
                            .wrap(JwtAuthMiddleware)
                            .app_data(feed_state.clone())
                            .service(handlers::get_feed)
                            .service(handlers::get_trending)
                            .service(handlers::invalidate_feed_cache),
                    )
                    .service(
                        web::scope("/reels")
                            .wrap(JwtAuthMiddleware)
                            .service(handlers::reels_get_feed)
                            .service(handlers::get_video_stream)
                            .service(handlers::get_processing_status)
                            .service(handlers::like_video)
                            .service(handlers::watch_video)
                            .service(handlers::share_video)
                            .service(handlers::get_trending_sounds)
                            .service(handlers::get_trending_hashtags)
                            .service(handlers::search_videos)
                            .service(handlers::get_similar_videos)
                    )
                    .service(
                        web::scope("/discover")
                            .wrap(JwtAuthMiddleware)
                            .service(handlers::get_suggested_users)
                            .service(handlers::get_recommended_creators),
                    )
                    .service(
                        web::scope("/events")
                            .app_data(events_state.clone())
                            .service(handlers::ingest_events),
                    )
                    // Auth endpoints
                    .service(
                        web::scope("/auth")
                            .route("/register", web::post().to(handlers::register))
                            .route("/login", web::post().to(handlers::login))
                            .route("/verify-email", web::post().to(handlers::verify_email))
                            .route("/logout", web::post().to(handlers::logout))
                            .route("/refresh", web::post().to(handlers::refresh_token))
                            .route(
                                "/forgot-password",
                                web::post().to(handlers::forgot_password),
                            )
                            .route("/reset-password", web::post().to(handlers::reset_password))
                            // 2FA endpoints
                            .service(
                                web::scope("/2fa")
                                    .wrap(JwtAuthMiddleware)
                                    .route("/enable", web::post().to(handlers::enable_2fa))
                                    .route("/confirm", web::post().to(handlers::confirm_2fa)),
                            )
                            .route("/2fa/verify", web::post().to(handlers::verify_2fa))
                            // OAuth endpoints
                            .route("/oauth/authorize", web::post().to(handlers::authorize))
                            .service(
                                web::scope("/oauth")
                                    .wrap(JwtAuthMiddleware)
                                    .route("/link", web::post().to(handlers::link_provider))
                                    .route(
                                        "/link/{provider}",
                                        web::delete().to(handlers::unlink_provider),
                                    ),
                            ),
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
    tracing::info!("Server shutting down. Stopping background services...");

    // Close job queue channel to stop worker
    drop(job_sender_shutdown);

    // Wait for image processor worker
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

    // Abort CDC consumer (long-running Kafka consumer loop)
    cdc_handle.abort();
    match tokio::time::timeout(std::time::Duration::from_secs(5), cdc_handle).await {
        Ok(Ok(())) => {
            tracing::info!("CDC consumer shut down gracefully");
        }
        Ok(Err(_)) => {
            tracing::info!("CDC consumer aborted");
        }
        Err(_) => {
            tracing::warn!("CDC consumer did not shut down within timeout");
        }
    }

    // Abort Events consumer
    events_handle.abort();
    match tokio::time::timeout(std::time::Duration::from_secs(5), events_handle).await {
        Ok(Ok(())) => {
            tracing::info!("Events consumer shut down gracefully");
        }
        Ok(Err(_)) => {
            tracing::info!("Events consumer aborted");
        }
        Err(_) => {
            tracing::warn!("Events consumer did not shut down within timeout");
        }
    }

    tracing::info!("All workers and consumers stopped. Server shutdown complete.");

    result
}
