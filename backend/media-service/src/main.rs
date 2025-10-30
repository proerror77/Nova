/// Media Service - HTTP Server
///
/// Handles video uploads, processing, and streaming.
/// Extracted from user-service as part of P1.2 service splitting.
use actix_web::{middleware as actix_middleware, web, App, HttpResponse, HttpServer};
use crypto_core::jwt;
use media_service::cache::MediaCache;
use media_service::handlers;
use media_service::middleware;
use media_service::services::ReelTranscodePipeline;
use media_service::Config;
use redis_utils::{RedisPool, SentinelConfig};
use sqlx::postgres::PgPoolOptions;
use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::broadcast;
use tokio::task::JoinSet;
use tracing::info;
use tracing_subscriber;

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

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Load configuration from environment
    let config = Config::from_env().expect("Failed to load configuration");

    let http_bind_address = format!("{}:{}", config.app.host, 8082);
    let grpc_bind_address = format!("{}:9082", config.app.host);

    println!(
        "🎥 Media Service starting HTTP server on {}",
        http_bind_address
    );
    println!(
        "🎥 Media Service starting gRPC server on {}",
        grpc_bind_address
    );

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

    // Initialize database connection pool
    let db_pool = PgPoolOptions::new()
        .max_connections(config.database.max_connections)
        .connect(&config.database.url)
        .await
        .expect("Failed to connect to database");

    let db_pool_http = db_pool.clone();
    let reel_pipeline = ReelTranscodePipeline::new(db_pool.clone());

    info!(
        "Connected to database (max_connections={})",
        config.database.max_connections
    );

    let sentinel_cfg = config.cache.sentinel.as_ref().map(|cfg| {
        SentinelConfig::new(
            cfg.endpoints.clone(),
            cfg.master_name.clone(),
            Duration::from_millis(cfg.poll_interval_ms),
        )
    });

    let redis_pool = RedisPool::connect(&config.cache.redis_url, sentinel_cfg)
        .await
        .map_err(|e| {
            io::Error::new(
                io::ErrorKind::Other,
                format!("Failed to initialize Redis connection: {e}"),
            )
        })?;

    let media_cache = Arc::new(MediaCache::with_manager(redis_pool.manager(), None));
    let media_cache_http = media_cache.clone();

    // Parse gRPC bind address
    let grpc_addr: SocketAddr = grpc_bind_address
        .parse()
        .expect("Failed to parse gRPC bind address");

    // Create HTTP server
    let server = HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(config.clone()))
            .app_data(web::Data::new(db_pool_http.clone()))
            .app_data(web::Data::new(reel_pipeline.clone()))
            .app_data(web::Data::new(media_cache_http.clone()))
            .wrap(actix_middleware::Logger::default())
            .route(
                "/metrics",
                web::get().to(media_service::metrics::serve_metrics),
            )
            .route(
                "/api/v1/health",
                web::get()
                    .to(|| async { HttpResponse::Ok().json(serde_json::json!({"status": "ok"})) }),
            )
            .route(
                "/api/v1/health/ready",
                web::get().to(|| async { HttpResponse::Ok().finish() }),
            )
            .route(
                "/api/v1/health/live",
                web::get().to(|| async { HttpResponse::Ok().finish() }),
            )
            .route(
                "/api/v1/openapi.json",
                web::get().to(|| async {
                    use utoipa::OpenApi;
                    HttpResponse::Ok()
                        .content_type("application/json")
                        .json(media_service::openapi::ApiDoc::openapi())
                }),
            )
            .service(
                web::scope("/api/v1")
                    .wrap(middleware::JwtAuthMiddleware)
                    .wrap(middleware::MetricsMiddleware)
                    .service(
                        web::scope("/uploads")
                            .route("", web::post().to(handlers::start_upload))
                            .route("/{upload_id}", web::get().to(handlers::get_upload))
                            .route(
                                "/{upload_id}/progress",
                                web::patch().to(handlers::update_upload_progress),
                            )
                            .route(
                                "/{upload_id}/complete",
                                web::post().to(handlers::complete_upload),
                            )
                            .route(
                                "/{upload_id}/presigned-url",
                                web::post().to(handlers::generate_presigned_url),
                            )
                            .route("/{upload_id}", web::delete().to(handlers::cancel_upload)),
                    )
                    .service(
                        web::scope("/videos")
                            .route("", web::get().to(handlers::list_videos))
                            .route("", web::post().to(handlers::create_video))
                            .route("/{id}", web::get().to(handlers::get_video))
                            .route("/{id}", web::patch().to(handlers::update_video))
                            .route("/{id}", web::delete().to(handlers::delete_video)),
                    )
                    .service(
                        web::scope("/reels")
                            .route("", web::get().to(handlers::list_reels))
                            .route("", web::post().to(handlers::create_reel))
                            .route("/{id}", web::get().to(handlers::get_reel))
                            .route("/{id}", web::delete().to(handlers::delete_reel)),
                    ),
            )
    })
    .bind(&http_bind_address)?
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
    let cache_grpc = media_cache.clone();
    tasks.spawn(async move {
        tracing::info!("gRPC server is running");
        media_service::grpc::start_grpc_server(grpc_addr, db_pool_grpc, cache_grpc, grpc_shutdown)
            .await
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("{}", e)))
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

    tracing::info!("Media-service shutting down");

    if let Some(err) = first_error {
        Err(err)
    } else {
        Ok(())
    }
}
