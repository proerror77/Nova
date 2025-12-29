//! Thumbnail Worker - Kafka consumer for real-time thumbnail generation
//!
//! This worker listens for media upload events from Kafka and generates thumbnails
//! using GCS for storage. It also performs periodic batch processing for any missed images.
//!
//! Environment variables:
//! - GCS_BUCKET: GCS bucket name (e.g., "nova-media-staging")
//! - GCS_SERVICE_ACCOUNT_JSON: Service account JSON content (base64 or raw)
//! - GCS_SERVICE_ACCOUNT_JSON_PATH: Alternative: path to service account JSON file
//! - CONTENT_DATABASE_URL: PostgreSQL URL for media DB (uploads/media_files tables in nova_media)
//! - KAFKA_BROKERS: Kafka broker addresses
//! - KAFKA_TOPIC: Topic to consume (default: "media_events")
//! - KAFKA_GROUP_ID: Consumer group ID (default: "thumbnail-worker")
//! - THUMB_MAX_DIMENSION: Max thumbnail dimension (default: 600)
//! - THUMB_QUALITY: JPEG quality 0-100 (default: 85)
//! - BATCH_INTERVAL_SECS: Batch processing interval (default: 300)

use media_service::error::{AppError, Result};
use media_service::services::thumbnail::{
    GcsClient, ThumbnailConfig, ThumbnailConsumer, ThumbnailConsumerConfig, ThumbnailService,
    ThumbnailServiceConfig,
};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::watch;
use tracing::{error, info, warn};

#[derive(Debug)]
struct WorkerConfig {
    gcs_bucket: String,
    gcs_service_account_json: Option<String>,
    gcs_service_account_json_path: Option<String>,
    content_db_url: String,
    kafka_brokers: String,
    kafka_topic: String,
    kafka_group_id: String,
    thumb_max_dimension: u32,
    thumb_quality: u8,
    batch_interval_secs: u64,
}

impl WorkerConfig {
    fn from_env() -> Result<Self> {
        let gcs_bucket = std::env::var("GCS_BUCKET")
            .map_err(|_| AppError::Internal("GCS_BUCKET not set".to_string()))?;

        let gcs_service_account_json = std::env::var("GCS_SERVICE_ACCOUNT_JSON").ok();
        let gcs_service_account_json_path = std::env::var("GCS_SERVICE_ACCOUNT_JSON_PATH").ok();

        if gcs_service_account_json.is_none() && gcs_service_account_json_path.is_none() {
            return Err(AppError::Internal(
                "Either GCS_SERVICE_ACCOUNT_JSON or GCS_SERVICE_ACCOUNT_JSON_PATH must be set"
                    .to_string(),
            ));
        }

        let content_db_url = std::env::var("CONTENT_DATABASE_URL")
            .or_else(|_| std::env::var("DATABASE_URL"))
            .map_err(|_| {
                AppError::Internal("CONTENT_DATABASE_URL or DATABASE_URL not set".to_string())
            })?;

        Ok(Self {
            gcs_bucket,
            gcs_service_account_json,
            gcs_service_account_json_path,
            content_db_url,
            kafka_brokers: std::env::var("KAFKA_BROKERS")
                .unwrap_or_else(|_| "localhost:9092".to_string()),
            kafka_topic: std::env::var("KAFKA_TOPIC")
                .unwrap_or_else(|_| "media_events".to_string()),
            kafka_group_id: std::env::var("KAFKA_GROUP_ID")
                .unwrap_or_else(|_| "thumbnail-worker".to_string()),
            thumb_max_dimension: std::env::var("THUMB_MAX_DIMENSION")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(600),
            thumb_quality: std::env::var("THUMB_QUALITY")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(85),
            batch_interval_secs: std::env::var("BATCH_INTERVAL_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(300),
        })
    }

    /// Load service account JSON from env var or file path
    fn load_service_account_json(&self) -> Result<String> {
        // First try the inline JSON
        if let Some(ref json) = self.gcs_service_account_json {
            // Check if it's base64 encoded
            if !json.trim().starts_with('{') {
                use base64::Engine;
                let decoded = base64::engine::general_purpose::STANDARD
                    .decode(json.trim())
                    .map_err(|e| {
                        AppError::Internal(format!("Failed to decode base64 SA JSON: {e}"))
                    })?;
                return String::from_utf8(decoded)
                    .map_err(|e| AppError::Internal(format!("Invalid UTF-8 in SA JSON: {e}")));
            }
            return Ok(json.clone());
        }

        // Try loading from file path
        if let Some(ref path) = self.gcs_service_account_json_path {
            return std::fs::read_to_string(path)
                .map_err(|e| AppError::Internal(format!("Failed to read SA JSON file: {e}")));
        }

        Err(AppError::Internal(
            "No service account JSON configured".to_string(),
        ))
    }
}

#[tokio::main]
async fn main() -> std::result::Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("thumb_worker=info".parse().expect("valid directive"))
                .add_directive("media_service=info".parse().expect("valid directive")),
        )
        .init();

    info!("Starting Thumbnail Worker");

    // Load configuration
    dotenvy::dotenv().ok();
    let config = WorkerConfig::from_env().map_err(|e| format!("{e}"))?;
    info!(
        bucket = %config.gcs_bucket,
        kafka_brokers = %config.kafka_brokers,
        kafka_topic = %config.kafka_topic,
        "Configuration loaded"
    );

    // Load service account JSON
    let sa_json = config
        .load_service_account_json()
        .map_err(|e| format!("{e}"))?;

    // Create GCS client
    let gcs_client = Arc::new(
        GcsClient::new(&sa_json, &config.gcs_bucket, "storage.googleapis.com")
            .map_err(|e| format!("{e}"))?,
    );
    info!("GCS client initialized");

    // Create thumbnail service
    let service_config = ThumbnailServiceConfig {
        thumbnail: ThumbnailConfig {
            max_dimension: config.thumb_max_dimension,
            quality: config.thumb_quality,
        },
        batch_size: 20,
        content_db_url: config.content_db_url.clone(),
    };
    let thumbnail_service = Arc::new(
        ThumbnailService::new(gcs_client.clone(), service_config)
            .await
            .map_err(|e| format!("{e}"))?,
    );
    info!("Thumbnail service initialized");

    // Setup shutdown signal
    let (shutdown_tx, shutdown_rx) = watch::channel(false);

    // Handle SIGTERM/SIGINT for graceful shutdown
    let shutdown_tx_clone = shutdown_tx.clone();
    tokio::spawn(async move {
        tokio::signal::ctrl_c()
            .await
            .expect("Failed to listen for ctrl+c");
        info!("Shutdown signal received");
        let _ = shutdown_tx_clone.send(true);
    });

    // Create Kafka consumer
    let consumer_config = ThumbnailConsumerConfig {
        brokers: config.kafka_brokers.clone(),
        topic: config.kafka_topic.clone(),
        group_id: config.kafka_group_id.clone(),
    };
    let mut consumer = ThumbnailConsumer::new(
        &consumer_config,
        thumbnail_service.clone(),
        shutdown_rx.clone(),
    )
    .map_err(|e| format!("{e}"))?;
    info!("Kafka consumer initialized");

    // Spawn batch processing task
    let batch_service = thumbnail_service.clone();
    let mut batch_shutdown_rx = shutdown_rx.clone();
    let batch_interval = Duration::from_secs(config.batch_interval_secs);

    let batch_handle = tokio::spawn(async move {
        info!(
            interval_secs = config.batch_interval_secs,
            "Starting batch processor"
        );

        // Initial batch run on startup
        match batch_service.process_pending().await {
            Ok(count) => info!(processed = count, "Initial batch processing completed"),
            Err(e) => error!(error = %e, "Initial batch processing failed"),
        }

        let mut interval = tokio::time::interval(batch_interval);
        interval.tick().await; // Skip first tick (we just ran)

        loop {
            tokio::select! {
                _ = batch_shutdown_rx.changed() => {
                    if *batch_shutdown_rx.borrow() {
                        info!("Batch processor shutting down");
                        break;
                    }
                }
                _ = interval.tick() => {
                    match batch_service.process_pending().await {
                        Ok(count) => {
                            if count > 0 {
                                info!(processed = count, "Batch processing completed");
                            }
                        }
                        Err(e) => {
                            warn!(error = %e, "Batch processing failed, will retry next interval");
                        }
                    }
                }
            }
        }
    });

    // Run the Kafka consumer (blocks until shutdown)
    info!("Starting Kafka consumer loop");
    if let Err(e) = consumer.run().await {
        error!(error = %e, "Consumer error");
    }

    // Wait for batch processor to finish
    info!("Waiting for batch processor to finish");
    let _ = batch_handle.await;

    info!("Thumbnail Worker stopped");
    Ok(())
}
