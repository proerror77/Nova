use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use anyhow::{Context, Result};
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use std::str::FromStr;
use std::sync::Arc;
use std::time::Duration;
use tokio::task::JoinSet;
use tonic::transport::Server;
use tracing::info;
use uuid::Uuid;

use chrono::{DateTime, Utc};
use grpc_clients::{config::GrpcConfig as GrpcClientConfig, GrpcClientPool};

mod config;
mod consumers;
mod domain;
mod error;
mod grpc;
mod handlers;
mod repositories;
mod repository;
mod services;
mod workers;

use config::Config;
use consumers::content_events::{ContentEventsConsumer, ContentEventsConsumerConfig};
use grpc::server_v2::{
    social::social_service_server::SocialServiceServer, AppState, SocialServiceImpl,
};
use services::{CounterService, KafkaEventProducerConfig, SocialEventProducer};
use transactional_outbox::SqlxOutboxRepository;
use workers::{graph_sync::GraphSyncConsumer, outbox_worker, redis_health};

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

async fn outbox_stats(repo: web::Data<Arc<SqlxOutboxRepository>>) -> impl Responder {
    match repo.pending_stats().await {
        Ok((count, age)) => HttpResponse::Ok().json(serde_json::json!({
            "pending_count": count,
            "oldest_pending_age_seconds": age,
        })),
        Err(e) => HttpResponse::InternalServerError().body(format!("error: {}", e)),
    }
}

#[derive(serde::Deserialize)]
struct ReplaySinceQuery {
    /// RFC3339 timestamp
    ts: String,
}

async fn outbox_replay_since(
    repo: web::Data<Arc<SqlxOutboxRepository>>,
    query: web::Query<ReplaySinceQuery>,
) -> impl Responder {
    match DateTime::parse_from_rfc3339(&query.ts).map(|dt| dt.with_timezone(&Utc)) {
        Ok(ts) => match repo.replay_since(ts).await {
            Ok(affected) => HttpResponse::Ok().json(serde_json::json!({
                "replayed": affected,
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
    repo: web::Data<Arc<SqlxOutboxRepository>>,
    query: web::Query<ReplayRangeQuery>,
) -> impl Responder {
    match repo.replay_range(query.from_id, query.to_id).await {
        Ok(affected) => HttpResponse::Ok().json(serde_json::json!({
            "replayed": affected,
            "from_id": query.from_id,
            "to_id": query.to_id,
        })),
        Err(e) => HttpResponse::InternalServerError().body(format!("error: {}", e)),
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize rustls crypto provider
    if let Err(err) = rustls::crypto::aws_lc_rs::default_provider().install_default() {
        eprintln!("ERROR: failed to install rustls crypto provider: {:?}", err);
        return Err(anyhow::anyhow!("failed to install rustls crypto provider"));
    }

    // Initialize tracing
    tracing_subscriber::fmt::init();

    info!("🔧 Starting social-service");

    // Load configuration
    let config = Config::from_env().context("Failed to load configuration")?;
    info!(
        "✅ Configuration loaded: env={}, http_port={}, grpc_port={}",
        config.app.env, config.app.http_port, config.grpc.port
    );

    // Initialize database pool with prepared statement caching disabled for PgBouncer compatibility
    let connect_options = PgConnectOptions::from_str(&config.database.url)
        .context("Failed to parse DATABASE_URL")?
        .statement_cache_capacity(0); // Disable prepared statement caching for PgBouncer transaction mode

    let pg_pool = PgPoolOptions::new()
        .max_connections(config.database.max_connections)
        .min_connections(config.database.min_connections)
        .acquire_timeout(Duration::from_secs(10))
        .idle_timeout(Duration::from_secs(600))
        .max_lifetime(Duration::from_secs(1800))
        .connect_with(connect_options)
        .await
        .context("Failed to connect to database")?;

    // Verify database connection
    sqlx::query("SELECT 1")
        .execute(&pg_pool)
        .await
        .context("Failed to verify database connection")?;
    info!("✅ Database pool created and verified");

    // Run database migrations
    sqlx::migrate!("./migrations")
        .run(&pg_pool)
        .await
        .context("Failed to run database migrations")?;
    info!("✅ Database migrations completed");

    // Initialize Redis connection
    let redis_client =
        redis::Client::open(config.redis.url.as_str()).context("Failed to create Redis client")?;
    let redis_conn = redis::aio::ConnectionManager::new(redis_client)
        .await
        .context("Failed to connect to Redis")?;
    info!("✅ Redis connection established");

    // Initialize Outbox repository
    let outbox_repo = Arc::new(SqlxOutboxRepository::new(pg_pool.clone()));
    info!("✅ Outbox repository initialized");

    // Initialize Counter service
    let counter_service = CounterService::new(redis_conn.clone(), pg_pool.clone());
    info!("✅ Counter service initialized");

    // Start Redis health check background job to prevent broken pipe errors
    let health_counter_service = Arc::new(counter_service.clone());
    tokio::spawn(async move {
        redis_health::start_redis_health_check(
            health_counter_service,
            redis_health::RedisHealthConfig::default(),
        )
        .await;
    });
    info!("✅ Redis health check background job started");

    // Initialize gRPC client for graph-service
    let grpc_cfg = GrpcClientConfig::from_env()
        .map_err(|e| anyhow::anyhow!("Failed to load gRPC client config: {}", e))?;
    let grpc_pool = Arc::new(
        GrpcClientPool::new(&grpc_cfg)
            .await
            .map_err(|e| anyhow::anyhow!("Failed to create gRPC client pool: {}", e))?,
    );
    let graph_client = grpc_pool.graph();
    info!("✅ Graph service gRPC client initialized");

    // Initialize Kafka event producer (optional)
    let event_producer = KafkaEventProducerConfig::from_env()
        .and_then(|config| {
            match SocialEventProducer::new(&config) {
                Ok(producer) => {
                    info!("✅ Kafka event producer initialized");
                    Some(producer)
                }
                Err(e) => {
                    tracing::warn!("Failed to initialize Kafka event producer: {}", e);
                    None
                }
            }
        });

    // Create AppState
    let mut app_state = AppState::new(
        pg_pool.clone(),
        counter_service,
        outbox_repo,
        graph_client,
    );
    if let Some(producer) = event_producer {
        app_state = app_state.with_event_producer(producer);
    }
    let app_state = Arc::new(app_state);
    info!("✅ AppState created");

    // gRPC server address
    let grpc_addr = format!("{}:{}", config.app.host, config.grpc.port)
        .parse()
        .context("Invalid gRPC address")?;

    // HTTP health check address
    let http_addr = format!("{}:{}", config.app.host, config.app.http_port);

    info!("🚀 Starting servers:");
    info!("  - HTTP health checks: http://{}", http_addr);
    info!("  - gRPC service: grpc://{}", grpc_addr);

    let mut join_set = JoinSet::new();

    let outbox_admin_enabled = std::env::var("SOCIAL_OUTBOX_ADMIN_ENABLED")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(true);

    // Spawn HTTP server task
    let http_outbox_repo = app_state.outbox_repo.clone();
    let http_server = HttpServer::new(move || {
        let mut app = App::new()
            .route("/health", web::get().to(|| async { "OK" }))
            .route("/ready", web::get().to(|| async { "READY" }));

        if outbox_admin_enabled {
            let repo_data = http_outbox_repo.clone();
            app = app
                .app_data(web::Data::new(repo_data))
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
    .bind(&http_addr)
    .context("Failed to bind HTTP server")?
    .run();

    join_set.spawn(async move {
        http_server
            .await
            .map_err(|e| anyhow::anyhow!("HTTP server error: {}", e))
    });
    info!("✅ HTTP health check server started");

    // Spawn gRPC server task
    let grpc_service = SocialServiceImpl::new(app_state.clone());
    let grpc_config = config.grpc.clone();

    join_set.spawn(async move {
        let mut server_builder = Server::builder();

        // Configure mTLS if certificates are provided
        if let (Some(cert_path), Some(key_path), Some(ca_path)) = (
            &grpc_config.server_cert_path,
            &grpc_config.server_key_path,
            &grpc_config.ca_cert_path,
        ) {
            info!("🔐 Configuring gRPC server with mTLS");

            let cert = tokio::fs::read(cert_path)
                .await
                .context("Failed to read server certificate")?;
            let key = tokio::fs::read(key_path)
                .await
                .context("Failed to read server key")?;
            let ca_cert = tokio::fs::read(ca_path)
                .await
                .context("Failed to read CA certificate")?;

            let server_identity = tonic::transport::Identity::from_pem(cert, key);
            let client_ca_cert = tonic::transport::Certificate::from_pem(ca_cert);

            let tls_config = tonic::transport::ServerTlsConfig::new()
                .identity(server_identity)
                .client_ca_root(client_ca_cert);

            server_builder = Server::builder()
                .tls_config(tls_config)
                .context("Failed to configure TLS")?;

            info!("✅ mTLS configuration applied");
        } else {
            info!("⚠️  Running gRPC server without mTLS (development mode)");
        }

        server_builder
            .add_service(SocialServiceServer::new(grpc_service))
            .serve_with_shutdown(grpc_addr, shutdown_signal())
            .await
            .map_err(|e| anyhow::anyhow!("gRPC server error: {}", e))
    });
    info!("✅ gRPC server started");

    // Start outbox worker (drains outbox -> Kafka/Noop with metrics)
    let outbox_repo_for_worker = app_state.outbox_repo.clone();
    join_set.spawn(outbox_worker::run(pg_pool.clone(), outbox_repo_for_worker));

    // Optionally start graph-sync consumer if write token is provided
    if let Ok(write_token) = std::env::var("INTERNAL_GRAPH_WRITE_TOKEN") {
        let grpc_cfg = GrpcClientConfig::from_env().map_err(|e| {
            anyhow::anyhow!("Failed to load gRPC client config for graph-sync: {}", e)
        })?;
        let grpc_pool = Arc::new(GrpcClientPool::new(&grpc_cfg).await.map_err(|e| {
            anyhow::anyhow!("Failed to create gRPC client pool for graph-sync: {}", e)
        })?);
        let graph_client = grpc_pool.graph();
        let repo = app_state.outbox_repo.clone();
        join_set.spawn(async move {
            GraphSyncConsumer::new(repo, graph_client, write_token)
                .run()
                .await;
            Ok(())
        });
        info!("✅ Graph-sync consumer started (edge upsert to graph-service)");
    } else {
        info!("Graph-sync consumer disabled: INTERNAL_GRAPH_WRITE_TOKEN not set");
    }

    // Start content events consumer to initialize post_counters on post creation
    if let Some(content_config) = ContentEventsConsumerConfig::from_env() {
        let pool_for_content = pg_pool.clone();
        join_set.spawn(async move {
            ContentEventsConsumer::new(pool_for_content, content_config)
                .run()
                .await;
            Ok(())
        });
        info!("✅ Content events consumer started (post_counters initialization)");
    } else {
        info!("Content events consumer disabled: KAFKA_BROKERS not configured");
    }

    info!("✅ All services started successfully");
    info!("🎉 social-service is running");

    // Wait for any task to complete (or fail)
    while let Some(result) = join_set.join_next().await {
        match result {
            Ok(Ok(())) => {
                info!("Task completed successfully");
            }
            Ok(Err(e)) => {
                tracing::error!("Task failed: {:#}", e);
                return Err(e);
            }
            Err(e) => {
                tracing::error!("Task panicked: {:#}", e);
                return Err(anyhow::anyhow!("Task panicked: {}", e));
            }
        }
    }

    info!("🛑 social-service shutting down");
    Ok(())
}
