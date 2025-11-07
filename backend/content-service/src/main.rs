use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer};
use chrono::Utc;
use content_service::cache::{ContentCache, FeedCache};
use content_service::db::ch_client::ClickHouseClient;
use content_service::db::ensure_feed_tables;
use grpc_clients::{config::GrpcConfig, AuthClient, GrpcClientPool};
use content_service::handlers::{self, feed::FeedHandlerState};
use content_service::jobs::feed_candidates::FeedCandidateRefreshJob;
use content_service::middleware;
use content_service::openapi::ApiDoc;
use content_service::services::{FeedRankingConfig, FeedRankingService};
use crypto_core::jwt;
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use redis::aio::ConnectionManager;
use redis::RedisError;
use redis_utils::{RedisPool, SentinelConfig};
use serde::Serialize;
use std::collections::HashMap;
use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{broadcast, Mutex};
use tokio::task::JoinSet;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

struct HealthState {
    db_pool: sqlx::Pool<sqlx::Postgres>,
    redis_manager: Arc<Mutex<ConnectionManager>>,
    clickhouse_client: Arc<ClickHouseClient>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "lowercase")]
enum ComponentStatus {
    Healthy,
    Degraded,
    Unhealthy,
}

#[derive(Serialize)]
struct ComponentCheck {
    status: ComponentStatus,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    latency_ms: Option<u64>,
}

#[derive(Serialize)]
struct ReadinessResponse {
    ready: bool,
    status: ComponentStatus,
    checks: HashMap<String, ComponentCheck>,
    timestamp: String,
}

impl HealthState {
    fn new(
        db_pool: sqlx::Pool<sqlx::Postgres>,
        redis_manager: Arc<Mutex<ConnectionManager>>,
        clickhouse_client: Arc<ClickHouseClient>,
    ) -> Self {
        Self {
            db_pool,
            redis_manager,
            clickhouse_client,
        }
    }

    async fn check_postgres(&self) -> Result<(), sqlx::Error> {
        sqlx::query("SELECT 1")
            .fetch_one(&self.db_pool)
            .await
            .map(|_| ())
    }

    async fn check_redis(&self) -> Result<(), RedisError> {
        let mut conn = self.redis_manager.lock().await;
        let pong: String = redis::cmd("PING").query_async(&mut *conn).await?;
        if pong == "PONG" {
            Ok(())
        } else {
            Err(RedisError::from((
                redis::ErrorKind::ResponseError,
                "unexpected PING response",
            )))
        }
    }

    async fn check_clickhouse(&self) -> Result<(), String> {
        self.clickhouse_client
            .health_check()
            .await
            .map_err(|e| e.to_string())
    }
}

async fn health_summary(state: web::Data<HealthState>) -> HttpResponse {
    match state.check_postgres().await {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({
            "status": "ok",
            "service": "content-service",
            "version": env!("CARGO_PKG_VERSION")
        })),
        Err(e) => HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "unhealthy",
            "error": format!("PostgreSQL connection failed: {}", e),
            "service": "content-service"
        })),
    }
}

async fn readiness_summary(state: web::Data<HealthState>) -> HttpResponse {
    let mut checks = HashMap::new();
    let mut ready = true;

    let start = Instant::now();
    let pg_result = state.check_postgres().await;
    let pg_latency = Some(start.elapsed().as_millis() as u64);
    let postgres_check = match pg_result {
        Ok(_) => ComponentCheck {
            status: ComponentStatus::Healthy,
            message: "PostgreSQL connection successful".to_string(),
            latency_ms: pg_latency,
        },
        Err(e) => {
            ready = false;
            ComponentCheck {
                status: ComponentStatus::Unhealthy,
                message: format!("PostgreSQL connection failed: {}", e),
                latency_ms: pg_latency,
            }
        }
    };
    checks.insert("postgresql".to_string(), postgres_check);

    let start = Instant::now();
    let redis_result = state.check_redis().await;
    let redis_latency = Some(start.elapsed().as_millis() as u64);
    let redis_check = match redis_result {
        Ok(_) => ComponentCheck {
            status: ComponentStatus::Healthy,
            message: "Redis ping successful".to_string(),
            latency_ms: redis_latency,
        },
        Err(e) => {
            ready = false;
            ComponentCheck {
                status: ComponentStatus::Unhealthy,
                message: format!("Redis ping failed: {}", e),
                latency_ms: redis_latency,
            }
        }
    };
    checks.insert("redis".to_string(), redis_check);

    let start = Instant::now();
    let clickhouse_result = state.check_clickhouse().await;
    let clickhouse_latency = Some(start.elapsed().as_millis() as u64);
    let clickhouse_check = match clickhouse_result {
        Ok(_) => ComponentCheck {
            status: ComponentStatus::Healthy,
            message: "ClickHouse query successful".to_string(),
            latency_ms: clickhouse_latency,
        },
        Err(e) => {
            ready = false;
            ComponentCheck {
                status: ComponentStatus::Degraded,
                message: format!("ClickHouse health check failed: {}", e),
                latency_ms: clickhouse_latency,
            }
        }
    };
    checks.insert("clickhouse".to_string(), clickhouse_check);

    let status = if ready {
        ComponentStatus::Healthy
    } else {
        ComponentStatus::Unhealthy
    };

    let response = ReadinessResponse {
        ready,
        status,
        checks,
        timestamp: Utc::now().to_rfc3339(),
    };

    if ready {
        HttpResponse::Ok().json(response)
    } else {
        HttpResponse::ServiceUnavailable().json(response)
    }
}

async fn liveness_check() -> HttpResponse {
    HttpResponse::Ok().json(serde_json::json!({"alive": true}))
}

async fn openapi_json(doc: web::Data<utoipa::openapi::OpenApi>) -> actix_web::Result<HttpResponse> {
    let body = serde_json::to_string(&*doc).map_err(|e| {
        tracing::error!("OpenAPI serialization failed: {}", e);
        actix_web::error::ErrorInternalServerError("OpenAPI serialization error")
    })?;

    Ok(HttpResponse::Ok()
        .content_type("application/json")
        .body(body))
}

async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};

        let mut terminate =
            signal(SignalKind::terminate()).expect("Failed to install SIGTERM handler");

        tokio::select! {
            _ = tokio::signal::ctrl_c() => {},
            _ = terminate.recv() => {},
        }
    }

    #[cfg(not(unix))]
    {
        tokio::signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    }
}

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
    let config = match content_service::Config::from_env() {
        Ok(cfg) => cfg,
        Err(e) => {
            tracing::error!("Configuration loading failed: {:#}", e);
            eprintln!("ERROR: Failed to load configuration: {}", e);
            std::process::exit(1);
        }
    };

    tracing::info!("Starting content-service v{}", env!("CARGO_PKG_VERSION"));
    tracing::info!("Environment: {}", config.app.env);

    match jwt::load_validation_key() {
        Ok(public_key) => {
            if let Err(err) = jwt::initialize_jwt_validation_only(&public_key) {
                return Err(io::Error::new(
                    io::ErrorKind::Other,
                    format!("Failed to initialize JWT keys: {err}"),
                ));
            }
        }
        Err(err) => {
            tracing::warn!(
                "JWT public key not configured ({err}); authentication middleware will fail requests"
            );
        }
    }

    // Initialize database connection pool (standardized)
    let mut db_cfg = DbPoolConfig::from_env().unwrap_or_default();
    if db_cfg.database_url.is_empty() {
        db_cfg.database_url = config.database.url.clone();
    }
    // Enforce sane minimums; allow env to override upwards
    if db_cfg.max_connections < 20 {
        db_cfg.max_connections = std::cmp::max(20, config.database.max_connections);
    }

    db_cfg.log_config();
    let db_pool = match create_pg_pool(db_cfg).await {
        Ok(pool) => pool,
        Err(e) => {
            tracing::error!("Database pool creation failed: {:#}", e);
            eprintln!("ERROR: Failed to create database pool: {}", e);
            std::process::exit(1);
        }
    };
    let db_pool_http = db_pool.clone();

    tracing::info!("Connected to database via db-pool crate");

    let http_bind_address = format!("{}:{}", config.app.host, 8081);
    let grpc_bind_address = format!("{}:9081", config.app.host);

    tracing::info!("Starting HTTP server at {}", http_bind_address);
    tracing::info!("Starting gRPC server at {}", grpc_bind_address);

    // Initialize Redis cache for content entities
    let sentinel_cfg = config.cache.sentinel.as_ref().map(|cfg| {
        SentinelConfig::new(
            cfg.endpoints.clone(),
            cfg.master_name.clone(),
            Duration::from_millis(cfg.poll_interval_ms),
        )
    });

    let redis_pool = RedisPool::connect(&config.cache.url, sentinel_cfg)
        .await
        .map_err(|e| {
            io::Error::new(
                io::ErrorKind::Other,
                format!("Failed to initialize Redis connection: {e}"),
            )
        })?;

    let content_cache = Arc::new(ContentCache::with_manager(redis_pool.manager(), None));
    let feed_cache = Arc::new(FeedCache::new(redis_pool.manager(), 120));

    let ch_cfg = &config.clickhouse;
    let ch_client = Arc::new(ClickHouseClient::new(
        &ch_cfg.url,
        &ch_cfg.database,
        &ch_cfg.username,
        &ch_cfg.password,
        ch_cfg.query_timeout_ms,
    ));

    ensure_feed_tables(ch_client.as_ref()).await.map_err(|e| {
        io::Error::new(
            io::ErrorKind::Other,
            format!("Failed to ensure ClickHouse feed schema: {e}"),
        )
    })?;

    match ch_client.health_check().await {
        Ok(()) => {
            tracing::info!("✅ ClickHouse connection validated");
        }
        Err(e) => {
            tracing::error!("❌ FATAL: ClickHouse health check failed - {}", e);
            tracing::error!(
                "   Fix: Ensure ClickHouse is running and accessible at {}",
                ch_cfg.url
            );
            return Err(io::Error::new(
                io::ErrorKind::ConnectionRefused,
                format!("ClickHouse initialization failed: {}", e),
            ));
        }
    }

    // Initialize gRPC client pool with connection pooling
    tracing::info!("Initializing gRPC client pool with connection pooling");
    let grpc_config = GrpcConfig::from_env().map_err(|e| {
        io::Error::new(
            io::ErrorKind::Other,
            format!("Failed to load gRPC config: {}", e),
        )
    })?;
    let grpc_pool = Arc::new(
        GrpcClientPool::new(&grpc_config)
            .await
            .map_err(|e| {
                io::Error::new(
                    io::ErrorKind::Other,
                    format!("Failed to create gRPC client pool: {}", e),
                )
            })?,
    );

    // Initialize AuthClient from connection pool
    let auth_client = Arc::new(AuthClient::from_pool(grpc_pool.clone()));
    tracing::info!("✅ Auth-service gRPC client initialized from connection pool");

    let feed_ranking = Arc::new(FeedRankingService::new(
        ch_client.clone(),
        feed_cache.clone(),
        db_pool.clone(),
        FeedRankingConfig::from(&config.feed),
    ));

    let feed_candidate_job = FeedCandidateRefreshJob::new(ch_client.clone());

    let feed_state = web::Data::new(FeedHandlerState {
        feed_ranking: feed_ranking.clone(),
    });
    let content_cache_data = web::Data::new(content_cache.clone());
    let auth_client_data = web::Data::new(auth_client.clone());

    let health_state = web::Data::new(HealthState::new(
        db_pool.clone(),
        redis_pool.manager(),
        ch_client.clone(),
    ));

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

        let openapi_doc = ApiDoc::openapi();

        App::new()
            .app_data(web::Data::new(openapi_doc.clone()))
            .service(
                SwaggerUi::new("/swagger-ui/{_:.*}")
                    .url("/api/v1/openapi.json", openapi_doc.clone()),
            )
            .route("/api/v1/openapi.json", web::get().to(openapi_json))
            .app_data(web::Data::new(db_pool_http.clone()))
            .app_data(content_cache_data.clone())
            .app_data(auth_client_data.clone())
            .app_data(feed_state.clone())
            .app_data(health_state.clone())
            .wrap(cors)
            .wrap(Logger::default())
            .wrap(tracing_actix_web::TracingLogger::default())
            .route(
                "/metrics",
                web::get().to(content_service::metrics::serve_metrics),
            )
            // Health check endpoints
            .route("/api/v1/health", web::get().to(health_summary))
            .route("/api/v1/health/ready", web::get().to(readiness_summary))
            .route("/api/v1/health/live", web::get().to(liveness_check))
            .service(
                web::scope("/api/v1")
                    .wrap(middleware::JwtAuthMiddleware)
                    .wrap(middleware::MetricsMiddleware)
                    .service(web::scope("/feed").route("", web::get().to(handlers::get_feed)))
                    .service(
                        web::scope("/posts")
                            .service(web::resource("").route(web::post().to(handlers::create_post)))
                            .service(
                                web::resource("/{post_id}")
                                    .route(web::get().to(handlers::get_post))
                                    .route(web::patch().to(handlers::update_post_status))
                                    .route(web::delete().to(handlers::delete_post)),
                            )
                            .service(
                                web::resource("/user/{user_id}")
                                    .route(web::get().to(handlers::get_user_posts)),
                            ),
                    )
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

    let server_handle = server.handle();

    let (shutdown_tx, _) = broadcast::channel(1);
    let grpc_shutdown = shutdown_tx.subscribe();

    // Spawn both HTTP and gRPC servers concurrently
    let mut tasks: JoinSet<io::Result<()>> = JoinSet::new();

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
    let auth_client_grpc = auth_client.clone();
    tasks.spawn(async move {
        tracing::info!("gRPC server is running");
        content_service::grpc::start_grpc_server(
            grpc_addr,
            db_pool_grpc,
            cache_grpc,
            feed_cache_grpc,
            feed_ranking_grpc,
            auth_client_grpc,
            grpc_shutdown,
        )
        .await
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("{}", e)))
    });

    // Feed refresh background job
    let feed_refresh_job = feed_candidate_job;
    tasks.spawn(async move {
        feed_refresh_job.run().await;
        Ok(())
    });

    let mut first_error: Option<io::Error> = None;

    let shutdown = shutdown_signal();
    tokio::pin!(shutdown);

    loop {
        tokio::select! {
            result = tasks.join_next() => {
                match result {
                    Some(Ok(Ok(_))) => {
                        tracing::info!("Background task completed");
                    }
                    Some(Ok(Err(e))) => {
                        tracing::error!("Task returned error: {}", e);
                        if first_error.is_none() {
                            first_error = Some(e);
                        }
                        let _ = shutdown_tx.send(());
                        server_handle.stop(true).await;
                        tasks.shutdown().await;
                        break;
                    }
                    Some(Err(e)) => {
                        tracing::error!("Task join error: {}", e);
                        if first_error.is_none() {
                            first_error = Some(io::Error::new(io::ErrorKind::Other, e.to_string()));
                        }
                        let _ = shutdown_tx.send(());
                        server_handle.stop(true).await;
                        tasks.shutdown().await;
                        break;
                    }
                    None => break,
                }
            }
            _ = &mut shutdown => {
                tracing::info!("Shutdown signal received");
                let _ = shutdown_tx.send(());
                server_handle.stop(true).await;
                tasks.shutdown().await;
                break;
            }
        }
    }

    tracing::info!("Content-service shutting down");

    match first_error {
        Some(e) => Err(e),
        None => Ok(()),
    }
}
