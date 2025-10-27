use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer};
use std::io;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use user_service::{
    cache::FeedCache,
    config::video_config,
    config::Config,
    db::{ch_client::ClickHouseClient, create_pool, run_migrations},
    handlers,
    handlers::{events::EventHandlerState, feed::FeedHandlerState, streams::StreamHandlerState},
    jobs::{
        self, run_jobs, suggested_users_generator::SuggestedUsersJob,
        suggested_users_generator::SuggestionConfig, JobContext,
    },
    metrics,
    middleware::{GlobalRateLimitMiddleware, JwtAuthMiddleware, MetricsMiddleware, RateLimiter},
    services::{
        cdc::{CdcConsumer, CdcConsumerConfig},
        deep_learning_inference::DeepLearningInferenceService,
        events::{EventDeduplicator, EventsConsumer, EventsConsumerConfig},
        feed_ranking::FeedRankingService,
        graph::GraphService,
        job_queue,
        kafka_producer::EventProducer,
        oauth::jwks_cache::JWKSCache,
        recommendation_v2::{HybridWeights, RecommendationConfig, RecommendationServiceV2},
        s3_service,
        stories::StoriesService,
        streaming::{
            RtmpWebhookHandler, StreamActor, StreamAnalyticsService, StreamChatHandlerState,
            StreamChatStore, StreamDiscoveryService, StreamRepository, StreamService, ViewerCounter,
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

    if let Err(e) = clickhouse_client.health_check().await {
        tracing::warn!("ClickHouse health check failed: {}", e);
    } else {
        tracing::info!("ClickHouse connection validated");
    }

    let feed_cache = FeedCache::new(redis_manager.clone(), 120);
    let feed_cache = Arc::new(Mutex::new(feed_cache));
    let feed_ranking = Arc::new(FeedRankingService::new(
        clickhouse_client.clone(),
        feed_cache.clone(),
    ));

    // Optional: init Recommendation V2 re-ranker (disabled by default)
    let rec_v2 = {
        let enabled =
            std::env::var("RECOMMENDATION_V2_INIT").unwrap_or_else(|_| "false".into()) == "true";
        if enabled {
            let onnx_path = std::env::var("REC_ONNX_MODEL_PATH")
                .unwrap_or_else(|_| "models/collaborative_v1.0.onnx".into());
            let cfg = RecommendationConfig {
                collaborative_model_path: std::env::var("REC_CF_MODEL").unwrap_or_default(),
                content_model_path: std::env::var("REC_CB_MODEL").unwrap_or_default(),
                onnx_model_path: onnx_path,
                hybrid_weights: HybridWeights::balanced(),
                enable_ab_testing: false,
            };
            match RecommendationServiceV2::new(cfg, db_pool.clone()).await {
                Ok(svc) => Some(Arc::new(svc)),
                Err(e) => {
                    tracing::warn!("Failed to initialize Recommendation V2: {}", e);
                    None
                }
            }
        } else {
            None
        }
    };

    let feed_state = web::Data::new(FeedHandlerState {
        feed_ranking: feed_ranking.clone(),
        rec_v2,
    });

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

    // ========================================
    // Initialize StreamActor (Phase 2: Actor pattern)
    // Replaces Arc<Mutex<StreamService>> with message-passing
    // ========================================
    let (stream_actor, stream_tx) = StreamActor::new(
        stream_repo.clone(),
        stream_viewer_counter.clone(),
        stream_chat_store,
        event_producer.clone(),
        rtmp_base_url.clone(),
        hls_cdn_url.clone(),
    );

    // Spawn the StreamActor in a background task to process commands
    let stream_actor_handle = tokio::spawn(async move {
        stream_actor.run().await;
    });
    tracing::info!("StreamActor spawned for processing commands");

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
        stream_tx: stream_tx.clone(),
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
    });

    // ========================================
    // Initialize CDC Consumer (PostgreSQL → Kafka → ClickHouse) if enabled
    // ========================================
    let ch_writable = Arc::new(ClickHouseClient::new_writable(
        &config.clickhouse.url,
        &config.clickhouse.database,
        &config.clickhouse.username,
        &config.clickhouse.password,
        config.clickhouse.timeout_ms,
    ));

    let enable_cdc = std::env::var("ENABLE_CDC").unwrap_or_else(|_| "false".into()) == "true";
    let mut cdc_handle_opt: Option<tokio::task::JoinHandle<()>> = None;
    if enable_cdc {
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

        let cdc_consumer =
            CdcConsumer::new(cdc_config, ch_writable.as_ref().clone(), db_pool.clone())
                .await
                .expect("Failed to create CDC consumer");

        let cdc_handle = tokio::spawn(async move {
            if let Err(e) = cdc_consumer.run().await {
                tracing::error!("CDC consumer error: {}", e);
            }
        });
        tracing::info!("CDC consumer spawned");
        cdc_handle_opt = Some(cdc_handle);
    } else {
        tracing::info!("CDC consumer disabled (ENABLE_CDC=false)");
    }

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
        redis_client.clone(),
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
            .app_data(events_state.clone())
            .app_data(stream_state.clone())
            .app_data(stream_chat_ws_state.clone())
            .app_data(graph_data.clone())
            .app_data(web::Data::new(jwks_cache.clone()))
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
                    .service(
                        web::scope("/stories")
                            .wrap(JwtAuthMiddleware)
                            .service(
                                web::resource("")
                                    .route(web::get().to(handlers::list_stories))
                                    .route(web::post().to(handlers::create_story)),
                            )
                            .route("/{id}", web::get().to(handlers::get_story))
                            .route("/{id}", web::delete().to(handlers::delete_story))
                            .route(
                                "/{id}/privacy",
                                web::patch().to(handlers::update_story_privacy),
                            )
                            .route(
                                "/user/{user_id}",
                                web::get().to(handlers::list_user_stories),
                            )
                            .route(
                                "/close-friends/{friend_id}",
                                web::post().to(handlers::add_close_friend),
                            )
                            .route(
                                "/close-friends/{friend_id}",
                                web::delete().to(handlers::remove_close_friend),
                            )
                            .route(
                                "/close-friends",
                                web::get().to(handlers::list_close_friends),
                            ),
                    )
                    .service(
                        web::scope("/videos")
                            .wrap(JwtAuthMiddleware)
                            .route("/upload/init", web::post().to(handlers::video_upload_init))
                            .route(
                                "/upload/complete",
                                web::post().to(handlers::video_upload_complete),
                            )
                            .route("", web::post().to(handlers::create_video))
                            .route("/{id}", web::get().to(handlers::get_video))
                            .route("/{id}", web::patch().to(handlers::update_video))
                            .route("/{id}", web::delete().to(handlers::delete_video))
                            .route("/{id}/stream", web::get().to(handlers::get_stream_manifest))
                            .route(
                                "/{id}/progress",
                                web::get().to(handlers::get_processing_progress),
                            )
                            .route(
                                "/{id}/processing/complete",
                                web::post().to(handlers::processing_complete),
                            )
                            .route(
                                "/{id}/embedding/rebuild",
                                web::post().to(handlers::rebuild_embedding),
                            )
                            .route("/{id}/similar", web::get().to(handlers::get_similar_videos))
                            .route("/{id}/like", web::post().to(handlers::like_video))
                            .route("/{id}/share", web::post().to(handlers::share_video)),
                    )
                    // Reels endpoints (short-form video functionality)
                    // Note: Reels handlers already have their actix-web decorators, so we register them as services
                    .service(handlers::reels::get_feed)
                    .service(handlers::reels::get_video_stream)
                    .service(handlers::reels::get_processing_status)
                    .service(handlers::reels::like_video)
                    .service(handlers::reels::watch_video)
                    .service(handlers::reels::share_video)
                    .service(handlers::reels::get_trending_sounds)
                    .service(handlers::reels::get_trending_hashtags)
                    .service(handlers::reels::get_similar_videos)
                    .service(handlers::reels::search_videos)
                    .service(handlers::reels::get_recommended_creators)
                    // Resumable uploads endpoints (chunked upload with resume support)
                    .service(
                        web::scope("/uploads")
                            .wrap(JwtAuthMiddleware)
                            .route("/init", web::post().to(handlers::upload_init))
                            .route(
                                "/{upload_id}/chunks/{chunk_index}",
                                web::put().to(handlers::upload_chunk),
                            )
                            .route(
                                "/{upload_id}/complete",
                                web::post().to(handlers::complete_upload),
                            )
                            .route("/{upload_id}", web::get().to(handlers::get_upload_status))
                            .route("/{upload_id}", web::delete().to(handlers::cancel_upload)),
                    )
                    // Admin endpoints (protected)
                    .service(web::scope("/admin").wrap(JwtAuthMiddleware).route(
                        "/milvus/init-collection",
                        web::post().to(handlers::init_milvus_collection),
                    ))
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
                            .route("/bookmarks", web::get().to(handlers::get_user_bookmarks)),
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
                    // Posts endpoints (protected with JWT authentication)
                    .service(
                        web::scope("/posts")
                            .wrap(JwtAuthMiddleware)
                            .route("", web::post().to(handlers::create_post_with_media))
                            .route(
                                "/upload/init",
                                web::post().to(handlers::upload_init_request),
                            )
                            .route(
                                "/upload/complete",
                                web::post().to(handlers::upload_complete_request),
                            )
                            .route("/{id}", web::get().to(handlers::get_post_request))
                            // Comments endpoints
                            .route(
                                "/{post_id}/comments",
                                web::post().to(handlers::create_comment),
                            )
                            .route("/{post_id}/comments", web::get().to(handlers::get_comments))
                            // Likes endpoints
                            .route("/{post_id}/like", web::post().to(handlers::like_post))
                            .route("/{post_id}/like", web::delete().to(handlers::unlike_post))
                            .route(
                                "/{post_id}/like/status",
                                web::get().to(handlers::check_like_status),
                            )
                            .route("/{post_id}/likes", web::get().to(handlers::get_post_likes))
                            // Bookmark endpoints
                            .route("/{id}/bookmark", web::post().to(handlers::bookmark_post))
                            .route("/{id}/bookmark", web::delete().to(handlers::unbookmark_post))
                            // Share endpoints
                            .route("/{id}/share", web::post().to(handlers::share_post)),
                    )
                    // Comment endpoints (direct access by comment ID)
                    .service(
                        web::scope("/comments")
                            .wrap(JwtAuthMiddleware)
                            .route("/{comment_id}", web::patch().to(handlers::update_comment))
                            .route("/{comment_id}", web::delete().to(handlers::delete_comment)),
                    )
                    // Discover endpoints
                    .service(
                        web::scope("/discover")
                            .wrap(JwtAuthMiddleware)
                            .app_data(graph_data.clone())
                            .route(
                                "/suggested-users",
                                web::get().to(handlers::get_suggested_users),
                            ),
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

    // Abort CDC consumer (long-running Kafka consumer loop) if running
    if let Some(cdc_handle) = cdc_handle_opt {
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
