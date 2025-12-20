use actix_web::{middleware, web, App, HttpServer};
use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use notification_service::{
    handlers::{
        devices::register_routes as register_devices,
        notifications::register_routes as register_notifications,
        preferences::register_routes as register_preferences,
        websocket::register_routes as register_websocket,
    },
    metrics,
    services::{APNsClient, FCMClient, KafkaNotificationConsumer, RedisDeduplicator, ServiceAccountKey},
    ConnectionManager, NotificationService,
};
use std::io;
use std::sync::Arc;
use tonic::transport::Server as GrpcServer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting notification service");

    // Initialize database
    let db_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://user:password@localhost/nova".to_string());

    let mut cfg = DbPoolConfig::for_service("notification-service");
    if cfg.database_url.is_empty() {
        cfg.database_url = db_url.clone();
    }
    if cfg.max_connections < 20 {
        cfg.max_connections = 20;
    }
    let db_pool = match create_pg_pool(cfg).await {
        Ok(pool) => {
            tracing::info!("Successfully connected to database");
            pool
        }
        Err(e) => {
            tracing::warn!(
                "Failed to connect to database: {}. Running in offline mode",
                e
            );
            tracing::info!("Some features will not work without database connection");
            return Err(io::Error::other("Database connection failed"));
        }
    };

    // Initialize FCM client from environment
    // FCM_CREDENTIALS should point to a Firebase service account JSON file
    let fcm_client: Option<Arc<FCMClient>> = if let Ok(credentials_path) =
        std::env::var("FCM_CREDENTIALS")
    {
        match std::fs::read_to_string(&credentials_path) {
            Ok(json_content) => match serde_json::from_str::<ServiceAccountKey>(&json_content) {
                Ok(key) => {
                    let project_id = key.project_id.clone();
                    let client = FCMClient::new(project_id.clone(), key);
                    tracing::info!(
                        "FCM client initialized for project {} from {}",
                        project_id,
                        credentials_path
                    );
                    Some(Arc::new(client))
                }
                Err(e) => {
                    tracing::warn!(
                        "Failed to parse FCM credentials from {}: {}",
                        credentials_path,
                        e
                    );
                    None
                }
            },
            Err(e) => {
                tracing::warn!(
                    "Failed to read FCM credentials file {}: {}",
                    credentials_path,
                    e
                );
                None
            }
        }
    } else {
        tracing::warn!("FCM_CREDENTIALS not set - FCM push notifications disabled");
        None
    };

    // Initialize APNs client from environment
    let apns_client: Option<Arc<APNsClient>> =
        if let Ok(cert_path) = std::env::var("APNS_CERTIFICATE_PATH") {
            let key_id = std::env::var("APNS_KEY_ID").unwrap_or_default();
            let team_id = std::env::var("APNS_TEAM_ID").unwrap_or_default();
            let is_production = std::env::var("APNS_PRODUCTION")
                .map(|v| v.to_lowercase() == "true" || v == "1")
                .unwrap_or(false);

            if key_id.is_empty() || team_id.is_empty() {
                tracing::warn!(
                    "APNS_KEY_ID or APNS_TEAM_ID not set - APNs push notifications disabled"
                );
                None
            } else {
                let client = APNsClient::new(
                    cert_path.clone(),
                    String::new(), // key_path - not used in wrapper
                    team_id,
                    key_id,
                    is_production,
                );
                tracing::info!(
                    "APNs client initialized (production={}) from {}",
                    is_production,
                    cert_path
                );
                Some(Arc::new(client))
            }
        } else {
            tracing::warn!("APNS_CERTIFICATE_PATH not set - APNs push notifications disabled");
            None
        };

    // Initialize Redis pool for distributed deduplication
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://localhost:6379".to_string());
    let redis_dedup_ttl_secs: u64 = std::env::var("REDIS_DEDUP_TTL_SECS")
        .unwrap_or_else(|_| "120".to_string())
        .parse()
        .unwrap_or(120);

    let redis_pool = match redis_utils::RedisPool::connect(&redis_url, None).await {
        Ok(pool) => {
            tracing::info!("Redis pool connected for deduplication (TTL: {}s)", redis_dedup_ttl_secs);
            Some(pool)
        }
        Err(e) => {
            tracing::warn!(
                "Failed to connect to Redis: {}. Deduplication will be disabled.",
                e
            );
            None
        }
    };

    let notification_service = Arc::new(NotificationService::new(
        db_pool.clone(),
        fcm_client.clone(),
        apns_client.clone(),
    ));

    // Start Kafka consumer in background for event-driven notifications
    let kafka_notification_service = notification_service.clone();
    let kafka_broker =
        std::env::var("KAFKA_BROKER").unwrap_or_else(|_| "localhost:9092".to_string());
    let kafka_enabled = std::env::var("KAFKA_ENABLED")
        .map(|v| v.to_lowercase() == "true" || v == "1")
        .unwrap_or(true);

    if kafka_enabled {
        // Create deduplicator if Redis is available
        let deduplicator = redis_pool.as_ref().map(|pool| {
            RedisDeduplicator::new(pool.manager(), redis_dedup_ttl_secs)
        });

        tokio::spawn(async move {
            let mut consumer =
                KafkaNotificationConsumer::new(kafka_broker.clone(), "notifications".to_string());

            // Attach Redis deduplicator if available
            if let Some(dedup) = deduplicator {
                consumer = consumer.with_deduplicator(dedup);
                tracing::info!(
                    "Kafka consumer with Redis deduplication (broker: {}, dedup_ttl: {}s)",
                    kafka_broker,
                    redis_dedup_ttl_secs
                );
            } else {
                tracing::warn!(
                    "Kafka consumer without deduplication - Redis not available (broker: {})",
                    kafka_broker
                );
            }

            if let Err(e) = consumer.start(kafka_notification_service).await {
                tracing::error!("Kafka consumer error: {}", e);
            }
        });
    } else {
        tracing::info!("Kafka consumer disabled (KAFKA_ENABLED=false)");
    }

    // Initialize WebSocket connection manager
    let connection_manager = Arc::new(ConnectionManager::new());
    tracing::info!("WebSocket connection manager initialized");

    // Support both PORT (legacy) and HTTP_PORT/SERVER_PORT (k8s) environment variables
    let http_port = std::env::var("HTTP_PORT")
        .or_else(|_| std::env::var("SERVER_PORT"))
        .or_else(|_| std::env::var("PORT"))
        .unwrap_or_else(|_| "8000".to_string());
    let addr = format!("0.0.0.0:{}", http_port);

    tracing::info!("Starting HTTP server on {}", addr);

    // Support GRPC_PORT env var, fallback to HTTP port + 1000
    let http_port_u16 = http_port.parse::<u16>().unwrap_or(8000);
    let grpc_port = std::env::var("GRPC_PORT")
        .ok()
        .and_then(|p| p.parse::<u16>().ok())
        .unwrap_or(http_port_u16 + 1000);
    let grpc_addr: std::net::SocketAddr = format!("0.0.0.0:{}", grpc_port)
        .parse()
        .expect("Invalid gRPC address");

    let grpc_db_pool = db_pool.clone();
    let grpc_notification_service = notification_service.clone();
    let grpc_fcm_client = fcm_client.clone();
    let grpc_apns_client = apns_client.clone();
    tokio::spawn(async move {
        use notification_service::grpc::{
            nova::notification_service::v2::notification_service_server::NotificationServiceServer,
            NotificationServiceImpl,
        };
        use notification_service::services::PushSender;
        use tonic_health::server::health_reporter;

        // Server-side correlation-id extractor interceptor
        fn server_interceptor(
            mut req: tonic::Request<()>,
        ) -> Result<tonic::Request<()>, tonic::Status> {
            let correlation_id = req
                .metadata()
                .get("correlation-id")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string());

            if let Some(id) = correlation_id {
                req.extensions_mut().insert::<String>(id);
            }
            Ok(req)
        }

        // ✅ P1: Create gRPC health reporter for Kubernetes probes
        let (mut health_reporter, health_service) = health_reporter();
        health_reporter
            .set_serving::<NotificationServiceServer<NotificationServiceImpl>>()
            .await;
        tracing::info!("gRPC health check enabled (tonic-health protocol)");

        let push_sender = Arc::new(PushSender::new(
            grpc_db_pool.clone(),
            grpc_fcm_client,
            grpc_apns_client,
        ));
        let svc =
            NotificationServiceImpl::new(grpc_db_pool, grpc_notification_service, push_sender);

        // ✅ P0: Load mTLS configuration
        //
        // In production, missing TLS configuration is a hard error.
        // In non-production environments (e.g. staging, development),
        // we allow starting without TLS to keep the environment usable
        // while mTLS is being rolled out.
        let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
        let is_production_env = app_env.eq_ignore_ascii_case("production");

        let tls_config = match grpc_tls::GrpcServerTlsConfig::from_env() {
            Ok(config) => {
                tracing::info!(
                    "mTLS enabled - service-to-service authentication active (env = {})",
                    app_env
                );
                Some(config)
            }
            Err(e) => {
                if is_production_env {
                    tracing::error!(
                        "Production requires mTLS - GRPC_SERVER_CERT_PATH must be set: {}",
                        e
                    );
                    return;
                }

                tracing::warn!(
                    "mTLS disabled - TLS config not found for env '{}': {}. \
                     Starting gRPC server without TLS (non-production only).",
                    app_env,
                    e
                );
                None
            }
        };

        // ✅ P0: Build server with optional TLS
        let mut server_builder = GrpcServer::builder();

        if let Some(tls_cfg) = tls_config {
            match tls_cfg.build_server_tls() {
                Ok(server_tls) => match GrpcServer::builder().tls_config(server_tls) {
                    Ok(builder) => {
                        server_builder = builder;
                        tracing::info!("gRPC server TLS configured successfully");
                    }
                    Err(e) => {
                        if is_production_env {
                            tracing::error!(
                                "Failed to configure TLS on gRPC server in production: {}",
                                e
                            );
                            return;
                        }

                        tracing::warn!(
                            "Failed to configure TLS on gRPC server in env '{}': {}. \
                             Falling back to non-TLS for this environment.",
                            app_env,
                            e
                        );
                    }
                },
                Err(e) => {
                    if is_production_env {
                        tracing::error!("Failed to build server TLS config in production: {}", e);
                        return;
                    }

                    tracing::warn!(
                        "Failed to build server TLS config in env '{}': {}. \
                         Falling back to non-TLS for this environment.",
                        app_env,
                        e
                    );
                }
            }
        }

        tracing::info!("gRPC server listening on {}", grpc_addr);
        if let Err(e) = server_builder
            .add_service(health_service) // ✅ P1: Add health service first
            .add_service(NotificationServiceServer::with_interceptor(
                svc,
                server_interceptor,
            ))
            .serve(grpc_addr)
            .await
        {
            tracing::error!("gRPC server error: {}", e);
        }
    });

    // Start HTTP server
    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(notification_service.clone()))
            .app_data(web::Data::new(connection_manager.clone()))
            .wrap(middleware::Logger::default())
            .wrap(metrics::MetricsMiddleware)
            .route("/health", web::get().to(|| async { "OK" }))
            .route(
                "/metrics",
                web::get().to(notification_service::metrics::serve_metrics),
            )
            .route("/", web::get().to(|| async { "Notification Service v1.0" }))
            .configure(|cfg| {
                register_notifications(cfg);
                register_devices(cfg);
                register_preferences(cfg);
                register_websocket(cfg);
            })
    })
    .bind(&addr)?
    .run()
    .await
}
