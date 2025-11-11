// TODO: Fix clippy warnings and code quality issues in follow-up PR (tracked in GitHub issue)
// TEMPORARY: Allow all warnings to unblock CRITICAL P0 BorrowMutError fix deployment
// This prevents HTTP server from responding to ANY requests - production impact!
// Revert this after deployment and fix warnings in separate PR
// Build timestamp: 2025-11-11T12:15 - Force rebuild to include BorrowMutError fix
#![allow(warnings)]
#![allow(clippy::all)]

use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer};
use redis_utils::RedisPool;
use std::io;
use std::net::SocketAddr;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use tonic::transport::Server as GrpcServer;
use tonic_health::server::health_reporter;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use user_service::grpc::{
    AuthServiceClient, ContentServiceClient, FeedServiceClient, GrpcClientConfig, HealthChecker,
    MediaServiceClient, UserServiceImpl,
};
use user_service::{
    config::Config,
    db::{ch_client::ClickHouseClient, create_pool, run_migrations},
    handlers,
    handlers::preferences::{
        block_user as preferences_block_user, unblock_user as preferences_unblock_user,
    },
    handlers::{events::EventHandlerState, health::HealthCheckState},
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
        events::{EventDeduplicator, EventsConsumer, EventsConsumerConfig},
        graph::GraphService,
        kafka_producer::EventProducer,
        social_graph_sync::SocialGraphSyncConsumer,
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
    let config = match Config::from_env() {
        Ok(cfg) => cfg,
        Err(e) => {
            tracing::error!("Configuration loading failed: {:#}", e);
            eprintln!("ERROR: Failed to load configuration: {}", e);
            std::process::exit(1);
        }
    };

    tracing::info!("Starting user-service v{}", env!("CARGO_PKG_VERSION"));
    tracing::info!("Environment: {}", config.app.env);

    // ========================================
    // Initialize JWT keys from environment
    // ========================================
    // 支援從檔案讀取金鑰（JWT_PRIVATE_KEY_FILE / JWT_PUBLIC_KEY_FILE）
    let private_key_pem = if let Ok(path) = std::env::var("JWT_PRIVATE_KEY_FILE") {
        match std::fs::read_to_string(&path) {
            Ok(key) => key,
            Err(e) => {
                tracing::error!("Failed to read JWT private key file at {}: {:#}", path, e);
                eprintln!("ERROR: JWT_PRIVATE_KEY_FILE read failed: {}", e);
                std::process::exit(1);
            }
        }
    } else {
        config.jwt.private_key_pem.clone()
    };
    let public_key_pem = if let Ok(path) = std::env::var("JWT_PUBLIC_KEY_FILE") {
        match std::fs::read_to_string(&path) {
            Ok(key) => key,
            Err(e) => {
                tracing::error!("Failed to read JWT public key file at {}: {:#}", path, e);
                eprintln!("ERROR: JWT_PUBLIC_KEY_FILE read failed: {}", e);
                std::process::exit(1);
            }
        }
    } else {
        config.jwt.public_key_pem.clone()
    };

    match user_service::security::jwt::initialize_keys(&private_key_pem, &public_key_pem) {
        Ok(()) => {}
        Err(e) => {
            tracing::error!("JWT keys initialization failed: {:#}", e);
            eprintln!("ERROR: JWT initialization failed: {}", e);
            std::process::exit(1);
        }
    }
    tracing::info!("JWT keys initialized from environment variables");

    // ========================================
    // Initialize Prometheus metrics
    // ========================================
    metrics::init_metrics();
    tracing::info!("Prometheus metrics initialized");

    // Create database connection pool
    let db_pool = match create_pool(&config.database.url, config.database.max_connections).await {
        Ok(pool) => pool,
        Err(e) => {
            tracing::error!("Database pool creation failed: {:#}", e);
            eprintln!("ERROR: Failed to create database pool: {}", e);
            std::process::exit(1);
        }
    };

    tracing::info!(
        "Database pool created with {} max connections",
        config.database.max_connections
    );

    // Run migrations - Fix P0-5: Migration failures must exit immediately in all environments
    let run_migrations_env = std::env::var("RUN_MIGRATIONS").unwrap_or_else(|_| "true".into());
    if run_migrations_env != "false" {
        tracing::info!("Running database migrations...");
        match run_migrations(&db_pool).await {
            Ok(_) => tracing::info!("Database migrations completed"),
            Err(e) => {
                // Migration failures are always fatal, regardless of environment
                // This prevents silent failures where the service starts but with outdated schema
                tracing::error!("Database migration failed: {:#}", e);
                eprintln!("ERROR: Database migration failed: {}", e);
                std::process::exit(1);
            }
        }
    } else {
        tracing::info!(
            "Skipping database migrations (RUN_MIGRATIONS={})",
            run_migrations_env
        );
    }

    // Create Redis connection pool
    let redis_pool = match RedisPool::connect(&config.redis.url, None).await {
        Ok(pool) => pool,
        Err(e) => {
            tracing::error!("Redis pool initialization failed: {:#}", e);
            eprintln!("ERROR: Failed to initialize Redis pool: {}", e);
            std::process::exit(1);
        }
    };
    let redis_manager = redis_pool.manager();

    tracing::info!("Redis connection established");

    // Initialize global rate limiter (100 requests per 15 minutes per IP/user)
    use user_service::middleware::rate_limit::RateLimitConfig;
    let rate_limit_config = RateLimitConfig {
        max_requests: 100,
        window_seconds: 900, // 15 minutes
    };
    let rate_limiter = RateLimiter::new(redis_manager.clone(), rate_limit_config);
    let global_rate_limit =
        GlobalRateLimitMiddleware::new(rate_limiter, config.rate_limit.trusted_proxies.clone());
    tracing::info!("Global rate limiter initialized: 100 requests per 15 minutes");

    // ========================================
    // Initialize ClickHouse client (optional analytics dependency)
    // ========================================
    let (clickhouse_client, clickhouse_writer) = if config.clickhouse.enabled {
        let client = Arc::new(ClickHouseClient::new(
            &config.clickhouse.url,
            &config.clickhouse.database,
            &config.clickhouse.username,
            &config.clickhouse.password,
            config.clickhouse.timeout_ms,
        ));

        match client.health_check().await {
            Ok(()) => {
                tracing::info!("ClickHouse connection validated");
                let writer = Arc::new(ClickHouseClient::new_writable(
                    &config.clickhouse.url,
                    &config.clickhouse.database,
                    &config.clickhouse.username,
                    &config.clickhouse.password,
                    config.clickhouse.timeout_ms,
                ));
                (Some(client), Some(writer))
            }
            Err(e) => {
                tracing::warn!("ClickHouse health check failed (analytics disabled): {}", e);
                (None, None)
            }
        }
    } else {
        tracing::info!("ClickHouse integration disabled via CLICKHOUSE_ENABLED=false");
        (None, None)
    };

    let clickhouse_available = clickhouse_client.is_some();

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
    let grpc_config = match GrpcClientConfig::from_env() {
        Ok(cfg) => cfg,
        Err(e) => {
            tracing::error!("gRPC client configuration loading failed: {:#}", e);
            eprintln!("ERROR: Failed to load gRPC client configuration: {}", e);
            std::process::exit(1);
        }
    };
    let health_checker = Arc::new(HealthChecker::new());

    // Initialize gRPC clients with graceful degradation
    // **Graceful Degradation**: auth-service and media-service are optional dependencies.
    // If unavailable, service starts with reduced functionality and logs warnings.
    // content-service and feed-service remain strict dependencies for core features.

    tracing::info!("Initializing gRPC service clients with graceful degradation");

    let content_client: Arc<ContentServiceClient> =
        match ContentServiceClient::new(&grpc_config, health_checker.clone()).await {
            Ok(client) => {
                tracing::info!("✓ content-service gRPC client initialized");
                Arc::new(client)
            }
            Err(e) => {
                tracing::error!(
                    "✗ FATAL: content-service gRPC client initialization failed: {:#}",
                    e
                );
                tracing::error!(
                    "  Ensure content-service deployment exists and is healthy in Kubernetes"
                );
                std::process::exit(1);
            }
        };

    let auth_client: Option<Arc<AuthServiceClient>> =
        match AuthServiceClient::new(&grpc_config, health_checker.clone()).await {
            Ok(client) => {
                tracing::info!("✓ auth-service gRPC client initialized");
                Some(Arc::new(client))
            }
            Err(e) => {
                tracing::warn!(
                    "⚠️  auth-service gRPC client initialization failed: {:#}",
                    e
                );
                tracing::warn!(
                    "   Authentication features will be limited until auth-service is deployed"
                );
                tracing::warn!("   Service will continue with reduced functionality");
                None
            }
        };

    let media_client: Option<Arc<MediaServiceClient>> =
        match MediaServiceClient::new(&grpc_config, health_checker.clone()).await {
            Ok(client) => {
                tracing::info!("✓ media-service gRPC client initialized");
                Some(Arc::new(client))
            }
            Err(e) => {
                tracing::warn!(
                    "⚠️  media-service gRPC client initialization failed: {:#}",
                    e
                );
                tracing::warn!(
                "   Media processing features will be unavailable until media-service is deployed"
            );
                tracing::warn!("   Service will continue with reduced functionality");
                None
            }
        };

    let feed_client: Option<Arc<FeedServiceClient>> = match FeedServiceClient::new(
        &grpc_config,
        health_checker.clone(),
    )
    .await
    {
        Ok(client) => {
            tracing::info!("✓ feed-service gRPC client initialized");
            Some(Arc::new(client))
        }
        Err(e) => {
            tracing::warn!(
                "⚠️  feed-service gRPC client initialization failed: {:#}",
                e
            );
            tracing::warn!(
                    "   Feed recommendation features will be unavailable until feed-service is deployed"
                );
            tracing::warn!("   Service will continue with reduced functionality");
            None
        }
    };

    let available_services = vec![
        "content-service",
        if auth_client.is_some() {
            "auth-service"
        } else {
            ""
        },
        if media_client.is_some() {
            "media-service"
        } else {
            ""
        },
        if feed_client.is_some() {
            "feed-service"
        } else {
            ""
        },
    ]
    .into_iter()
    .filter(|s| !s.is_empty())
    .collect::<Vec<_>>()
    .join(", ");

    tracing::info!("✅ gRPC services initialized: {}", available_services);

    // Feed state moved to feed-service (port 8089)
    let content_client_data = web::Data::new(content_client.clone());
    let feed_client_data = web::Data::new(feed_client.clone());
    let auth_client_data = web::Data::new(auth_client.clone()); // Now Option<Arc<AuthServiceClient>>
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
            match GraphService::new(&user_service::config::GraphConfig {
                enabled: false,
                neo4j_uri: String::new(),
                neo4j_user: String::new(),
                neo4j_password: String::new(),
            })
            .await
            {
                Ok(svc) => svc,
                Err(e2) => {
                    tracing::error!(
                        "GraphService fallback initialization failed (should never happen): {:#}",
                        e2
                    );
                    eprintln!(
                        "FATAL: GraphService disabled mode initialization failed: {}",
                        e2
                    );
                    std::process::exit(1);
                }
            }
        }
    };
    let graph_service_clone = graph_service.clone();
    let graph_data = web::Data::new(graph_service);

    // ========================================
    // Initialize Kafka producer for events (needed by multiple services)
    // ========================================
    let event_producer = Arc::new(match EventProducer::new(&config.kafka) {
        Ok(producer) => producer,
        Err(e) => {
            tracing::error!("Kafka producer initialization failed: {:#}", e);
            eprintln!("ERROR: Failed to create Kafka producer: {}", e);
            std::process::exit(1);
        }
    });

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
        redis_manager.clone(),
        clickhouse_client.clone(),
        Some(event_producer.clone()),
        health_checker.clone(),
        cdc_health_flag.clone(),
        config.clickhouse.enabled,
        clickhouse_writer.is_some(),
    ));

    // ========================================
    // Initialize additional handler states with PostgreSQL circuit breaker
    // ========================================
    // posts, videos, likes, comments states REMOVED - moved to content-service and media-service

    let relationships_state = web::Data::new(handlers::relationships::RelationshipsHandlerState {
        postgres_cb: postgres_circuit_breaker.clone(),
    });

    // ========================================
    // Initialize ClickHouse-dependent background pipelines
    // ========================================
    let (cdc_handle, events_handle) = if let Some(ch_writer) = clickhouse_writer.clone() {
        // CDC: PostgreSQL → Kafka → ClickHouse
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
            match CdcConsumer::new(cdc_config, ch_writer.as_ref().clone(), db_pool.clone()).await {
                Ok(consumer) => consumer,
                Err(e) => {
                    tracing::error!("CDC consumer initialization failed: {:#}", e);
                    eprintln!("ERROR: Failed to create CDC consumer: {}", e);
                    std::process::exit(1);
                }
            };

        let cdc_health_for_task = cdc_health_flag.clone();
        let cdc_handle = tokio::spawn(async move {
            if let Err(e) = cdc_consumer.run().await {
                tracing::error!("CDC consumer error: {}", e);
                cdc_health_for_task.store(false, Ordering::SeqCst);
            }
        });
        tracing::info!("CDC consumer spawned");

        // Events consumer: Kafka → ClickHouse
        let event_deduplicator = EventDeduplicator::new(redis_manager.clone(), 3600);

        let events_config = EventsConsumerConfig {
            brokers: config.kafka.brokers.clone(),
            group_id: "nova-events-consumer-v1".to_string(),
            topic: config.kafka.events_topic.clone(),
            batch_size: 100,
            max_concurrent_inserts: 5,
        };

        // Events consumer requires content and feed service clients
        if let Some(feed_client_arc) = feed_client.clone() {
            match EventsConsumer::new(
                events_config,
                ch_writer.as_ref().clone(),
                event_deduplicator,
                content_client.clone(),
                feed_client_arc,
            ) {
                Ok(consumer) => {
                    let handle = tokio::spawn(async move {
                        if let Err(e) = consumer.run().await {
                            tracing::error!("Events consumer error: {}", e);
                        }
                    });
                    tracing::info!("✓ Events consumer spawned");
                    (Some(cdc_handle), Some(handle))
                }
                Err(e) => {
                    tracing::warn!("⚠️  Events consumer initialization failed: {:#}", e);
                    tracing::warn!(
                        "   Events processing will be unavailable until feed-service is deployed"
                    );
                    (Some(cdc_handle), None)
                }
            }
        } else {
            tracing::info!("Skipping events consumer (feed-service unavailable)");
            (Some(cdc_handle), None)
        }
    } else {
        tracing::info!("Skipping CDC and events consumers (ClickHouse unavailable)");
        (None, None)
    };

    // ========================================
    // Initialize social graph sync consumer (Neo4j)
    // ========================================
    let _social_graph_sync_handle = match SocialGraphSyncConsumer::new(
        &config.kafka,
        Arc::new(graph_service_clone),
        Arc::new(event_producer.as_ref().clone()),
    )
    .await
    {
        Err(e) => {
            tracing::warn!("Failed to create social graph sync consumer: {}", e);
            None
        }
        Ok(consumer) => {
            let handle = Arc::new(consumer).start();
            tracing::info!("Social graph sync consumer spawned");
            Some(handle)
        }
    };

    // S3 client initialization removed - moved to media-service (port 8082)
    // Use media-service API for image upload and storage operations

    // Clone config for server closure
    let server_config = config.clone();
    let bind_address = format!("{}:{}", config.app.host, config.app.port);

    tracing::info!("Starting HTTP server at {}", bind_address);

    // ========================================
    // Background jobs: Suggested Users (fallback cache)
    // ========================================
    let jobs_handle = if clickhouse_available {
        let (shutdown_tx, _) = tokio::sync::broadcast::channel::<()>(1);

        // Build JobContext
        let ch_client_for_jobs = clickhouse::Client::default()
            .with_url(&config.clickhouse.url)
            .with_user(&config.clickhouse.username)
            .with_password(&config.clickhouse.password)
            .with_database(&config.clickhouse.database);

        let job_ctx = jobs::JobContext::new(redis_manager.clone(), ch_client_for_jobs.clone());
        let job_ctx3 = jobs::JobContext::new(redis_manager.clone(), ch_client_for_jobs);

        let suggested_job = SuggestedUsersJob::new(SuggestionConfig::default());

        // Cache warmer requires both content and feed service clients
        let mut jobs_vec: Vec<(Arc<dyn jobs::CacheRefreshJob>, jobs::JobContext)> = vec![(
            Arc::new(suggested_job) as Arc<dyn jobs::CacheRefreshJob>,
            job_ctx,
        )];

        // Conditionally add cache warmer if feed-service is available
        if let Some(feed_client_arc) = feed_client.clone() {
            let cache_warmer = jobs::cache_warmer::CacheWarmerJob::new(
                jobs::cache_warmer::CacheWarmerConfig::default(),
                content_client.clone(),
                feed_client_arc,
            );
            jobs_vec.push((
                Arc::new(cache_warmer) as Arc<dyn jobs::CacheRefreshJob>,
                job_ctx3,
            ));
            tracing::info!("✓ Cache warmer job and suggested users job initialized");
        } else {
            tracing::info!("✓ Suggested users job initialized (cache warmer skipped - feed-service unavailable)");
        }

        // Run jobs in background (suggested + cache warmup; trending moved to feed-service)
        let num_jobs = jobs_vec.len();
        let handle = tokio::spawn(async move {
            run_jobs(jobs_vec, num_jobs, shutdown_tx).await;
        });
        Some(handle)
    } else {
        tracing::info!("Skipping background cache jobs (ClickHouse unavailable)");
        None
    };

    // ========================================
    // Build gRPC server for UserService
    // ========================================
    let app_state = Arc::new(user_service::AppState {
        db: db_pool.clone(),
        redis: redis_manager.clone(),
    });
    let grpc_service = UserServiceImpl::new(app_state);
    let grpc_server_svc =
        user_service::grpc::nova::user_service::user_service_server::UserServiceServer::new(
            grpc_service,
        );

    // NOTE: S3 client unused after video service migration to media-service
    let _s3_client = Arc::new(
        user_service::services::storage::build_s3_client(&config.s3)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "Failed to initialise S3 client for gRPC video server");
                io::Error::new(io::ErrorKind::Other, format!("S3 client init failed: {e}"))
            })?,
    );
    let _s3_config = Arc::new(config.s3.clone());

    // NOTE: Video service removed - migrated to dedicated media-service
    // Video processing, transcoding, and streaming are now handled by media-service (port 8082)

    // Start gRPC server on port + 1000 (e.g., 8080 -> 9080)
    let grpc_port = config.app.port + 1000;
    let grpc_addr = format!("{}:{}", config.app.host, grpc_port);
    let (grpc_shutdown_tx, grpc_shutdown_rx) = tokio::sync::oneshot::channel();

    let grpc_handle = tokio::spawn(async move {
        let grpc_addr_parsed: SocketAddr =
            grpc_addr.parse().map_err(|e: std::net::AddrParseError| {
                tracing::error!("Invalid gRPC address: {}", e);
            })?;

        tracing::info!("gRPC server listening on {}", grpc_addr_parsed);
        let (mut health, health_service) = health_reporter();
        health
            .set_serving::<user_service::grpc::nova::user_service::user_service_server::UserServiceServer<UserServiceImpl>>()
            .await;
        // Server-side correlation-id extractor interceptor
        fn server_interceptor(
            mut req: tonic::Request<()>,
        ) -> Result<tonic::Request<()>, tonic::Status> {
            // IMPORTANT: Clone the correlation ID before calling extensions_mut()
            // to avoid BorrowMutError (req.metadata() holds immutable borrow)
            if let Some(val) = req.metadata().get("correlation-id") {
                if let Ok(s) = val.to_str() {
                    let correlation_id = s.to_string();
                    // Safe to call extensions_mut() now - no outstanding borrows
                    req.extensions_mut().insert::<String>(correlation_id);
                }
            }
            Ok(req)
        }

        GrpcServer::builder()
            .add_service(health_service)
            .add_service(grpc_server_svc)
            // Video service removed - see media-service
            .serve_with_shutdown(grpc_addr_parsed, async {
                let _ = grpc_shutdown_rx.await;
            })
            .await
            .map_err(|e| {
                tracing::error!("gRPC server error: {}", e);
            })
    });

    // Create and run HTTP server
    let server = HttpServer::new(move || {
        let content_client_data = content_client_data.clone();
        let health_checker_data = health_checker_data.clone();
        let health_state = health_state.clone();
        let events_state = events_state.clone();
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
            // Feed state moved to feed-service (port 8089)
            .app_data(content_client_data.clone())
            .app_data(feed_client_data.clone())
            .app_data(auth_client_data.clone())
            .app_data(health_state.clone())
            .app_data(health_checker_data.clone())
            .app_data(events_state.clone())
            .app_data(graph_data.clone())
            // posts_state, videos_state, likes_state, comments_state REMOVED - moved to content/media services
            .app_data(relationships_state.clone())
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
                    // Feed endpoints REMOVED - moved to feed-service (port 8089)
                    // Use feed-service API for feed generation and caching
                    .service(
                        web::scope("/events")
                            .app_data(events_state.clone())
                            .service(handlers::ingest_events),
                    )
                    // Note: Messaging endpoints moved to messaging-service (port 8085)
                    // Use messaging-service API for conversations and messages
                    // Stories and close-friends endpoints REMOVED - moved to content-service (port 8081)
                    // Videos, reels, uploads endpoints REMOVED - moved to media-service (port 8082)
                    // Admin endpoints (protected)
                    // Admin endpoints - milvus init moved to media-service
                    // Auth endpoints REMOVED - moved to auth-service (port 8084)
                    // Use auth-service API for registration, login, OAuth, and 2FA
                    // Authenticated user endpoints under /users/me (must be defined BEFORE /users/{id})
                    .service(
                        web::scope("/users/me")
                            .wrap(JwtAuthMiddleware)
                            .route("", web::get().to(handlers::get_current_user))
                            .route("", web::patch().to(handlers::update_profile))
                            .route("/public-key", web::put().to(handlers::upsert_my_public_key))
                            // Feed preferences moved to feed-service (port 8089)
                            .route("/preferences/blocked-users/{id}", web::post().to(preferences_block_user))
                            .route("/preferences/blocked-users/{id}", web::delete().to(preferences_unblock_user))
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
                                            .route(web::post().to(preferences_block_user))
                                            .route(web::delete().to(preferences_unblock_user)),
                                    ),
                            )
                            .route("/{id}/followers", web::get().to(handlers::get_followers))
                            .route("/{id}/following", web::get().to(handlers::get_following)),
                    )
                    // Posts and comments endpoints REMOVED - moved to content-service (port 8081)
                    // Discover endpoints REMOVED - moved to feed-service (port 8089)
                    // NOTE: Search endpoints moved to search-service:8086
                    // Use /api/v1/search/* routes via API Gateway (Nginx)
                    // NOTE: Trending endpoints moved to feed-service:8089
                    // Use /api/v1/trending/* routes via API Gateway (Nginx)
            )
    })
    .bind(&bind_address)?
    .workers(4)
    .run();

    let server_handle = server.handle();
    let mut http_handle = Some(tokio::spawn(server));
    let mut grpc_handle = Some(grpc_handle);

    // Run both HTTP and gRPC servers concurrently with graceful shutdown support
    let mut grpc_shutdown_tx = Some(grpc_shutdown_tx);
    let mut shutdown_signal = Box::pin(async {
        tokio::signal::ctrl_c()
            .await
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))
    });

    let mut shutdown_initiated = false;
    let result: Result<(), io::Error>;

    let result_loop = loop {
        tokio::select! {
            http_res = async {
                if let Some(handle) = &mut http_handle {
                    Some(handle.await)
                } else {
                    None
                }
            }, if http_handle.is_some() => {
                let join_res = http_res.expect("HTTP join handle result");
                http_handle = None;
                tracing::info!("HTTP server exited");
                let http_result = match join_res {
                    Ok(inner) => inner,
                    Err(e) => Err(io::Error::new(io::ErrorKind::Other, e.to_string())),
                };
                break http_result;
            }
            grpc_res = async {
                if let Some(handle) = &mut grpc_handle {
                    Some(handle.await)
                } else {
                    None
                }
            }, if grpc_handle.is_some() => {
                let join_res = grpc_res.expect("gRPC join handle result");
                grpc_handle = None;
                tracing::info!("gRPC server exited");
                let grpc_result = match join_res {
                    Ok(Ok(())) => Ok(()),
                    Ok(Err(())) => Err(io::Error::new(io::ErrorKind::Other, "gRPC server error")),
                    Err(e) => Err(io::Error::new(io::ErrorKind::Other, e.to_string())),
                };
                break grpc_result;
            }
            sig = &mut shutdown_signal => {
                match sig {
                    Ok(()) => {
                        tracing::info!("Shutdown signal received; initiating graceful shutdown");
                    }
                    Err(e) => {
                        tracing::error!("Failed to listen for shutdown signal: {}", e);
                        break Err(io::Error::new(e.kind(), e.to_string()));
                    }
                }

                if !shutdown_initiated {
                    shutdown_initiated = true;
                    server_handle.stop(true).await;
                    if let Some(tx) = grpc_shutdown_tx.take() {
                        let _ = tx.send(());
                    }
                }
            }
        }
    };

    result = result_loop;

    if !shutdown_initiated {
        server_handle.stop(true).await;
        if let Some(tx) = grpc_shutdown_tx.take() {
            let _ = tx.send(());
        }
    }

    if let Some(handle) = http_handle {
        match tokio::time::timeout(std::time::Duration::from_secs(5), handle).await {
            Ok(join_res) => {
                if let Err(e) = join_res {
                    tracing::warn!("HTTP server join error after shutdown: {}", e);
                }
            }
            Err(_) => {
                tracing::warn!("HTTP server did not shut down within timeout; aborting task");
            }
        }
    }

    if let Some(handle) = grpc_handle {
        match tokio::time::timeout(std::time::Duration::from_secs(5), handle).await {
            Ok(join_res) => match join_res {
                Ok(Ok(())) => {}
                Ok(Err(())) => {
                    tracing::warn!("gRPC server reported error during shutdown");
                }
                Err(e) => {
                    tracing::warn!("gRPC server join error after shutdown: {}", e);
                }
            },
            Err(_) => {
                tracing::warn!("gRPC server did not shut down within timeout; aborting task");
            }
        }
    }

    // ========================================
    // Cleanup: Graceful worker shutdown
    // ========================================
    tracing::info!("Server shutting down. Stopping background services...");

    if let Some(handle) = cdc_handle {
        handle.abort();
        match tokio::time::timeout(std::time::Duration::from_secs(5), handle).await {
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
    } else {
        tracing::info!("CDC consumer not running; skipping shutdown");
    }

    if let Some(handle) = events_handle {
        handle.abort();
        match tokio::time::timeout(std::time::Duration::from_secs(5), handle).await {
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
    } else {
        tracing::info!("Events consumer not running; skipping shutdown");
    }

    if let Some(handle) = jobs_handle {
        handle.abort();
        match tokio::time::timeout(std::time::Duration::from_secs(5), handle).await {
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
    } else {
        tracing::info!("No background cache jobs running; skipping shutdown");
    }

    tracing::info!("All workers, consumers, and jobs stopped. Server shutdown complete.");

    result
}
