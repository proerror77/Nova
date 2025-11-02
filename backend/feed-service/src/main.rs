mod openapi;

use actix_web::{dev::Service, web, App, HttpServer};
use std::io;
use std::sync::Arc;
use std::time::Instant;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use utoipa_swagger_ui::SwaggerUi;

use rdkafka::config::ClientConfig;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::Message;
use recommendation_service::config::Config;
use recommendation_service::handlers::{
    get_model_info, get_recommendations, rank_candidates, semantic_search,
    RecommendationHandlerState,
};
use recommendation_service::services::{RecommendationEventConsumer, RecommendationServiceV2};
use serde_json::from_slice;
use tracing::{error, info, warn};

async fn openapi_json(doc: web::Data<utoipa::openapi::OpenApi>) -> actix_web::HttpResponse {
    let body = serde_json::to_string(&*doc)
        .expect("Failed to serialize OpenAPI document for feed-service");

    actix_web::HttpResponse::Ok()
        .content_type("application/json")
        .body(body)
}

/// Start Kafka consumer for recommendation events
async fn start_kafka_consumer(
    service: Arc<RecommendationServiceV2>,
    config: &Config,
) -> Result<(), Box<dyn std::error::Error>> {
    info!("Starting Kafka consumer for recommendation events");

    // Create Kafka consumer with configuration
    let consumer: StreamConsumer = ClientConfig::new()
        .set("bootstrap.servers", &config.kafka.bootstrap_servers)
        .set("group.id", "recommendation-service-group")
        .set("auto.offset.reset", "earliest")
        .set("enable.auto.commit", "true")
        .set("auto.commit.interval.ms", "5000")
        .set("session.timeout.ms", "10000")
        .create()?;

    // Subscribe to recommendation event topics
    let topics = [
        "recommendations.model_updates",
        "recommendations.feedback",
        "experiments.config",
    ];
    consumer.subscribe(&topics)?;
    info!("Subscribed to topics: {:?}", topics);

    // Create recommendation event consumer for batch processing
    let mut event_consumer = RecommendationEventConsumer::new(Arc::clone(&service));

    // Periodic flush interval: 5 seconds
    let mut flush_interval = tokio::time::interval(tokio::time::Duration::from_secs(5));

    // Consume messages from Kafka with periodic flushing
    loop {
        tokio::select! {
            // Handle incoming Kafka messages
            msg_result = consumer.recv() => {
                match msg_result {
                    Ok(msg) => {
                        // Parse message payload as RecommendationKafkaEvent
                        if let Some(payload) = msg.payload() {
                            match from_slice::<recommendation_service::services::RecommendationKafkaEvent>(
                                payload,
                            ) {
                                Ok(event) => {
                                    // Process event through consumer
                                    if let Err(e) = event_consumer.handle_event(event).await {
                                        error!("Failed to handle recommendation event: {:?}", e);
                                        // Continue processing next event
                                    }
                                }
                                Err(e) => {
                                    warn!("Failed to deserialize Kafka message: {:?}", e);
                                }
                            }
                        }
                    }
                    Err(e) => {
                        error!("Kafka consumer error: {:?}", e);
                        // Implement exponential backoff or circuit breaker here
                        tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
                    }
                }
            }
            // Handle periodic flush
            _ = flush_interval.tick() => {
                if let Err(e) = event_consumer.flush().await {
                    error!("Failed to flush event batch: {:?}", e);
                }
            }
        }
    }
}

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

    // Load configuration
    let config = Config::from_env().expect("Failed to load configuration");

    tracing::info!(
        "Starting recommendation-service v{}",
        env!("CARGO_PKG_VERSION")
    );
    tracing::info!("Environment: {}", config.app.env);

    // Initialize database
    let db_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(config.database.max_connections)
        .connect(&config.database.url)
        .await
        .expect("Failed to create database pool");

    let db_pool = web::Data::new(db_pool.clone());

    // Initialize recommendation service
    let rec_config = recommendation_service::services::RecommendationConfig {
        collaborative_model_path: config.recommendation.collaborative_model_path.clone(),
        content_model_path: config.recommendation.content_model_path.clone(),
        onnx_model_path: config.recommendation.onnx_model_path.clone(),
        hybrid_weights: recommendation_service::services::HybridWeights::balanced(),
        enable_ab_testing: config.recommendation.enable_ab_testing,
    };

    let recommendation_svc =
        match RecommendationServiceV2::new(rec_config, db_pool.get_ref().clone()).await {
            Ok(service) => {
                tracing::info!("Recommendation service initialized successfully");
                Arc::new(service)
            }
            Err(e) => {
                tracing::error!("Failed to initialize recommendation service: {:?}", e);
                // Continue without recommendation service (fallback to v1.0)
                // For now, we'll still fail startup since this is critical
                return Err(io::Error::new(
                    io::ErrorKind::Other,
                    format!("Failed to initialize recommendation service: {:?}", e),
                ));
            }
        };

    let rec_handler_state = web::Data::new(RecommendationHandlerState {
        service: Arc::clone(&recommendation_svc),
    });

    // Start Kafka consumer in background task
    let kafka_svc = Arc::clone(&recommendation_svc);
    let kafka_config = config.clone();
    tokio::spawn(async move {
        if let Err(e) = start_kafka_consumer(kafka_svc, &kafka_config).await {
            error!("Kafka consumer failed: {:?}", e);
        }
    });
    info!("Kafka consumer task spawned");

    // TODO: Start gRPC server for RecommendationService in addition to HTTP server

    // Start HTTP server
    let http_server = HttpServer::new(move || {
        let openapi_doc = openapi::doc();

        App::new()
            .app_data(web::Data::new(openapi_doc.clone()))
            .service(
                SwaggerUi::new("/swagger-ui/{_:.*}")
                    .url("/api/v1/openapi.json", openapi_doc.clone()),
            )
            .route("/api/v1/openapi.json", web::get().to(openapi_json))
            .app_data(db_pool.clone())
            .app_data(rec_handler_state.clone())
            .route("/health", web::get().to(|| async { "OK" }))
            .route(
                "/metrics",
                web::get().to(recommendation_service::metrics::serve_metrics),
            )
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
                            recommendation_service::metrics::observe_http_request(
                                &method,
                                &path,
                                res.status().as_u16(),
                                start.elapsed(),
                            );
                            Ok(res)
                        }
                        Err(err) => {
                            recommendation_service::metrics::observe_http_request(
                                &method,
                                &path,
                                500,
                                start.elapsed(),
                            );
                            Err(err)
                        }
                    }
                }
            })
            .service(get_recommendations)
            .service(get_model_info)
            .service(rank_candidates)
            .service(semantic_search)
    })
    .bind(format!("0.0.0.0:{}", config.app.port))?
    .run()
    .await;

    http_server
}
