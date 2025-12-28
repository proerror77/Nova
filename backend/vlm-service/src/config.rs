//! Configuration for VLM service
use serde::Deserialize;

/// Main configuration struct, loaded from environment variables
#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// Google Cloud Vision API key (optional, uses ADC if not set)
    #[serde(default = "default_vision_api_key")]
    pub google_vision_api_key: String,

    /// Use Application Default Credentials instead of API key
    #[serde(default)]
    pub use_adc: bool,

    /// Database connection URL
    pub database_url: String,

    /// Redis URL for caching
    #[serde(default = "default_redis_url")]
    pub redis_url: String,

    /// Kafka broker addresses
    #[serde(default = "default_kafka_brokers")]
    pub kafka_brokers: String,

    /// Kafka events topic
    #[serde(default = "default_kafka_topic")]
    pub kafka_events_topic: String,

    /// gRPC server port
    #[serde(default = "default_grpc_port")]
    pub grpc_port: u16,

    /// Maximum tags to generate per image
    #[serde(default = "default_max_tags")]
    pub max_tags: usize,

    /// Minimum confidence for VLM tags
    #[serde(default = "default_min_confidence")]
    pub min_tag_confidence: f32,

    /// Minimum confidence for channel matching
    #[serde(default = "default_channel_min_confidence")]
    pub channel_min_confidence: f32,

    /// Maximum channels to suggest per post
    #[serde(default = "default_max_channels")]
    pub max_channels: usize,

    /// Rate limit for Vision API (requests per second)
    #[serde(default = "default_rate_limit")]
    pub rate_limit_rps: u32,

    /// Cache TTL in seconds
    #[serde(default = "default_cache_ttl")]
    pub cache_ttl_seconds: u64,

    // ============================================
    // Backfill mode configuration
    // ============================================
    /// Batch size for backfill processing
    #[serde(default = "default_backfill_batch_size")]
    pub backfill_batch_size: u32,

    /// Maximum posts to process in one run
    #[serde(default = "default_backfill_max_posts")]
    pub backfill_max_posts: u32,

    /// Delay between batches in milliseconds
    #[serde(default = "default_backfill_batch_delay_ms")]
    pub backfill_batch_delay_ms: u64,

    /// Run once and exit (for CronJob mode)
    #[serde(default)]
    pub backfill_run_once: bool,
}

fn default_backfill_batch_size() -> u32 {
    100
}

fn default_backfill_max_posts() -> u32 {
    10000
}

fn default_backfill_batch_delay_ms() -> u64 {
    100 // 100ms delay = ~10 RPS
}

fn default_vision_api_key() -> String {
    String::new()
}

fn default_redis_url() -> String {
    "redis://localhost:6379".to_string()
}

fn default_kafka_brokers() -> String {
    "localhost:9092".to_string()
}

fn default_kafka_topic() -> String {
    "nova-events".to_string()
}

fn default_grpc_port() -> u16 {
    50060
}

fn default_max_tags() -> usize {
    15
}

fn default_min_confidence() -> f32 {
    0.3
}

fn default_channel_min_confidence() -> f32 {
    0.25
}

fn default_max_channels() -> usize {
    3
}

fn default_rate_limit() -> u32 {
    10
}

fn default_cache_ttl() -> u64 {
    3600 // 1 hour
}

impl Config {
    /// Load configuration from environment variables
    pub fn from_env() -> Result<Self, envy::Error> {
        envy::from_env()
    }
}
