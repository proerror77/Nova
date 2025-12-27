use actix_web::HttpResponse;
use actix_web::{web, App, HttpServer};
use analytics_service::grpc::nova::events_service::v2::events_service_server::EventsServiceServer;
use analytics_service::services::{CdcConsumer, CdcConsumerConfig, OutboxConfig, OutboxPublisher};
use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use std::sync::Arc;
use tonic::transport::Server as GrpcServer;
use tonic_health::server::health_reporter;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use uuid::Uuid;

#[actix_web::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=debug,analytics_service=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Initialize rustls crypto provider (required for Rustls 0.23+)
    rustls::crypto::aws_lc_rs::default_provider()
        .install_default()
        .expect("Failed to install rustls crypto provider");

    tracing::info!("Starting analytics-service");

    // Initialize database (standardized pool)
    let mut cfg = DbPoolConfig::for_service("analytics-service");
    if cfg.database_url.is_empty() {
        cfg.database_url = std::env::var("DATABASE_URL").unwrap_or_default();
    }
    if cfg.max_connections < 20 {
        cfg.max_connections = 20;
    }
    cfg.log_config();

    let db_pool = create_pg_pool(cfg)
        .await
        .context("Failed to create database pool")?;

    tracing::info!("Database pool created successfully");

    // Run migrations
    tracing::info!("Running database migrations...");
    sqlx::migrate!("./migrations")
        .run(&db_pool)
        .await
        .context("Failed to run migrations")?;
    tracing::info!("Migrations completed successfully");

    // Create AppState for gRPC service
    let app_state = Arc::new(analytics_service::grpc::AppState::new(db_pool.clone()));

    // Start OutboxPublisher in background (feature flag enabled by default)
    let outbox_enabled = std::env::var("OUTBOX_PUBLISHER_ENABLED")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(true);
    let mut outbox_publisher: Option<Arc<OutboxPublisher>> = None;

    if outbox_enabled {
        let outbox_config = OutboxConfig::from_env();
        tracing::info!(
            "Starting OutboxPublisher (brokers: {}, batch_size: {})",
            outbox_config.kafka_brokers,
            outbox_config.batch_size
        );

        match OutboxPublisher::new(db_pool.clone(), outbox_config) {
            Ok(p) => {
                let publisher = Arc::new(p);
                let publisher_clone = publisher.clone();
                tokio::spawn(async move {
                    tracing::info!("OutboxPublisher task started");
                    if let Err(e) = publisher_clone.start().await {
                        tracing::error!("OutboxPublisher failed: {:?}", e);
                    }
                });
                outbox_publisher = Some(publisher);
            }
            Err(e) => {
                tracing::error!("Failed to create OutboxPublisher: {:?}", e);
                tracing::warn!(
                    "Events service will run without Kafka publishing (outbox disabled)"
                );
            }
        }
    } else {
        tracing::warn!("OUTBOX_PUBLISHER_ENABLED=false - skipping outbox worker start");
    }

    // Start CDC Consumer in background (enabled by default for feed ranking)
    let cdc_enabled = std::env::var("CDC_CONSUMER_ENABLED")
        .map(|v| v != "0" && !v.eq_ignore_ascii_case("false"))
        .unwrap_or(true);

    if cdc_enabled {
        let cdc_config = CdcConsumerConfig::from_env();
        tracing::info!(
            "Starting CDC Consumer (brokers: {}, topics: {:?})",
            cdc_config.brokers,
            cdc_config.topics
        );

        match CdcConsumer::new(cdc_config) {
            Ok(consumer) => {
                tokio::spawn(async move {
                    tracing::info!("CDC Consumer task started");
                    if let Err(e) = consumer.run().await {
                        tracing::error!("CDC Consumer failed: {:?}", e);
                    }
                });
            }
            Err(e) => {
                tracing::error!("Failed to create CDC Consumer: {:?}", e);
                tracing::warn!("Analytics service will run without CDC Consumer");
            }
        }
    } else {
        tracing::info!("CDC_CONSUMER_ENABLED=false - skipping CDC consumer start");
    }

    // Compute HTTP and gRPC ports
    let http_port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8000);
    let grpc_port: u16 = http_port + 1000;

    tracing::info!("HTTP port: {}, gRPC port: {}", http_port, grpc_port);

    // Start gRPC server in background on http_port + 1000
    let grpc_addr: std::net::SocketAddr = format!("0.0.0.0:{}", grpc_port)
        .parse()
        .expect("Failed to parse gRPC address - this is a configuration error and should never happen with valid port number");
    let app_state_clone = Arc::clone(&app_state);

    tokio::spawn(async move {
        let (mut health, health_service) = health_reporter();
        health
            .set_serving::<EventsServiceServer<analytics_service::grpc::EventsServiceImpl>>()
            .await;

        // Server-side correlation-id extractor interceptor
        fn server_interceptor(
            mut req: tonic::Request<()>,
        ) -> Result<tonic::Request<()>, tonic::Status> {
            if let Some(val) = req.metadata().get("correlation-id") {
                if let Ok(s) = val.to_str() {
                    let correlation_id = s.to_string();
                    req.extensions_mut().insert::<String>(correlation_id);
                }
            }
            Ok(req)
        }

        // ✅ P0-1: Load mTLS configuration
        let tls_config = match grpc_tls::GrpcServerTlsConfig::from_env() {
            Ok(config) => {
                tracing::info!("mTLS enabled - service-to-service authentication active");
                Some(config)
            }
            Err(e) => {
                tracing::warn!("mTLS disabled - TLS config not found: {}. Using development mode for testing only.", e);
                let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
                if app_env != "production" {
                    tracing::info!("Development/Staging mode: Starting without TLS (NOT FOR PRODUCTION)");
                    None
                } else {
                    tracing::error!("Production requires mTLS - GRPC_SERVER_CERT_PATH must be set");
                    return;
                }
            }
        };

        // Build server with optional TLS
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

        let svc = analytics_service::grpc::EventsServiceImpl::new(app_state_clone);

        tracing::info!("Starting gRPC server on {}", grpc_addr);

        if let Err(e) = server_builder
            .add_service(health_service)
            .add_service(EventsServiceServer::with_interceptor(
                svc,
                server_interceptor,
            ))
            .serve(grpc_addr)
            .await
        {
            tracing::error!("analytics-service gRPC server error: {}", e);
        }
    });

    // Admin helpers for outbox operations
    async fn outbox_stats(publisher: web::Data<Arc<OutboxPublisher>>) -> HttpResponse {
        match publisher.record_pending_metrics().await {
            Ok(_) => HttpResponse::Ok().json(serde_json::json!({
                "pending_count": publisher.metrics.pending.get(),
                "oldest_pending_age_seconds": publisher.metrics.oldest_pending_age_seconds.get(),
                "published_total": publisher.metrics.published.get(),
            })),
            Err(e) => HttpResponse::InternalServerError().body(format!("error: {}", e)),
        }
    }

    #[derive(serde::Deserialize)]
    struct ReplaySinceQuery {
        ts: String,
    }

    async fn outbox_replay_since(
        publisher: web::Data<Arc<OutboxPublisher>>,
        query: web::Query<ReplaySinceQuery>,
    ) -> HttpResponse {
        match DateTime::parse_from_rfc3339(&query.ts).map(|dt| dt.with_timezone(&Utc)) {
            Ok(ts) => match publisher.replay_since(ts).await {
                Ok(count) => HttpResponse::Ok().json(serde_json::json!({
                    "replayed": count,
                    "since": query.ts,
                })),
                Err(e) => HttpResponse::InternalServerError().body(format!("error: {}", e)),
            },
            Err(e) => HttpResponse::BadRequest().body(format!("invalid ts: {}", e)),
        }
    }

    #[derive(serde::Deserialize)]
    struct ReplayRangeQuery {
        from_id: Uuid,
        to_id: Uuid,
    }

    async fn outbox_replay_range(
        publisher: web::Data<Arc<OutboxPublisher>>,
        query: web::Query<ReplayRangeQuery>,
    ) -> HttpResponse {
        match publisher.replay_range(query.from_id, query.to_id).await {
            Ok(count) => HttpResponse::Ok().json(serde_json::json!({
                "replayed": count,
                "from_id": query.from_id,
                "to_id": query.to_id,
            })),
            Err(e) => HttpResponse::InternalServerError().body(format!("error: {}", e)),
        }
    }

    // Start HTTP server
    tracing::info!("Starting HTTP server on 0.0.0.0:{}", http_port);

    let admin_outbox = outbox_publisher.clone();

    HttpServer::new(move || {
        let mut app = App::new()
            .route("/health", web::get().to(|| async { "OK" }))
            .route("/ready", web::get().to(|| async { "READY" }));

        if let Some(publisher) = admin_outbox.clone() {
            app = app
                .app_data(web::Data::new(publisher))
                .route("/admin/outbox/stats", web::get().to(outbox_stats))
                .route(
                    "/admin/outbox/replay_since",
                    web::post().to(outbox_replay_since),
                )
                .route(
                    "/admin/outbox/replay_range",
                    web::post().to(outbox_replay_range),
                );
        }

        app
    })
    .bind(("0.0.0.0", http_port))
    .context("Failed to bind HTTP server")?
    .run()
    .await
    .context("HTTP server error")
}
