/// Configuration management for Content Service
///
/// This module handles loading and managing configuration from environment variables
/// and configuration files.
use serde::{Deserialize, Serialize};

/// Main application configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Application settings
    pub app: AppConfig,
    /// CORS configuration
    pub cors: CorsConfig,
    /// Database configuration
    pub database: DatabaseConfig,
    /// Cache (Redis) configuration
    pub cache: CacheConfig,
    /// Kafka configuration
    pub kafka: KafkaConfig,
    /// ClickHouse configuration
    pub clickhouse: ClickHouseConfig,
    /// Feed ranking configuration
    pub feed: FeedConfig,
}

/// Application settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    /// Application environment (dev, staging, prod)
    pub env: String,
    /// Server host to bind to
    pub host: String,
    /// Server port to bind to
    pub port: u16,
}

/// CORS configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CorsConfig {
    /// Comma-separated list of allowed origins
    pub allowed_origins: String,
}

/// Database configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    /// Database URL
    pub url: String,
    /// Max connections in pool
    pub max_connections: u32,
}

/// Cache (Redis) configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheConfig {
    /// Redis URL
    pub url: String,
    #[serde(default)]
    pub sentinel: Option<CacheSentinelConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheSentinelConfig {
    pub endpoints: Vec<String>,
    pub master_name: String,
    pub poll_interval_ms: u64,
}

/// Kafka configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaConfig {
    /// Kafka brokers
    pub brokers: Vec<String>,
    /// Events topic
    pub events_topic: String,
    #[serde(default = "default_kafka_request_timeout_ms")]
    pub request_timeout_ms: u64,
    #[serde(default = "default_kafka_retry_backoff_ms")]
    pub retry_backoff_ms: u64,
    #[serde(default = "default_kafka_retry_attempts")]
    pub retry_attempts: u32,
}

/// ClickHouse configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClickHouseConfig {
    pub url: String,
    pub database: String,
    pub username: String,
    pub password: String,
    pub query_timeout_ms: u64,
}

/// Feed ranking configuration (weights, candidate limits)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedConfig {
    pub freshness_weight: f64,
    pub engagement_weight: f64,
    pub affinity_weight: f64,
    pub freshness_lambda: f64,
    pub max_candidates: usize,
    pub candidate_prefetch_multiplier: usize,
    pub fallback_cache_ttl_secs: u64,
}

impl Config {
    /// Load configuration from environment variables
    pub fn from_env() -> Result<Self, String> {
        let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());

        Ok(Config {
            app: AppConfig {
                env: app_env.clone(),
                host: std::env::var("CONTENT_SERVICE_HOST")
                    .unwrap_or_else(|_| "0.0.0.0".to_string()),
                port: std::env::var("CONTENT_SERVICE_PORT")
                    .ok()
                    .and_then(|p| p.parse().ok())
                    .unwrap_or(8081),
            },
            cors: {
                let allowed_origins = match std::env::var("CORS_ALLOWED_ORIGINS") {
                    Ok(value) => value,
                    Err(_) if app_env.eq_ignore_ascii_case("production") => {
                        return Err("CORS_ALLOWED_ORIGINS must be set in production".to_string())
                    }
                    Err(_) => "http://localhost:3000".to_string(),
                };

                if app_env.eq_ignore_ascii_case("production") && allowed_origins.trim() == "*" {
                    return Err("CORS_ALLOWED_ORIGINS cannot be '*' in production".to_string());
                }

                CorsConfig { allowed_origins }
            },
            database: DatabaseConfig {
                url: std::env::var("DATABASE_URL")
                    .unwrap_or_else(|_| "postgresql://localhost/nova".to_string()),
                max_connections: std::env::var("DATABASE_MAX_CONNECTIONS")
                    .ok()
                    .and_then(|c| c.parse().ok())
                    .unwrap_or(10),
            },
            cache: CacheConfig {
                url: std::env::var("REDIS_URL")
                    .unwrap_or_else(|_| "redis://localhost:6379".to_string()),
                sentinel: parse_sentinel_config(),
            },
            kafka: KafkaConfig {
                brokers: std::env::var("KAFKA_BROKERS")
                    .unwrap_or_else(|_| "localhost:9092".to_string())
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .collect(),
                events_topic: std::env::var("KAFKA_EVENTS_TOPIC")
                    .unwrap_or_else(|_| "nova-events".to_string()),
                request_timeout_ms: std::env::var("KAFKA_REQUEST_TIMEOUT_MS")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or_else(default_kafka_request_timeout_ms),
                retry_backoff_ms: std::env::var("KAFKA_RETRY_BACKOFF_MS")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or_else(default_kafka_retry_backoff_ms),
                retry_attempts: std::env::var("KAFKA_RETRY_ATTEMPTS")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or_else(default_kafka_retry_attempts),
            },
            clickhouse: {
                let password =
                    std::env::var("CLICKHOUSE_PASSWORD").unwrap_or_else(|_| "".to_string());
                if app_env.eq_ignore_ascii_case("production")
                    && (password.trim().is_empty() || password == "clickhouse")
                {
                    return Err(
                        "CLICKHOUSE_PASSWORD must be set to a non-default value in production"
                            .to_string(),
                    );
                }

                ClickHouseConfig {
                    url: std::env::var("CLICKHOUSE_URL")
                        .unwrap_or_else(|_| "http://localhost:8123".to_string()),
                    database: std::env::var("CLICKHOUSE_DATABASE")
                        .unwrap_or_else(|_| "default".to_string()),
                    username: std::env::var("CLICKHOUSE_USERNAME")
                        .unwrap_or_else(|_| "default".to_string()),
                    password,
                    query_timeout_ms: std::env::var("CLICKHOUSE_QUERY_TIMEOUT_MS")
                        .ok()
                        .and_then(|v| v.parse().ok())
                        .unwrap_or(2_000),
                }
            },
            feed: FeedConfig {
                freshness_weight: parse_env_or_default("FEED_FRESHNESS_WEIGHT", 0.3)?,
                engagement_weight: parse_env_or_default("FEED_ENGAGEMENT_WEIGHT", 0.4)?,
                affinity_weight: parse_env_or_default("FEED_AFFINITY_WEIGHT", 0.3)?,
                freshness_lambda: parse_env_or_default("FEED_FRESHNESS_LAMBDA", 0.1)?,
                max_candidates: std::env::var("FEED_MAX_CANDIDATES")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(1_000),
                candidate_prefetch_multiplier: std::env::var("FEED_CANDIDATE_PREFETCH_MULTIPLIER")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(5),
                fallback_cache_ttl_secs: std::env::var("FEED_FALLBACK_CACHE_TTL_SECS")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(60),
            },
        })
    }
}

fn parse_sentinel_config() -> Option<CacheSentinelConfig> {
    let raw = std::env::var("REDIS_SENTINEL_ENDPOINTS").ok()?;
    let endpoints: Vec<String> = raw
        .split(',')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|endpoint| {
            if endpoint.starts_with("redis://") || endpoint.starts_with("rediss://") {
                endpoint.to_string()
            } else {
                format!("redis://{}", endpoint)
            }
        })
        .collect();

    if endpoints.is_empty() {
        return None;
    }

    let master_name = std::env::var("REDIS_SENTINEL_MASTER_NAME")
        .unwrap_or_else(|_| "mymaster".to_string());
    let poll_interval_ms = std::env::var("REDIS_SENTINEL_POLL_INTERVAL_MS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(5000);

    Some(CacheSentinelConfig {
        endpoints,
        master_name,
        poll_interval_ms,
    })
}

fn parse_env_or_default(key: &str, default: f64) -> Result<f64, String> {
    match std::env::var(key) {
        Ok(val) => val
            .parse()
            .map_err(|e| format!("Failed to parse {}='{}': {}", key, val, e)),
        Err(_) => Ok(default),
    }
}

fn default_kafka_request_timeout_ms() -> u64 {
    5_000
}

fn default_kafka_retry_backoff_ms() -> u64 {
    200
}

fn default_kafka_retry_attempts() -> u32 {
    3
}
