use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer};
use std::io;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use tokio::sync::Mutex;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use user_service::grpc::{ContentServiceClient, GrpcClientConfig, HealthChecker};
use user_service::{
    config::video_config,
    config::Config,
    db::{ch_client::ClickHouseClient, create_pool, run_migrations},
    handlers,
    handlers::{
        events::EventHandlerState, feed::FeedHandlerState, health::HealthCheckState,
        streams::StreamHandlerState,
    },
    jobs::{
        self, run_jobs, suggested_users_generator::SuggestedUsersJob,
        suggested_users_generator::SuggestionConfig,
    },
    metrics,
    middleware::{
        CircuitBreaker, CircuitBreakerConfig, GlobalRateLimitMiddleware, JwtAuthMiddleware,
        MetricsMiddleware, RateLimiter,
    },
    services::{
        cdc::{CdcConsumer, CdcConsumerConfig},
        deep_learning_inference::DeepLearningInferenceService,
        events::{EventDeduplicator, EventsConsumer, EventsConsumerConfig},
        graph::GraphService,
        job_queue,
        kafka_producer::EventProducer,
        oauth::jwks_cache::JWKSCache,
        s3_service,
        stories::StoriesService,
        streaming::{
            RtmpWebhookHandler, StreamAnalyticsService, StreamChatHandlerState, StreamChatStore,
            StreamDiscoveryService, StreamRepository, StreamService, ViewerCounter,
        },
        video_service::VideoService,
    },
};

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Support container healthchecks via CLI subcommand: `healthcheck-http` or legacy `healthcheck`
    // It checks the HTTP endpoint /api/v1/health on localhost:8080 and exits accordingly.
    {
        let mut args = std::env::args();
        let _bin = args.next();
        if let Some(cmd) = args.next() {
            if cmd == "healthcheck" || cmd == "healthcheck-http" {
                let url = "http://127.0.0.1:8080/api/v1/health";
                match reqwest::Client::new().get(url).send().await {
                    Ok(resp) if resp.status().is_success() => return Ok(()),
                    Ok(resp) => {
                        eprintln!("healthcheck HTTP status: {}", resp.status());
                        return Err(io::Error::new(io::ErrorKind::Other, "healthcheck failed"));
                    }
                    Err(e) => {
                        eprintln!("healthcheck HTTP error: {}", e);
                        return Err(io::Error::new(io::ErrorKind::Other, "healthcheck error"));
                    }
                }
            }
        }
    }
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
    // 支援從檔案讀取金鑰（JWT_PRIVATE_KEY_FILE / JWT_PUBLIC_KEY_FILE）
    let private_key_pem = if let Ok(path) = std::env::var("JWT_PRIVATE_KEY_FILE") {
        std::fs::read_to_string(path).expect("Failed to read JWT private key file")
    } else {
        config.jwt.private_key_pem.clone()
    };
    let public_key_pem = if let Ok(path) = std::env::var("JWT_PUBLIC_KEY_FILE") {
        std::fs::read_to_string(path).expect("Failed to read JWT public key file")
    } else {
        config.jwt.public_key_pem.clone()
    };

    user_service::security::jwt::initialize_keys(&private_key_pem, &public_key_pem)
        .expect("Failed to initialize JWT keys from environment variables or files");
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

    // Run migrations in non-production unless explicitly skipped
    let run_migrations_env = std::env::var("RUN_MIGRATIONS").unwrap_or_else(|_| "true".into());
    if !config.is_production() && run_migrations_env != "false" {
        tracing::info!("Running database migrations...");
        match run_migrations(&db_pool).await {
            Ok(_) => tracing::info!("Database migrations completed"),
            Err(e) => {
                // 容忍本地/历史迁移缺口（如 VersionMissing），避免开发环境崩溃
                tracing::warn!("Skipping migrations due to error: {:#}", e);
            }
        }
    } else {
        tracing::info!(
            "Skipping database migrations (RUN_MIGRATIONS={})",
            run_migrations_env
        );
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
    // Initialize JWKS cache for OAuth providers
    // ========================================
    let jwks_cache = Arc::new(JWKSCache::new(redis_client.clone()));
    tracing::info!("JWKS cache initialized for OAuth providers (24-hour TTL)");

    // Initialize global rate limiter (100 requests per 15 minutes per IP/user)
    use user_service::middleware::rate_limit::RateLimitConfig;
    let rate_limit_config = RateLimitConfig {
        max_requests: 100,
        window_seconds: 900, // 15 minutes
    };
    let rate_limiter = RateLimiter::new(redis_manager.clone(), rate_limit_config);
    let global_rate_limit = GlobalRateLimitMiddleware::new(rate_limiter);
    tracing::info!("Global rate limiter initialized: 100 requests per 15 minutes");

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

    // CRITICAL: ClickHouse health check MUST succeed before startup
    // Feed ranking is 100% dependent on ClickHouse. No fallback available.
    match clickhouse_client.health_check().await {
        Ok(()) => {
            tracing::info!("✅ ClickHouse connection validated");
        }
        Err(e) => {
            tracing::error!("❌ FATAL: ClickHouse health check failed - {}", e);
            tracing::error!("   Feed ranking cannot function without ClickHouse");
            tracing::error!(
                "   Fix: Ensure ClickHouse is running and accessible at {}",
                config.clickhouse.url
            );
            return Err(io::Error::new(
                io::ErrorKind::ConnectionRefused,
                format!("ClickHouse initialization failed: {}", e),
            ));
        }
    }

    // ========================================
    // Initialize Circuit Breakers for critical services
    // ========================================
    // ClickHouse Circuit Breaker (3 failures → open, 30s timeout, 3 successes to close)
    let clickhouse_circuit_breaker = Arc::new(CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 3,
        success_threshold: 3,
        timeout_seconds: 30,
    }));
    tracing::info!("ClickHouse circuit breaker initialized");

    // Kafka Circuit Breaker (2 failures → open, 60s timeout, 3 successes to close)
    let kafka_circuit_breaker = Arc::new(CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 2,
        success_threshold: 3,
        timeout_seconds: 60,
    }));
    tracing::info!("Kafka circuit breaker initialized");

    // Redis Circuit Breaker (5 failures → open, 15s timeout, 2 successes to close)
    let redis_circuit_breaker = Arc::new(CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 5,
        success_threshold: 2,
        timeout_seconds: 15,
    }));
    tracing::info!("Redis circuit breaker initialized");

    // PostgreSQL Circuit Breaker (4 failures → open, 45s timeout, 3 successes to close)
    let postgres_circuit_breaker = Arc::new(CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 4,
        success_threshold: 3,
        timeout_seconds: 45,
    }));
    tracing::info!("PostgreSQL circuit breaker initialized");

    // Initialize downstream gRPC clients
    let grpc_config =
        GrpcClientConfig::from_env().expect("Failed to load gRPC client configuration");
    let health_checker = Arc::new(HealthChecker::new());
    let content_client = Arc::new(
        ContentServiceClient::new(&grpc_config, health_checker.clone())
            .await
            .expect("Failed to initialize content-service gRPC client"),
    );

    let feed_state = web::Data::new(FeedHandlerState {
        content_client: content_client.clone(),
    });
    let content_client_data = web::Data::new(content_client.clone());
    let health_checker_data = web::Data::new(health_checker.clone());

    // Initialize Neo4j Graph service (optional)
    let graph_service = match GraphService::new(&config.graph).await {
        Ok(svc) => {
            if svc.is_enabled() {
                tracing::info!("Neo4j graph service enabled");
            } else {
                tracing::info!("Neo4j graph service disabled");
            }
            svc
        }
        Err(e) => {
            tracing::warn!("Neo4j service init failed: {} (graph disabled)", e);
            GraphService::new(&user_service::config::GraphConfig {
                enabled: false,
                neo4j_uri: String::new(),
                neo4j_user: String::new(),
                neo4j_password: String::new(),
            })
            .await
            .expect("GraphService disabled init should succeed")
        }
    };
    let graph_data = web::Data::new(graph_service);

    // ========================================
    // Initialize live streaming services
    // ========================================
    let rtmp_base_url = std::env::var("STREAMING_RTMP_BASE_URL")
        .unwrap_or_else(|_| "rtmp://localhost/live".to_string());
    let hls_cdn_url = std::env::var("STREAMING_HLS_BASE_URL")
        .unwrap_or_else(|_| "https://cdn.nova.local".to_string());

    let stream_repo = StreamRepository::new(db_pool.clone());
    let stream_viewer_counter = ViewerCounter::new(redis_manager.clone());
    let stream_chat_store = StreamChatStore::new(redis_manager.clone(), 200);

    // Kafka producer must be initialized before stream service
    // Note: event_producer is initialized later at line 261, so we need to reorganize

    // ========================================
    // Initialize Kafka producer for events (moved earlier)
    // ========================================
    let event_producer = Arc::new(
        EventProducer::new(&config.kafka.brokers, config.kafka.events_topic.clone())
            .expect("Failed to create Kafka producer"),
    );

    let stream_service = Arc::new(Mutex::new(StreamService::new(
        stream_repo.clone(),
        stream_viewer_counter.clone(),
        stream_chat_store,
        event_producer.clone(),
        rtmp_base_url.clone(),
        hls_cdn_url.clone(),
    )));

    let discovery_service = Arc::new(Mutex::new(StreamDiscoveryService::new(
        stream_repo.clone(),
        stream_viewer_counter.clone(),
    )));

    let analytics_service = Arc::new(StreamAnalyticsService::new(stream_repo.clone()));
    let rtmp_handler = Arc::new(Mutex::new(RtmpWebhookHandler::new(
        stream_repo,
        ViewerCounter::new(redis_manager.clone()),
        hls_cdn_url.clone(),
    )));

    let stream_state = web::Data::new(StreamHandlerState {
        stream_service: stream_service.clone(),
        discovery_service: discovery_service.clone(),
        analytics_service: analytics_service.clone(),
        rtmp_handler: rtmp_handler.clone(),
    });

    // ========================================
    // Initialize WebSocket chat for streams
    // ========================================
    let stream_chat_ws_state = web::Data::new(StreamChatHandlerState::new(
        StreamChatStore::new(redis_manager.clone(), 200),
        event_producer.clone(),
        db_pool.clone(),
    ));
    tracing::info!("Stream WebSocket chat handler initialized");

    // ========================================
    // Initialize events state (producer already created above)
    // ========================================
    let events_state = web::Data::new(EventHandlerState {
        producer: event_producer.clone(),
        kafka_cb: kafka_circuit_breaker.clone(),
    });

    let cdc_health_flag = Arc::new(AtomicBool::new(true));

    let health_state = web::Data::new(HealthCheckState::new(
        db_pool.clone(),
        redis_client.clone(),
        Some(clickhouse_client.clone()),
        Some(event_producer.clone()),
        health_checker.clone(),
        cdc_health_flag.clone(),
    ));

    // ========================================
    // Initialize additional handler states with PostgreSQL circuit breaker
    // ========================================
    // posts, videos, likes, comments states REMOVED - moved to content-service and media-service

    let relationships_state = web::Data::new(handlers::relationships::RelationshipsHandlerState {
        postgres_cb: postgres_circuit_breaker.clone(),
    });

    // ========================================
    // Initialize CDC Consumer (PostgreSQL → Kafka → ClickHouse) - MANDATORY
    // ========================================
    // NOTE: CDC is REQUIRED for data consistency between PostgreSQL and ClickHouse
    // Feed ranking depends on ClickHouse sync. Disabling CDC = data inconsistency bug.
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
        .expect("Failed to create CDC consumer - CDC is mandatory for data consistency");

    let cdc_health_for_task = cdc_health_flag.clone();
    let cdc_handle = tokio::spawn(async move {
        if let Err(e) = cdc_consumer.run().await {
            tracing::error!("CDC consumer error: {}", e);
            cdc_health_for_task.store(false, Ordering::SeqCst);
        }
    });
    tracing::info!("CDC consumer spawned (MANDATORY for data consistency)");

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
        content_client.clone(),
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

    // ========================================
    // Initialize S3 client with health check
    // ========================================
    // CRITICAL: S3 health check MUST succeed before startup
    // Video upload/processing is 100% dependent on S3. No fallback available.
    let s3_client = s3_service::get_s3_client(&config.s3)
        .await
        .expect("Failed to create S3 client");

    // Perform S3 health check (bucket access, credentials validation)
    match s3_service::health_check(&s3_client, &config.s3).await {
        Ok(()) => {
            tracing::info!("✅ S3 health check passed");
        }
        Err(e) => {
            tracing::error!("❌ FATAL: S3 health check failed - {}", e);
            tracing::error!("   Video upload functionality cannot work without S3");
            tracing::error!("   Application will not start");
            return Err(io::Error::new(
                io::ErrorKind::ConnectionRefused,
                format!("S3 initialization failed: {}", e),
            ));
        }
    }

    // Spawn image processor worker task
    let worker_handle = job_queue::spawn_image_processor_worker(
        db_pool.clone(),
        s3_client.clone(),
        Arc::new(config.s3.clone()),
        job_receiver,
    );
    tracing::info!("Image processor worker spawned");

    // ========================================
    // Initialize video processing job queue
    // ========================================
    let (video_job_sender, video_job_receiver) =
        user_service::services::video_job_queue::create_video_job_queue(100);
    tracing::info!("Video processing job queue created (capacity: 100)");

    // Spawn video processor worker task
    let _video_worker_handle =
        user_service::services::video_job_queue::spawn_video_processor_worker(
            db_pool.clone(),
            s3_client,
            Arc::new(config.s3.clone()),
            video_job_receiver,
        );
    tracing::info!("Video processor worker spawned");

    // Clone config for server closure
    let server_config = config.clone();
    let bind_address = format!("{}:{}", config.app.host, config.app.port);

    tracing::info!("Starting HTTP server at {}", bind_address);

    // Clone job_sender for graceful shutdown (will be dropped after server stops)
    let job_sender_shutdown = job_sender.clone();

    // Background: spawn stories cleanup worker (every 5 minutes)
    {
        let pool = db_pool.clone();
        tokio::spawn(async move {
            let svc = StoriesService::new(pool);
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(300));
            loop {
                interval.tick().await;
                if let Ok(affected) = svc.cleanup_expired().await {
                    if affected > 0 {
                        tracing::info!("stories cleanup marked deleted: {}", affected);
                    }
                }
            }
        });
    }

    // Background: ensure Milvus collection (when enabled)
    {
        let milvus_enabled =
            std::env::var("MILVUS_ENABLED").unwrap_or_else(|_| "false".into()) == "true";
        if milvus_enabled {
            tokio::spawn(async move {
                let cfg = video_config::VideoConfig::from_env().inference;
                let dl = DeepLearningInferenceService::new(cfg);
                if let Err(e) = dl.check_milvus_health().await {
                    tracing::warn!("Milvus health check error: {}", e);
                }
                if let Ok(true) = dl.check_milvus_health().await {
                    if let Ok(true) = dl.ensure_milvus_collection().await {
                        tracing::info!("Milvus collection ensured at startup");
                    } else {
                        tracing::warn!("Milvus collection ensure failed");
                    }
                } else {
                    tracing::warn!("Milvus not healthy at startup; using PG fallback");
                }
            });
        }
    }

    // ========================================
    // Background jobs: Suggested Users (fallback cache)
    // ========================================
    let jobs_handle = {
        let (shutdown_tx, _) = tokio::sync::broadcast::channel::<()>(1);

        // Build JobContext
        let ch_client_for_jobs = clickhouse::Client::default()
            .with_url(&config.clickhouse.url)
            .with_user(&config.clickhouse.username)
            .with_password(&config.clickhouse.password)
            .with_database(&config.clickhouse.database);

        let job_ctx = jobs::JobContext::new(redis_manager.clone(), ch_client_for_jobs.clone());
        let job_ctx2 = jobs::JobContext::new(redis_manager.clone(), ch_client_for_jobs.clone());
        let job_ctx3 = jobs::JobContext::new(redis_manager.clone(), ch_client_for_jobs);

        let suggested_job = SuggestedUsersJob::new(SuggestionConfig::default());
        let trending_hourly = jobs::trending_generator::TrendingGeneratorJob::new(
            jobs::trending_generator::TrendingConfig::hourly(),
        );
        let cache_warmer = jobs::cache_warmer::CacheWarmerJob::new(
            jobs::cache_warmer::CacheWarmerConfig::default(),
            content_client.clone(),
        );

        // Run jobs in background (suggested + trending + cache warmup)
        let handle = tokio::spawn(async move {
            run_jobs(
                vec![
                    (
                        Arc::new(suggested_job) as Arc<dyn jobs::CacheRefreshJob>,
                        job_ctx,
                    ),
                    (
                        Arc::new(trending_hourly) as Arc<dyn jobs::CacheRefreshJob>,
                        job_ctx2,
                    ),
                    (
                        Arc::new(cache_warmer) as Arc<dyn jobs::CacheRefreshJob>,
                        job_ctx3,
                    ),
                ],
                2,
                shutdown_tx,
            )
            .await;
        });
        handle
    };

    // Create and run HTTP server
    let server = HttpServer::new(move || {
        let feed_state = feed_state.clone();
        let content_client_data = content_client_data.clone();
        let health_checker_data = health_checker_data.clone();
        let health_state = health_state.clone();
        let events_state = events_state.clone();
        let stream_state = stream_state.clone();
        let stream_chat_ws_state = stream_chat_ws_state.clone();
        let graph_data = graph_data.clone();
        let global_rate_limit = global_rate_limit.clone();
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
            .app_data(web::Data::new(event_producer.clone()))
            .app_data(web::Data::new(db_pool.clone()))
            .app_data(web::Data::new(redis_manager.clone()))
            .app_data(web::Data::new(server_config.clone()))
            .app_data(web::Data::new(job_sender.clone()))
            .app_data(web::Data::new(video_job_sender.clone()))
            .app_data(web::Data::new(VideoService::new(
                video_config::VideoConfig::from_env(),
            )))
            .app_data(web::Data::new(DeepLearningInferenceService::new(
                video_config::VideoConfig::from_env().inference,
            )))
            .app_data(feed_state.clone())
            .app_data(content_client_data.clone())
            .app_data(health_state.clone())
            .app_data(health_checker_data.clone())
            .app_data(events_state.clone())
            .app_data(stream_state.clone())
            .app_data(stream_chat_ws_state.clone())
            .app_data(graph_data.clone())
            // posts_state, videos_state, likes_state, comments_state REMOVED - moved to content/media services
            .app_data(relationships_state.clone())
            .app_data(web::Data::new(jwks_cache.clone()))
            // Circuit breakers for critical service protection
            .app_data(web::Data::new(clickhouse_circuit_breaker.clone()))
            .app_data(web::Data::new(kafka_circuit_breaker.clone()))
            .app_data(web::Data::new(redis_circuit_breaker.clone()))
            .wrap(cors)
            .wrap(Logger::default())
            .wrap(tracing_actix_web::TracingLogger::default())
            .wrap(MetricsMiddleware) // Add metrics middleware
            .wrap(global_rate_limit) // Add global rate limiting middleware
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
            // OpenAPI JSON endpoint
            .route(
                "/api/v1/openapi.json",
                web::get().to(|| async {
                    use utoipa::OpenApi;
                    HttpResponse::Ok()
                        .content_type("application/json")
                        .json(user_service::openapi::ApiDoc::openapi())
                }),
            )
            // Swagger UI (CDN-hosted)
            .route(
                "/swagger-ui",
                web::get().to(|| async {
                    HttpResponse::Ok()
                        .content_type("text/html; charset=utf-8")
                        .body(
                            r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Nova User Service API</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
    <script>
        window.onload = function() {
            SwaggerUIBundle({
                url: "/api/v1/openapi.json",
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIStandalonePreset
                ],
                plugins: [
                    SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "StandaloneLayout"
            });
        };
    </script>
</body>
</html>"#,
                        )
                }),
            )
            // Documentation entry point
            .route(
                "/docs",
                web::get().to(|| async {
                    HttpResponse::Ok()
                        .content_type("text/html; charset=utf-8")
                        .body(
                            r#"<!DOCTYPE html>
<html>
<head>
    <title>Nova API Documentation</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        a { display: block; margin: 15px 0; padding: 15px; background: #007bff; color: white; text-decoration: none; border-radius: 4px; }
        a:hover { background: #0056b3; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Nova User Service API</h1>
        <p>Choose your preferred documentation viewer:</p>
        <a href="/swagger-ui">📘 Swagger UI (Interactive)</a>
        <a href="/api/v1/openapi.json">📄 OpenAPI JSON (Raw)</a>
    </div>
</body>
</html>"#,
                        )
                }),
            )
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
                            .service(handlers::invalidate_feed_cache),
                    )
                    .service(
                        web::scope("/events")
                            .app_data(events_state.clone())
                            .service(handlers::ingest_events),
                    )
                    .service(
                        web::scope("/streams")
                            .app_data(stream_state.clone())
                            .route("", web::get().to(handlers::list_live_streams))
                            .route("/search", web::get().to(handlers::search_streams))
                            .route("/{id}", web::get().to(handlers::get_stream_details))
                            .route(
                                "/{id}/comments",
                                web::get().to(handlers::get_stream_comments),
                            )
                            .route("/rtmp/auth", web::post().to(handlers::rtmp_authenticate))
                            .route("/rtmp/done", web::post().to(handlers::rtmp_done))
                            .service(
                                web::scope("")
                                    .wrap(JwtAuthMiddleware)
                                    .route("", web::post().to(handlers::create_stream))
                                    .route("/{id}/join", web::post().to(handlers::join_stream))
                                    .route("/{id}/leave", web::post().to(handlers::leave_stream))
                                    .route(
                                        "/{id}/comments",
                                        web::post().to(handlers::post_stream_comment),
                                    )
                                    .route(
                                        "/{id}/analytics",
                                        web::get().to(handlers::get_stream_analytics),
                                    ),
                            ),
                    )
                    // Note: Messaging endpoints moved to messaging-service (port 8085)
                    // Use messaging-service API for conversations and messages
                    // Stories and close-friends endpoints REMOVED - moved to content-service (port 8081)
                    // Videos, reels, uploads endpoints REMOVED - moved to media-service (port 8082)
                    // Admin endpoints (protected)
                    // Admin endpoints - milvus init moved to media-service
                    // Auth endpoints
                    .service(
                        web::scope("/auth")
                            .route("/dev-verify", web::post().to(handlers::dev_verify_email))
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
                    // Authenticated user endpoints under /users/me (must be defined BEFORE /users/{id})
                    .service(
                        web::scope("/users/me")
                            .wrap(JwtAuthMiddleware)
                            .route("", web::get().to(handlers::get_current_user))
                            .route("", web::patch().to(handlers::update_profile))
                            .route("/public-key", web::put().to(handlers::upsert_my_public_key))
                            // /bookmarks moved to content-service (port 8081)
                    )
                    // Users endpoints (place after /users/me to avoid route collision)
                    .service(
                        web::scope("/users")
                            .app_data(graph_data.clone())
                            // Public endpoints
                            .route("/{id}", web::get().to(handlers::get_user))
                            .route(
                                "/{id}/public-key",
                                web::get().to(handlers::get_user_public_key),
                            )
                            // Relationship endpoints (JWT required)
                            .service(
                                web::scope("")
                                    .wrap(JwtAuthMiddleware)
                                    .service(
                                        web::resource("/{id}/follow")
                                            .route(web::post().to(handlers::follow_user))
                                            .route(web::delete().to(handlers::unfollow_user)),
                                    )
                                    .service(
                                        web::resource("/{id}/block")
                                            .route(web::post().to(handlers::block_user))
                                            .route(web::delete().to(handlers::unblock_user)),
                                    ),
                            )
                            .route("/{id}/followers", web::get().to(handlers::get_followers))
                            .route("/{id}/following", web::get().to(handlers::get_following)),
                    )
                    // Posts and comments endpoints REMOVED - moved to content-service (port 8081)
                    // Discover endpoints
                    .service(
                        web::scope("")
                            .wrap(JwtAuthMiddleware)
                            .app_data(graph_data.clone())
                            .service(handlers::get_suggested_users),
                    )
                    // NOTE: Search endpoints moved to search-service:8086
                    // Use /api/v1/search/* routes via API Gateway (Nginx)
                    // Trending endpoints (public)
                    .service(handlers::get_trending)
                    .service(handlers::get_trending_videos)
                    .service(handlers::get_trending_posts)
                    .service(handlers::get_trending_streams)
                    .service(handlers::get_trending_categories)
                    .service(
                        web::scope("")
                            .wrap(JwtAuthMiddleware)
                            .service(handlers::record_engagement),
                    ),
            )
            // WebSocket endpoints (outside /api/v1)
            .service(
                web::scope("/ws/streams")
                    .wrap(JwtAuthMiddleware)
                    .app_data(stream_chat_ws_state.clone())
                    .route("/{id}/chat", web::get().to(handlers::stream_chat_ws)),
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

    // Abort CDC consumer (always running, mandatory for consistency)
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

    // Stop jobs
    jobs_handle.abort();
    match tokio::time::timeout(std::time::Duration::from_secs(5), jobs_handle).await {
        Ok(Ok(())) => {
            tracing::info!("Background jobs shut down gracefully");
        }
        Ok(Err(_)) => {
            tracing::info!("Background jobs aborted");
        }
        Err(_) => {
            tracing::warn!("Background jobs did not shut down within timeout");
        }
    }

    tracing::info!("All workers, consumers, and jobs stopped. Server shutdown complete.");

    result
}
