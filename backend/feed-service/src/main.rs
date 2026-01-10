mod openapi;

use actix_web::{dev::Service, web, App, HttpServer};
use opentelemetry_config::{init_tracing, TracingConfig};
use std::io;
use std::sync::Arc;
use std::time::Instant;
use tonic::transport::Server as GrpcServer;
use tonic_health::server::health_reporter;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use utoipa_swagger_ui::SwaggerUi;

use recommendation_service::config::Config;
use recommendation_service::handlers::{
    get_feed, get_guest_feed, get_liked_feed, get_model_info, get_recommendations, get_saved_feed,
    rank_candidates, semantic_search, FeedHandlerState, RecommendationHandlerState,
};
use tracing::info;

use grpc_clients::{config::GrpcConfig, AuthClient, GrpcClientPool};
use recommendation_service::middleware::JwtAuthMiddleware;

async fn openapi_json(
    doc: web::Data<utoipa::openapi::OpenApi>,
) -> actix_web::Result<actix_web::HttpResponse> {
    let body = serde_json::to_string(&*doc).map_err(|e| {
        tracing::error!("OpenAPI serialization failed: {}", e);
        actix_web::error::ErrorInternalServerError("OpenAPI serialization error")
    })?;

    Ok(actix_web::HttpResponse::Ok()
        .content_type("application/json")
        .body(body))
}

// Kafka consumer removed - recommendation events now handled by ranking-service

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Initialize rustls crypto provider early (before any TLS operations)
    if let Err(err) = rustls::crypto::aws_lc_rs::default_provider().install_default() {
        eprintln!("ERROR: Failed to install rustls crypto provider: {:?}", err);
        std::process::exit(1);
    }

    // Initialize OpenTelemetry tracing (if enabled)
    let tracing_config = TracingConfig::from_env();
    if tracing_config.enabled {
        match init_tracing("feed-service", tracing_config) {
            Ok(_tracer) => {
                tracing::info!("OpenTelemetry distributed tracing initialized for feed-service");
            }
            Err(e) => {
                eprintln!("Failed to initialize OpenTelemetry tracing: {}", e);
                // Initialize fallback structured logging with JSON format
                tracing_subscriber::registry()
                    .with(
                        tracing_subscriber::EnvFilter::try_from_default_env()
                            .unwrap_or_else(|_| "info,actix_web=debug".into()),
                    )
                    .with(
                        tracing_subscriber::fmt::layer()
                            .json()
                            .with_current_span(true)
                            .with_span_list(true)
                            .with_thread_ids(true)
                            .with_thread_names(true)
                            .with_line_number(true)
                            .with_file(true)
                            .with_target(true),
                    )
                    .init();
            }
        }
    } else {
        // Initialize fallback structured logging without OpenTelemetry
        tracing_subscriber::registry()
            .with(
                tracing_subscriber::EnvFilter::try_from_default_env()
                    .unwrap_or_else(|_| "info,actix_web=debug".into()),
            )
            .with(
                tracing_subscriber::fmt::layer()
                    .json()
                    .with_current_span(true)
                    .with_span_list(true)
                    .with_thread_ids(true)
                    .with_thread_names(true)
                    .with_line_number(true)
                    .with_file(true)
                    .with_target(true),
            )
            .init();
    }

    // Load configuration
    let config = match Config::from_env() {
        Ok(cfg) => cfg,
        Err(e) => {
            tracing::error!("Configuration loading failed: {:#}", e);
            eprintln!("ERROR: Failed to load configuration: {}", e);
            std::process::exit(1);
        }
    };

    tracing::info!(
        "Starting recommendation-service v{}",
        env!("CARGO_PKG_VERSION")
    );
    tracing::info!("Environment: {}", config.app.env);

    // Initialize JWT keys from environment variables
    let jwt_public_key = match std::env::var("JWT_PUBLIC_KEY_PEM") {
        Ok(key) => key,
        Err(_) => {
            tracing::error!("JWT_PUBLIC_KEY_PEM environment variable not set");
            eprintln!("ERROR: JWT_PUBLIC_KEY_PEM must be set for JWT authentication");
            std::process::exit(1);
        }
    };

    let jwt_private_key = match std::env::var("JWT_PRIVATE_KEY_PEM") {
        Ok(key) => key,
        Err(_) => {
            tracing::error!("JWT_PRIVATE_KEY_PEM environment variable not set");
            eprintln!("ERROR: JWT_PRIVATE_KEY_PEM must be set for JWT authentication");
            std::process::exit(1);
        }
    };

    if let Err(e) =
        recommendation_service::security::jwt::initialize_keys(&jwt_private_key, &jwt_public_key)
    {
        tracing::error!("Failed to initialize JWT keys: {}", e);
        eprintln!("ERROR: Failed to initialize JWT keys: {}", e);
        std::process::exit(1);
    }
    tracing::info!("✅ JWT keys initialized successfully");

    // Initialize database (standardized pool)
    let mut db_cfg = db_pool::DbConfig::for_service("feed-service");
    if db_cfg.database_url.is_empty() {
        db_cfg.database_url = config.database.url.clone();
    }
    db_cfg.max_connections = std::cmp::max(db_cfg.max_connections, config.database.max_connections);
    let db_pool = match db_pool::create_pool(db_cfg).await {
        Ok(pool) => pool,
        Err(e) => {
            tracing::error!("Database pool creation failed: {:#}", e);
            eprintln!("ERROR: Failed to create database pool: {}", e);
            std::process::exit(1);
        }
    };

    let db_pool = web::Data::new(db_pool.clone());

    // Initialize gRPC client pool with connection pooling
    let grpc_config = match GrpcConfig::from_env() {
        Ok(cfg) => cfg,
        Err(e) => {
            tracing::error!("Failed to load gRPC config: {:#}", e);
            eprintln!("ERROR: Failed to load gRPC config: {}", e);
            std::process::exit(1);
        }
    };

    let grpc_pool = match GrpcClientPool::new(&grpc_config).await {
        Ok(pool) => {
            tracing::info!("gRPC client pool initialized successfully");
            Arc::new(pool)
        }
        Err(e) => {
            tracing::error!("Failed to create gRPC client pool: {:#}", e);
            eprintln!("ERROR: Failed to create gRPC client pool: {}", e);
            std::process::exit(1);
        }
    };

    // Initialize AuthService gRPC client from connection pool
    let auth_client = Arc::new(AuthClient::from_pool(grpc_pool.clone()));
    tracing::info!("AuthService gRPC client initialized from pool");

    // Initialize RankingServiceClient from gRPC pool
    let ranking_client = Arc::new(grpc_pool.ranking());
    tracing::info!("RankingService gRPC client initialized from pool");

    let rec_handler_state = web::Data::new(RecommendationHandlerState { ranking_client });

    // Initialize FeedHandlerState with gRPC clients
    let feed_handler_state = web::Data::new(FeedHandlerState {
        content_client: Arc::new(
            recommendation_service::grpc::clients::ContentServiceClient::from_pool(
                grpc_pool.clone(),
            ),
        ),
        graph_client: Arc::new(recommendation_service::grpc::clients::GraphServiceClient {
            pool: grpc_pool.clone(),
            enabled: true,
        }),
        grpc_pool: grpc_pool.clone(),
    });
    tracing::info!("FeedHandlerState initialized with content, graph, and social gRPC clients");

    // Kafka consumer removed - recommendation events now handled by ranking-service
    info!("Feed-service simplified - ranking delegated to ranking-service");

    // Phase 3: Spec 007 - Feed cleaner background job
    // Cleans up experiment data from soft-deleted users after 30-day retention period
    let cleaner_db = db_pool.get_ref().clone();
    let cleaner_auth = auth_client.clone();
    tokio::spawn(async move {
        recommendation_service::jobs::feed_cleaner::start_feed_cleaner(cleaner_db, cleaner_auth)
            .await;
    });
    info!("✅ Feed cleaner background job started");

    // Cache warmer background job - proactively warms caches for active users
    if config.redis.cache_warmer_enabled {
        match recommendation_service::FeedCache::new(
            &config.redis.url,
            recommendation_service::CacheConfig::default(),
        )
        .await
        {
            Ok(feed_cache) => {
                let warmer_db = db_pool.get_ref().clone();
                let warmer_cache = Arc::new(feed_cache);
                let warmer_grpc = grpc_pool.clone();
                let warmer_config =
                    recommendation_service::jobs::cache_warmer::CacheWarmerConfig::default();

                tokio::spawn(async move {
                    recommendation_service::jobs::cache_warmer::start_cache_warmer(
                        warmer_db,
                        warmer_cache,
                        warmer_grpc,
                        warmer_config,
                    )
                    .await;
                });
                info!("✅ Cache warmer background job started");
            }
            Err(e) => {
                tracing::warn!("Cache warmer disabled - failed to connect to Redis: {}", e);
            }
        }
    } else {
        info!("Cache warmer disabled by configuration");
    }

    // Start gRPC server for RecommendationService in addition to HTTP server
    let grpc_port: u16 = std::env::var("GRPC_PORT")
        .unwrap_or_else(|_| "9084".to_string())
        .parse()
        .expect("Invalid GRPC_PORT");
    let grpc_addr: std::net::SocketAddr = format!("0.0.0.0:{}", grpc_port)
        .parse()
        .expect("Invalid gRPC bind address");
    let grpc_db_pool = db_pool.get_ref().clone();

    // Create shared FeedCache for gRPC service (reuse existing if available)
    let grpc_cache = match recommendation_service::FeedCache::new(
        &config.redis.url,
        recommendation_service::CacheConfig::default(),
    )
    .await
    {
        Ok(cache) => Arc::new(cache),
        Err(e) => {
            tracing::error!("Failed to initialize FeedCache for gRPC service: {}", e);
            panic!("Failed to initialize FeedCache: {}", e);
        }
    };

    // Start Redis health check background job to prevent broken pipe errors
    let health_cache = Arc::clone(&grpc_cache);
    tokio::spawn(async move {
        recommendation_service::jobs::redis_health::start_redis_health_check(
            health_cache,
            recommendation_service::jobs::redis_health::RedisHealthConfig::default(),
        )
        .await;
    });
    info!("Redis health check background job started");

    // Initialize gRPC service with existing pools (avoid creating another GrpcClientPool)
    let grpc_svc = recommendation_service::grpc::RecommendationServiceImpl::with_cache(
        grpc_db_pool,
        grpc_cache,
        grpc_pool.clone(),
    );

    tokio::spawn(async move {
        let svc = grpc_svc;
        tracing::info!("gRPC server listening on {}", grpc_addr);

        // Server-side correlation-id extractor interceptor
        fn server_interceptor(
            mut req: tonic::Request<()>,
        ) -> Result<tonic::Request<()>, tonic::Status> {
            // Extract correlation-id from metadata if present
            let correlation_id = req
                .metadata()
                .get("correlation-id")
                .and_then(|val| val.to_str().ok())
                .map(|s| s.to_string());

            if let Some(id) = correlation_id {
                // Store in extensions for logging and tracing
                req.extensions_mut().insert::<String>(id);
            }
            Ok(req)
        }

        // Health service
        let (mut health, health_service) = health_reporter();
        health
            .set_serving::<recommendation_service::grpc::recommendation_service_server::RecommendationServiceServer<recommendation_service::grpc::RecommendationServiceImpl>>()
            .await;

        // ✅ P0: Load mTLS configuration
        let tls_config = match grpc_tls::GrpcServerTlsConfig::from_env() {
            Ok(config) => {
                tracing::info!("mTLS enabled - service-to-service authentication active");
                Some(config)
            }
            Err(e) => {
                tracing::warn!(
                    "mTLS disabled - TLS config not found: {}. Using development mode for testing only.",
                    e
                );
                // Use runtime check instead of compile-time cfg! to allow staging without TLS
                let is_dev = std::env::var("APP_ENV")
                    .map(|v| v == "development" || v == "staging")
                    .unwrap_or(false);
                if is_dev {
                    tracing::info!(
                        "Development/Staging mode: Starting without TLS (NOT FOR PRODUCTION)"
                    );
                    None
                } else {
                    tracing::error!(
                        "Production requires mTLS - GRPC_SERVER_CERT_PATH must be set: {}",
                        e
                    );
                    return;
                }
            }
        };

        // ✅ P0: Build server with optional TLS
        let mut server_builder = GrpcServer::builder();

        if let Some(tls_cfg) = tls_config {
            match tls_cfg.build_server_tls() {
                Ok(server_tls) => match server_builder.tls_config(server_tls) {
                    Ok(builder) => {
                        server_builder = builder;
                        tracing::info!("gRPC server TLS configured successfully");
                    }
                    Err(e) => {
                        tracing::error!("Failed to configure TLS on gRPC server: {}", e);
                        return;
                    }
                },
                Err(e) => {
                    tracing::error!("Failed to build server TLS config: {}", e);
                    return;
                }
            }
        }

        if let Err(e) = server_builder
            .add_service(health_service)
            .add_service(
                recommendation_service::grpc::recommendation_service_server::RecommendationServiceServer::with_interceptor(
                    svc,
                    server_interceptor,
                ),
            )
            .serve(grpc_addr)
            .await
        {
            tracing::error!("gRPC server error: {}", e);
        }
    });

    // Start HTTP server
    let http_server = HttpServer::new(move || {
        let openapi_doc = openapi::doc();

        App::new()
            .app_data(web::Data::new(openapi_doc.clone()))
            .service(
                SwaggerUi::new("/swagger-ui/{_:.*}")
                    .url("/api/v1/openapi.json", openapi_doc.clone()),
            )
            .route("/api/v1/openapi.json", web::get().to(openapi_json))
            .app_data(db_pool.clone())
            .app_data(rec_handler_state.clone())
            .app_data(feed_handler_state.clone())
            .route("/health", web::get().to(|| async { "OK" }))
            // Health endpoints for K8s probes
            .route("/api/v1/health", web::get().to(|| async { "OK" }))
            .route("/api/v1/health/live", web::get().to(|| async { "OK" }))
            .route("/api/v1/health/ready", web::get().to(|| async { "OK" }))
            .route(
                "/metrics",
                web::get().to(recommendation_service::metrics::serve_metrics),
            )
            .wrap_fn(|req, srv| {
                let method = req.method().to_string();
                let path = req
                    .match_pattern()
                    .map(|p| p.to_string())
                    .unwrap_or_else(|| req.path().to_string());
                let start = Instant::now();

                let fut = srv.call(req);
                async move {
                    match fut.await {
                        Ok(res) => {
                            recommendation_service::metrics::observe_http_request(
                                &method,
                                &path,
                                res.status().as_u16(),
                                start.elapsed(),
                            );
                            Ok(res)
                        }
                        Err(err) => {
                            recommendation_service::metrics::observe_http_request(
                                &method,
                                &path,
                                500,
                                start.elapsed(),
                            );
                            Err(err)
                        }
                    }
                }
            })
            .service(get_recommendations)
            .service(get_model_info)
            .service(rank_candidates)
            .service(semantic_search)
            // Guest feed - public endpoint at /api/v2/guest/feed/trending (NO authentication)
            // Separated from authenticated feed to avoid Actix-web scope conflicts
            .service(web::scope("/api/v2/guest/feed").service(get_guest_feed))
            // Authenticated feed - requires JWT at /api/v2/feed
            .service(
                web::scope("/api/v2/feed")
                    .wrap(JwtAuthMiddleware)
                    .service(get_feed)
                    .service(get_saved_feed)
                    .service(get_liked_feed),
            )
    })
    .bind(format!("0.0.0.0:{}", config.app.port))?
    .run()
    .await;

    http_server
}
