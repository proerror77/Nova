use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer};
use std::io;
use std::net::SocketAddr;
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

    let http_bind_address = format!("{}:{}", config.app.host, 8081);
    let grpc_bind_address = format!("{}:9081", config.app.host);

    tracing::info!("Starting HTTP server at {}", http_bind_address);
    tracing::info!("Starting gRPC server at {}", grpc_bind_address);

    // Parse gRPC bind address
    let grpc_addr: SocketAddr = grpc_bind_address.parse()
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
            .wrap(cors)
            .wrap(Logger::default())
            .wrap(tracing_actix_web::TracingLogger::default())
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
                    HttpResponse::Ok()
                        .content_type("application/json")
                        .json(serde_json::json!({
                            "openapi": "3.0.0",
                            "info": {
                                "title": "Nova Content Service API",
                                "version": env!("CARGO_PKG_VERSION")
                            },
                            "paths": {}
                        }))
                }),
            )
            // TODO: Register posts, comments, stories handlers
            // These will be extracted from user-service in the implementation phase
            .service(
                web::scope("/api/v1")
                    .route(
                        "/posts",
                        web::get().to(|| async {
                            HttpResponse::Ok().json(serde_json::json!({
                                "message": "Posts endpoint - TODO: Implement handler extraction"
                            }))
                        }),
                    )
                    .route(
                        "/comments",
                        web::get().to(|| async {
                            HttpResponse::Ok().json(serde_json::json!({
                                "message": "Comments endpoint - TODO: Implement handler extraction"
                            }))
                        }),
                    )
                    .route(
                        "/stories",
                        web::get().to(|| async {
                            HttpResponse::Ok().json(serde_json::json!({
                                "message": "Stories endpoint - TODO: Implement handler extraction"
                            }))
                        }),
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
    tasks.spawn(async move {
        tracing::info!("gRPC server is running");
        content_service::grpc::start_grpc_server(grpc_addr)
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
