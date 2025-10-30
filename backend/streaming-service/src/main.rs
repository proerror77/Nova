//! Streaming Service Main Entry Point
//!
//! This service handles live video streaming functionality including:
//! - Stream lifecycle management
//! - WebSocket-based chat
//! - RTMP webhook integration
//! - Stream discovery and analytics

use actix_web::{dev::Service, middleware as actix_middleware, web, App, HttpServer};
use std::io;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::Mutex;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use streaming_service::handlers::StreamHandlerState;
use streaming_service::metrics;
use streaming_service::services::{
    EventProducer, RtmpWebhookHandler, StreamAnalyticsService, StreamChatStore,
    StreamDiscoveryService, StreamRepository, StreamService, ViewerCounter,
};

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=debug,streaming_service=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting streaming-service v{}", env!("CARGO_PKG_VERSION"));

    // Load configuration from environment
    let database_url =
        std::env::var("DATABASE_URL").unwrap_or_else(|_| "postgres://localhost/nova".to_string());
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".to_string());
    let port = std::env::var("PORT")
        .unwrap_or_else(|_| "8083".to_string())
        .parse::<u16>()
        .expect("Invalid PORT");

    // Initialize database pool
    let db_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await
        .expect("Failed to create database pool");

    // Initialize Redis client and connection manager
    let redis_client =
        redis::Client::open(redis_url.clone()).expect("Failed to create Redis client");
    let redis_conn_mgr = redis::aio::ConnectionManager::new(redis_client.clone())
        .await
        .expect("Failed to create Redis connection manager");

    // Initialize services
    let repository = StreamRepository::new(db_pool.clone());
    let viewer_counter = ViewerCounter::new(redis_conn_mgr.clone());
    let chat_store = StreamChatStore::new(redis_conn_mgr.clone(), 100);
    let kafka_producer = Arc::new(
        EventProducer::new("localhost:9092".to_string(), "stream_events".to_string())
            .expect("Failed to create Kafka producer"),
    );

    let stream_service = Arc::new(Mutex::new(StreamService::new(
        repository.clone(),
        viewer_counter.clone(),
        chat_store.clone(),
        kafka_producer.clone(),
        "rtmp://localhost/live".to_string(),
        "https://cdn.nova.dev/hls".to_string(),
    )));

    let discovery_service = Arc::new(Mutex::new(StreamDiscoveryService::new(
        repository.clone(),
        viewer_counter.clone(),
    )));
    let analytics_service = Arc::new(StreamAnalyticsService::new(repository.clone()));
    let rtmp_handler = Arc::new(Mutex::new(RtmpWebhookHandler::new(
        repository.clone(),
        viewer_counter.clone(),
        "https://cdn.nova.dev/hls".to_string(),
    )));

    // Create handler state
    let handler_state = web::Data::new(StreamHandlerState {
        stream_service,
        discovery_service,
        analytics_service,
        rtmp_handler,
    });

    tracing::info!("Listening on 0.0.0.0:{}", port);

    // Start HTTP server
    HttpServer::new(move || {
        App::new()
            .app_data(handler_state.clone())
            .wrap(actix_middleware::Logger::default())
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
                            metrics::observe_http_request(
                                &method,
                                &path,
                                res.status().as_u16(),
                                start.elapsed(),
                            );
                            Ok(res)
                        }
                        Err(err) => {
                            metrics::observe_http_request(&method, &path, 500, start.elapsed());
                            Err(err)
                        }
                    }
                }
            })
            .route("/health", web::get().to(|| async { "OK" }))
            .route(
                "/metrics",
                web::get().to(streaming_service::metrics::serve_metrics),
            )
        // TODO: Add route configuration when ready
    })
    .bind(format!("0.0.0.0:{}", port))?
    .run()
    .await
}
