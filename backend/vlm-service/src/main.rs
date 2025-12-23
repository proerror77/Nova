//! VLM Service - Main entry point
//!
//! This service provides image analysis using Google Cloud Vision API
//! and generates tags for automatic channel classification.
//!
//! # Modes
//! - `consumer` (default): Run as Kafka consumer, processing events in real-time
//! - `backfill`: Run as batch job, processing existing posts with pending VLM status

use anyhow::Result;
use std::env;
use std::sync::Arc;
use tracing::{error, info, warn};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use vlm_service::{BackfillJob, Config, GoogleVisionClient, VLMConsumer, VLMConsumerConfig, VLMProducer};

/// Service run mode
#[derive(Debug, Clone, PartialEq)]
enum RunMode {
    /// Default: Kafka consumer mode for real-time processing
    Consumer,
    /// Batch backfill mode for existing posts
    Backfill,
}

impl RunMode {
    fn from_args() -> Self {
        let args: Vec<String> = env::args().collect();

        // Check for --mode argument
        for i in 0..args.len() {
            if args[i] == "--mode" && i + 1 < args.len() {
                return match args[i + 1].as_str() {
                    "backfill" => RunMode::Backfill,
                    "consumer" => RunMode::Consumer,
                    _ => {
                        warn!("Unknown mode '{}', using default 'consumer'", args[i + 1]);
                        RunMode::Consumer
                    }
                };
            }
        }

        RunMode::Consumer
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize rustls crypto provider (required for rustls 0.23+)
    rustls::crypto::aws_lc_rs::default_provider()
        .install_default()
        .expect("Failed to install rustls crypto provider");

    // Initialize tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| {
            "vlm_service=debug,tower_http=debug,rdkafka=warn,info".into()
        }))
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Determine run mode
    let mode = RunMode::from_args();
    info!("Starting VLM Service in {:?} mode", mode);

    // Load configuration
    dotenvy::dotenv().ok();
    let config = Config::from_env().map_err(|e| {
        error!("Failed to load configuration: {}", e);
        anyhow::anyhow!("Configuration error: {}", e)
    })?;

    info!(
        "Configuration loaded: max_tags={}, min_confidence={}, max_channels={}",
        config.max_tags, config.min_tag_confidence, config.max_channels
    );

    // Initialize Google Vision client
    let vision_client = if config.use_adc {
        info!("Using Application Default Credentials for Vision API");
        Arc::new(GoogleVisionClient::with_adc())
    } else if !config.google_vision_api_key.is_empty() {
        info!("Using API key for Vision API");
        Arc::new(GoogleVisionClient::new(config.google_vision_api_key.clone()))
    } else {
        // Default to ADC if no API key is provided
        info!("No API key provided, using Application Default Credentials");
        Arc::new(GoogleVisionClient::with_adc())
    };

    info!("Google Vision client initialized (auth: {:?})", vision_client.auth_mode());

    // Run based on mode
    match mode {
        RunMode::Backfill => run_backfill_mode(config, vision_client).await,
        RunMode::Consumer => run_consumer_mode(config, vision_client).await,
    }
}

/// Run in backfill mode - process existing posts
async fn run_backfill_mode(config: Config, vision_client: Arc<GoogleVisionClient>) -> Result<()> {
    info!(
        "Running backfill job: batch_size={}, max_posts={}, rate_limit={}rps",
        config.backfill_batch_size, config.backfill_max_posts, config.rate_limit_rps
    );

    // Database is required for backfill mode
    if config.database_url.is_empty() {
        error!("DATABASE_URL is required for backfill mode");
        anyhow::bail!("DATABASE_URL environment variable is required for backfill mode");
    }

    let db_pool = sqlx::PgPool::connect(&config.database_url).await.map_err(|e| {
        error!("Failed to connect to database: {}", e);
        anyhow::anyhow!("Database connection error: {}", e)
    })?;

    info!("Database connection pool initialized");

    // Create and run backfill job
    let backfill_job = BackfillJob::new(db_pool, vision_client, config.clone());

    let stats = backfill_job.run().await.map_err(|e| {
        error!("Backfill job failed: {}", e);
        anyhow::anyhow!("Backfill job error: {}", e)
    })?;

    info!(
        "Backfill completed: processed={}, success={}, errors={}, batches={}",
        stats.total_processed, stats.success_count, stats.error_count, stats.batches_processed
    );

    // Exit with error code if there were failures
    if stats.error_count > 0 {
        warn!(
            "Backfill completed with {} errors out of {} posts",
            stats.error_count, stats.total_processed
        );
    }

    Ok(())
}

/// Run in consumer mode - process Kafka events
async fn run_consumer_mode(config: Config, vision_client: Arc<GoogleVisionClient>) -> Result<()> {
    // Initialize database connection pool (optional for consumer mode)
    let db_pool = if !config.database_url.is_empty() {
        match sqlx::PgPool::connect(&config.database_url).await {
            Ok(pool) => {
                info!("Database connection pool initialized");
                Some(pool)
            }
            Err(e) => {
                warn!("Failed to connect to database: {}. Running without DB.", e);
                None
            }
        }
    } else {
        warn!("DATABASE_URL not set, running without database");
        None
    };

    // Initialize Kafka producer
    let producer = Arc::new(
        VLMProducer::new(&config.kafka_brokers).map_err(|e| {
            error!("Failed to create Kafka producer: {}", e);
            anyhow::anyhow!("Kafka producer error: {}", e)
        })?,
    );

    info!("Kafka producer initialized");

    // Initialize Kafka consumer
    let consumer_config = VLMConsumerConfig {
        brokers: config.kafka_brokers.clone(),
        group_id: "vlm-service".to_string(),
        max_retries: 3,
        retry_backoff_ms: 100,
        max_retry_backoff_ms: 30_000,
    };

    let consumer = VLMConsumer::new(
        consumer_config,
        vision_client.clone(),
        producer.clone(),
        db_pool,
    )
    .map_err(|e| {
        error!("Failed to create Kafka consumer: {}", e);
        anyhow::anyhow!("Kafka consumer error: {}", e)
    })?;

    info!("Kafka consumer initialized");

    // Spawn consumer task
    let consumer_handle = tokio::spawn(async move {
        if let Err(e) = consumer.run().await {
            error!("Kafka consumer error: {}", e);
        }
    });

    info!("VLM Service ready on port {}", config.grpc_port);
    info!("Listening for posts on topic: vlm.post.created");

    // Wait for shutdown signal
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            info!("Received shutdown signal");
        }
        _ = consumer_handle => {
            error!("Consumer task exited unexpectedly");
        }
    }

    info!("Shutting down VLM Service");

    Ok(())
}
