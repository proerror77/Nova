/// Configuration management for media-service
///
/// Loads configuration from environment variables with sensible defaults.
use serde::Deserialize;

#[derive(Clone, Debug, Deserialize)]
pub struct Config {
    pub app: AppConfig,
    pub cors: CorsConfig,
    pub database: DatabaseConfig,
    pub cache: CacheConfig,
    pub kafka: KafkaConfig,
    pub s3: S3Config,
}

#[derive(Clone, Debug, Deserialize)]
pub struct AppConfig {
    pub host: String,
    pub port: u16,
    pub env: String,
}

#[derive(Clone, Debug, Deserialize)]
pub struct CorsConfig {
    pub allowed_origins: Vec<String>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
}

#[derive(Clone, Debug, Deserialize)]
pub struct CacheConfig {
    pub redis_url: String,
    #[serde(default)]
    pub sentinel: Option<CacheSentinelConfig>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct CacheSentinelConfig {
    pub endpoints: Vec<String>,
    pub master_name: String,
    pub poll_interval_ms: u64,
}

#[derive(Clone, Debug, Deserialize)]
pub struct KafkaConfig {
    pub brokers: String,
    pub events_topic: String,
}

#[derive(Clone, Debug, Deserialize)]
pub struct S3Config {
    pub bucket: String,
    pub region: String,
    pub access_key_id: Option<String>,
    pub secret_access_key: Option<String>,
    pub endpoint: Option<String>,
}

impl Config {
    /// Load configuration from environment variables
    pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Config {
            app: AppConfig {
                host: std::env::var("MEDIA_SERVICE_HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
                port: std::env::var("MEDIA_SERVICE_PORT")
                    .unwrap_or_else(|_| "8082".to_string())
                    .parse()
                    .unwrap_or(8082),
                env: std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string()),
            },
            cors: CorsConfig {
                allowed_origins: vec!["*".to_string()],
            },
            database: DatabaseConfig {
                url: std::env::var("DATABASE_URL")
                    .unwrap_or_else(|_| "postgresql://localhost/nova".to_string()),
                max_connections: std::env::var("DATABASE_MAX_CONNECTIONS")
                    .unwrap_or_else(|_| "10".to_string())
                    .parse()
                    .unwrap_or(10),
            },
            cache: CacheConfig {
                redis_url: std::env::var("REDIS_URL")
                    .unwrap_or_else(|_| "redis://localhost".to_string()),
                sentinel: parse_sentinel_config(),
            },
            kafka: KafkaConfig {
                brokers: std::env::var("KAFKA_BROKERS")
                    .unwrap_or_else(|_| "localhost:9092".to_string()),
                events_topic: std::env::var("KAFKA_EVENTS_TOPIC")
                    .unwrap_or_else(|_| "media_events".to_string()),
            },
            s3: S3Config {
                bucket: std::env::var("S3_BUCKET").unwrap_or_else(|_| "nova-uploads".to_string()),
                region: std::env::var("AWS_REGION").unwrap_or_else(|_| "us-east-1".to_string()),
                access_key_id: std::env::var("AWS_ACCESS_KEY_ID").ok(),
                secret_access_key: std::env::var("AWS_SECRET_ACCESS_KEY").ok(),
                endpoint: std::env::var("S3_ENDPOINT").ok(),
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
