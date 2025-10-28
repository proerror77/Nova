/// Media Service - HTTP Server
///
/// Handles video uploads, processing, and streaming.
/// Extracted from user-service as part of P1.2 service splitting.

use actix_web::{web, App, HttpResponse, HttpServer, middleware as actix_middleware};
use media_service::Config;
use std::io;
use std::net::SocketAddr;
use tokio::task::JoinSet;
use tracing_subscriber;

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Load configuration from environment
    let config = Config::from_env()
        .expect("Failed to load configuration");

    let http_bind_address = format!("{}:{}", config.app.host, 8082);
    let grpc_bind_address = format!("{}:9082", config.app.host);

    println!("🎥 Media Service starting HTTP server on {}", http_bind_address);
    println!("🎥 Media Service starting gRPC server on {}", grpc_bind_address);

    // Parse gRPC bind address
    let grpc_addr: SocketAddr = grpc_bind_address.parse()
        .expect("Failed to parse gRPC bind address");

    // Create HTTP server
    let server = HttpServer::new(move || {
        App::new()
            .wrap(actix_middleware::Logger::default())
            .route(
                "/api/v1/health",
                web::get().to(|| async { HttpResponse::Ok().json(serde_json::json!({"status": "ok"})) }),
            )
            .route(
                "/api/v1/health/ready",
                web::get().to(|| async { HttpResponse::Ok().finish() }),
            )
            .route(
                "/api/v1/health/live",
                web::get().to(|| async { HttpResponse::Ok().finish() }),
            )
            // TODO: Register video, upload, and reel handlers
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
    tasks.spawn(async move {
        tracing::info!("gRPC server is running");
        media_service::grpc::start_grpc_server(grpc_addr)
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
