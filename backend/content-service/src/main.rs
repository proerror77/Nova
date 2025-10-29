use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer};
use content_service::cache::{ContentCache, FeedCache};
use content_service::db::ch_client::ClickHouseClient;
use content_service::db::ensure_feed_tables;
use content_service::handlers::{self, feed::FeedHandlerState};
use content_service::jobs::feed_candidates::FeedCandidateRefreshJob;
use content_service::services::{FeedRankingConfig, FeedRankingService};
use crypto_core::jwt;
use sqlx::postgres::PgPoolOptions;
use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::task::JoinSet;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

/// Content Service
///
/// A microservice that handles posts, comments, and stories endpoints.
/// This service is part of the P1.2 service splitting initiative to extract
/// content management from the monolithic user-service.
///
/// # Routes
///
/// - `/api/v1/posts/*` - Create, read, update, delete posts
/// - `/api/v1/comments/*` - Create, read, update, delete comments
/// - `/api/v1/stories/*` - Create, read, update, delete stories
///
/// # Architecture
///
/// This service follows the same architecture as user-service:
/// - HTTP handlers with request/response conversion
/// - PostgreSQL for persistent storage
/// - Redis for caching and sessions
/// - Kafka for events and CDC (Change Data Capture)
/// - ClickHouse for analytics
/// - Circuit breakers for resilience
///
/// # Deployment
///
/// Content-service runs on port 8081 (configurable via CONTENT_SERVICE_PORT env var).
/// It shares the same database, cache, and infrastructure with other Nova services.
///
/// # Status
///
/// This is a skeleton implementation. Full extraction of handlers, services,
/// and models from user-service will be completed in the implementation phase.

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Support container healthchecks via CLI subcommand: `healthcheck-http` or legacy `healthcheck`
    {
        let mut args = std::env::args();
        let _bin = args.next();
        if let Some(cmd) = args.next() {
            if cmd == "healthcheck" || cmd == "healthcheck-http" {
                let url = "http://127.0.0.1:8081/api/v1/health";
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
    let config = content_service::Config::from_env().expect("Failed to load configuration");

    tracing::info!("Starting content-service v{}", env!("CARGO_PKG_VERSION"));
    tracing::info!("Environment: {}", config.app.env);

    if let Ok(public_key) = std::env::var("JWT_PUBLIC_KEY_PEM") {
        if let Err(err) = jwt::initialize_jwt_validation_only(&public_key) {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("Failed to initialize JWT keys: {err}"),
            ));
        }
    } else {
        tracing::warn!("JWT_PUBLIC_KEY_PEM not set; authentication middleware will fail requests");
    }

    // Initialize database connection pool
    let db_url = std::env::var("DATABASE_URL").unwrap_or_else(|_| {
        "postgres://nova:nova_password@localhost:5432/nova_content".to_string()
    });

    let db_pool = PgPoolOptions::new()
        .max_connections(20)
        .connect(&db_url)
        .await
        .expect("Failed to connect to database");
    let db_pool_http = db_pool.clone();

    tracing::info!("Connected to database");

    let http_bind_address = format!("{}:{}", config.app.host, 8081);
    let grpc_bind_address = format!("{}:9081", config.app.host);

    tracing::info!("Starting HTTP server at {}", http_bind_address);
    tracing::info!("Starting gRPC server at {}", grpc_bind_address);

    // Initialize Redis cache for content entities
    let redis_client = redis::Client::open(config.cache.url.as_str())
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("Invalid REDIS_URL: {e}")))?;
    let content_cache = Arc::new(
        ContentCache::new(redis_client.clone(), None)
            .await
            .map_err(|e| {
                io::Error::new(
                    io::ErrorKind::Other,
                    format!("Failed to initialize cache: {e}"),
                )
            })?,
    );

    let feed_cache_manager = redis_client
        .get_connection_manager()
        .await
        .map_err(|e| {
            io::Error::new(
                io::ErrorKind::Other,
                format!("Failed to connect Redis: {e}"),
            )
        })?;
    let feed_cache = Arc::new(FeedCache::new(feed_cache_manager, 120));

    let ch_cfg = &config.clickhouse;
    let ch_client = Arc::new(ClickHouseClient::new(
        &ch_cfg.url,
        &ch_cfg.database,
        &ch_cfg.username,
        &ch_cfg.password,
        ch_cfg.query_timeout_ms,
    ));

    ensure_feed_tables(ch_client.as_ref())
        .await
        .map_err(|e| {
            io::Error::new(
                io::ErrorKind::Other,
                format!("Failed to ensure ClickHouse feed schema: {e}"),
            )
        })?;

    let feed_ranking = Arc::new(FeedRankingService::new(
        ch_client.clone(),
        feed_cache.clone(),
        db_pool.clone(),
        FeedRankingConfig::from(&config.feed),
    ));

    let _feed_candidate_job = FeedCandidateRefreshJob::new(ch_client.clone()).spawn();

    let feed_state = web::Data::new(FeedHandlerState {
        feed_ranking: feed_ranking.clone(),
    });
    let content_cache_data = web::Data::new(content_cache.clone());

    // Parse gRPC bind address
    let grpc_addr: SocketAddr = grpc_bind_address
        .parse()
        .expect("Failed to parse gRPC bind address");

    // Create HTTP server
    let server = HttpServer::new(move || {
        // Build CORS configuration
        let cors_builder = Cors::default();
        let mut cors = cors_builder;
        for origin in config.cors.allowed_origins.split(',') {
            let origin = origin.trim();
            if origin == "*" {
                cors = cors.allow_any_origin();
            } else {
                cors = cors.allowed_origin(origin);
            }
        }
        cors = cors.allow_any_method().allow_any_header().max_age(3600);

        App::new()
            .app_data(web::Data::new(db_pool_http.clone()))
            .app_data(content_cache_data.clone())
            .app_data(feed_state.clone())
            .wrap(cors)
            .wrap(Logger::default())
            .wrap(tracing_actix_web::TracingLogger::default())
            .route("/metrics", web::get().to(content_service::metrics::serve_metrics))
            // Health check endpoints
            .route(
                "/api/v1/health",
                web::get().to(|| async {
                    HttpResponse::Ok().json(serde_json::json!({
                        "status": "ok",
                        "service": "content-service",
                        "version": env!("CARGO_PKG_VERSION")
                    }))
                }),
            )
            .route(
                "/api/v1/health/ready",
                web::get().to(|| async {
                    HttpResponse::Ok().json(serde_json::json!({
                        "status": "ready"
                    }))
                }),
            )
            .route(
                "/api/v1/health/live",
                web::get().to(|| async {
                    HttpResponse::Ok().json(serde_json::json!({
                        "status": "alive"
                    }))
                }),
            )
            // OpenAPI JSON endpoint
            .route(
                "/api/v1/openapi.json",
                web::get().to(|| async {
                    use utoipa::OpenApi;
                    HttpResponse::Ok()
                        .content_type("application/json")
                        .json(content_service::openapi::ApiDoc::openapi())
                }),
            )
            .service(
                web::scope("/api/v1")
                    .service(web::scope("/feed").route("", web::get().to(handlers::get_feed)))
                    .service(
                        web::scope("/stories")
                            .service(
                                web::resource("").route(web::post().to(handlers::create_story)),
                            )
                            .route("/feed", web::get().to(handlers::get_stories_feed))
                            .service(
                                web::resource("/close-friends")
                                    .route(web::post().to(handlers::add_close_friend)),
                            )
                            .service(
                                web::resource("/close-friends/{friend_id}")
                                    .route(web::delete().to(handlers::remove_close_friend)),
                            )
                            .service(
                                web::resource("/user/{owner_id}")
                                    .route(web::get().to(handlers::get_user_stories)),
                            )
                            .service(
                                web::resource("/{story_id}")
                                    .route(web::get().to(handlers::get_story))
                                    .route(web::delete().to(handlers::delete_story)),
                            )
                            .route(
                                "/{story_id}/views",
                                web::post().to(handlers::track_story_view),
                            )
                            .route(
                                "/{story_id}/privacy",
                                web::patch().to(handlers::update_story_privacy),
                            ),
                    ),
            )
    })
    .bind(&http_bind_address)?
    .workers(4)
    .run();

    // Spawn both HTTP and gRPC servers concurrently
    let mut tasks = JoinSet::new();

    // HTTP server task
    tasks.spawn(async move {
        tracing::info!("HTTP server is running");
        server.await
    });

    // gRPC server task
    let db_pool_grpc = db_pool.clone();
    let cache_grpc = content_cache.clone();
    let feed_cache_grpc = feed_cache.clone();
    let feed_ranking_grpc = feed_ranking.clone();
    tasks.spawn(async move {
        tracing::info!("gRPC server is running");
        content_service::grpc::start_grpc_server(
            grpc_addr,
            db_pool_grpc,
            cache_grpc,
            feed_cache_grpc,
            feed_ranking_grpc,
        )
            .await
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("{}", e)))
    });

    // Wait for any server to fail
    let mut first_error = None;
    while let Some(result) = tasks.join_next().await {
        match result {
            Ok(Ok(_)) => {
                // Server completed normally (shouldn't happen unless shut down)
                tracing::warn!("Server completed");
            }
            Ok(Err(e)) => {
                // Server error
                tracing::error!("Server error: {}", e);
                if first_error.is_none() {
                    first_error = Some(e);
                }
            }
            Err(e) => {
                // Task join error
                tracing::error!("Task error: {}", e);
                if first_error.is_none() {
                    first_error = Some(io::Error::new(io::ErrorKind::Other, format!("{}", e)));
                }
            }
        }
    }

    tracing::info!("Content-service shutting down");

    match first_error {
        Some(e) => Err(e),
        None => Ok(()),
    }
}
