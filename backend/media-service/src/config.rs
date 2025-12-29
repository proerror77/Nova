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
    pub gcs: Option<GcsConfig>,
    pub upload: UploadConfig,
}

/// Upload limits configuration
#[derive(Clone, Debug, Deserialize)]
pub struct UploadConfig {
    /// Maximum image file size in bytes (default: 10MB)
    pub max_image_size: u64,
    /// Maximum video file size in bytes (default: 100MB)
    pub max_video_size: u64,
    /// Maximum audio file size in bytes (default: 50MB)
    pub max_audio_size: u64,
    /// Maximum total request body size in bytes (default: 150MB)
    pub max_request_size: u64,
    /// Allowed image MIME types
    pub allowed_image_types: Vec<String>,
    /// Allowed video MIME types
    pub allowed_video_types: Vec<String>,
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
pub struct GcsConfig {
    pub bucket: String,
    /// Service account JSON content (preferred), or a filesystem path to JSON.
    /// If both are absent, GCS signing is disabled.
    pub service_account_json: Option<String>,
    pub service_account_json_path: Option<String>,
    #[serde(default = "default_gcs_url_host")]
    pub host: String,
}

fn default_gcs_url_host() -> String {
    "storage.googleapis.com".to_string()
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
                events_topic: {
                    let topic_prefix =
                        std::env::var("KAFKA_TOPIC_PREFIX").unwrap_or_else(|_| "nova".to_string());
                    std::env::var("KAFKA_MEDIA_EVENTS_TOPIC")
                        .or_else(|_| std::env::var("KAFKA_EVENTS_TOPIC"))
                        .unwrap_or_else(|_| format!("{}.media.events", topic_prefix))
                },
            },
            gcs: {
                // Enable GCS signing only when a bucket AND some form of service account JSON is provided.
                let bucket = std::env::var("GCS_BUCKET").ok();
                let sa_json = std::env::var("GCS_SERVICE_ACCOUNT_JSON").ok();
                let sa_json_path = std::env::var("GCS_SERVICE_ACCOUNT_JSON_PATH").ok();
                if let Some(bucket) = bucket {
                    if sa_json.is_some() || sa_json_path.is_some() {
                        Some(GcsConfig {
                            bucket,
                            service_account_json: sa_json,
                            service_account_json_path: sa_json_path,
                            host: std::env::var("GCS_HOST")
                                .unwrap_or_else(|_| default_gcs_url_host()),
                        })
                    } else {
                        None
                    }
                } else {
                    None
                }
            },
            upload: UploadConfig {
                // Default: 10MB for images
                max_image_size: std::env::var("UPLOAD_MAX_IMAGE_SIZE")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(10 * 1024 * 1024),
                // Default: 100MB for videos
                max_video_size: std::env::var("UPLOAD_MAX_VIDEO_SIZE")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(100 * 1024 * 1024),
                // Default: 50MB for audio
                max_audio_size: std::env::var("UPLOAD_MAX_AUDIO_SIZE")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(50 * 1024 * 1024),
                // Default: 150MB total request size
                max_request_size: std::env::var("UPLOAD_MAX_REQUEST_SIZE")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(150 * 1024 * 1024),
                allowed_image_types: std::env::var("UPLOAD_ALLOWED_IMAGE_TYPES")
                    .map(|v| v.split(',').map(|s| s.trim().to_string()).collect())
                    .unwrap_or_else(|_| {
                        vec![
                            "image/jpeg".to_string(),
                            "image/png".to_string(),
                            "image/gif".to_string(),
                            "image/webp".to_string(),
                            "image/heic".to_string(),
                            "image/heif".to_string(),
                        ]
                    }),
                allowed_video_types: std::env::var("UPLOAD_ALLOWED_VIDEO_TYPES")
                    .map(|v| v.split(',').map(|s| s.trim().to_string()).collect())
                    .unwrap_or_else(|_| {
                        vec![
                            "video/mp4".to_string(),
                            "video/quicktime".to_string(),
                            "video/webm".to_string(),
                            "video/x-msvideo".to_string(),
                        ]
                    }),
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

    let master_name =
        std::env::var("REDIS_SENTINEL_MASTER_NAME").unwrap_or_else(|_| "mymaster".to_string());
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
