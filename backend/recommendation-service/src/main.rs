use actix_web::{web, App, HttpServer};
use std::io;
use std::sync::Arc;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use recommendation_service::config::Config;
use recommendation_service::handlers::{
    get_recommendations, get_model_info, rank_candidates, RecommendationHandlerState,
};
use recommendation_service::services::RecommendationServiceV2;

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

    let recommendation_svc = match RecommendationServiceV2::new(rec_config, db_pool.get_ref().clone()).await {
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
        service: recommendation_svc,
    });

    // TODO: Start gRPC server for RecommendationService in addition to HTTP server

    // Start HTTP server
    let http_server = HttpServer::new(move || {
        App::new()
            .app_data(db_pool.clone())
            .app_data(rec_handler_state.clone())
            .route("/health", web::get().to(|| async { "OK" }))
            .service(get_recommendations)
            .service(get_model_info)
            .service(rank_candidates)
    })
    .bind(format!("0.0.0.0:{}", config.app.port))?
    .run()
    .await;

    http_server
}
