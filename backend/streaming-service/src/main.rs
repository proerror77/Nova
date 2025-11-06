//! Streaming Service Main Entry Point
//!
//! This service handles live video streaming functionality including:
//! - Stream lifecycle management
//! - WebSocket-based chat
//! - RTMP webhook integration
//! - Stream discovery and analytics

mod openapi;

use actix_web::{dev::Service, middleware as actix_middleware, web, App, HttpServer};
use tonic_health::server::health_reporter;
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::Mutex;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use utoipa_swagger_ui::SwaggerUi;

use streaming_service::handlers::StreamHandlerState;
use streaming_service::metrics;
use streaming_service::services::{
    EventProducer, RtmpWebhookHandler, StreamAnalyticsService, StreamChatStore,
    StreamDiscoveryService, StreamRepository, StreamService, ViewerCounter,
};

async fn openapi_json(doc: web::Data<utoipa::openapi::OpenApi>) -> actix_web::HttpResponse {
    let body = serde_json::to_string(&*doc)
        .expect("Failed to serialize OpenAPI document for streaming-service");

    actix_web::HttpResponse::Ok()
        .content_type("application/json")
        .body(body)
}

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
    let mut cfg = DbPoolConfig::from_env().unwrap_or_default();
    if cfg.database_url.is_empty() {
        cfg.database_url = database_url.clone();
    }
    if cfg.max_connections < 20 {
        cfg.max_connections = 20;
    }
    let db_pool = create_pg_pool(cfg)
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

    // gRPC server (spawned in background) on PORT+1000
    let grpc_addr: SocketAddr = format!("0.0.0.0:{}", port + 1000)
        .parse()
        .expect("Invalid gRPC address");
    let db_pool_grpc = db_pool.clone();
    tokio::spawn(async move {
        let svc = streaming_service::grpc::StreamingServiceImpl::new(db_pool_grpc);
        tracing::info!("gRPC server listening on {}", grpc_addr);
        let (mut health, health_service) = health_reporter();
        health
            .set_serving::<streaming_service::grpc::streaming_service_server::StreamingServiceServer<streaming_service::grpc::StreamingServiceImpl>>()
            .await;

        // Server-side correlation-id extractor interceptor
        fn server_interceptor(mut req: tonic::Request<()>) -> Result<tonic::Request<()>, tonic::Status> {
            if let Some(val) = req.metadata().get("correlation-id") {
                if let Ok(s) = val.to_str() { req.extensions_mut().insert::<String>(s.to_string()); }
            }
            Ok(req)
        }

        if let Err(e) = tonic::transport::Server::builder()
            .add_service(health_service)
            .add_service(
                streaming_service::grpc::streaming_service_server::StreamingServiceServer::with_interceptor(
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
    HttpServer::new(move || {
        let openapi_doc = openapi::doc();

        App::new()
            .app_data(web::Data::new(openapi_doc.clone()))
            .service(
                SwaggerUi::new("/swagger-ui/{_:.*}")
                    .url("/api/v1/openapi.json", openapi_doc.clone()),
            )
            .route("/api/v1/openapi.json", web::get().to(openapi_json))
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
