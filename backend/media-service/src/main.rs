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
use sqlx::postgres::PgPoolOptions;
use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::task::JoinSet;
use tracing_subscriber;

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
    let db_pool = PgPoolOptions::new()
        .max_connections(config.database.max_connections)
        .connect(&config.database.url)
        .await
        .expect("Failed to connect to database");

    let db_pool_http = db_pool.clone();
    let reel_pipeline = ReelTranscodePipeline::new(db_pool.clone());

    let redis_client = redis::Client::open(config.cache.redis_url.as_str())
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("Invalid REDIS_URL: {e}")))?;
    let media_cache = Arc::new(MediaCache::new(redis_client, None).await.map_err(|e| {
        io::Error::new(
            io::ErrorKind::Other,
            format!("Failed to initialize cache: {e}"),
        )
    })?);

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
            .app_data(web::Data::new(media_cache.clone()))
            .wrap(actix_middleware::Logger::default())
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
                            .route("/{upload_id}/progress", web::patch().to(handlers::update_upload_progress))
                            .route("/{upload_id}/complete", web::post().to(handlers::complete_upload))
                            .route("/{upload_id}/presigned-url", web::post().to(handlers::generate_presigned_url))
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

    // Spawn both HTTP and gRPC servers concurrently
    let mut tasks = JoinSet::new();

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
        media_service::grpc::start_grpc_server(grpc_addr, db_pool_grpc, cache_grpc)
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

    tracing::info!("Media-service shutting down");

    match first_error {
        Some(e) => Err(e),
        None => Ok(()),
    }
}
