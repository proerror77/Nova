use serde::{Deserialize, Serialize};

pub mod video_config {
    use super::*;

    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub struct VideoConfig {
        pub cdn: CdnConfig,
    }

    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub struct CdnConfig {
        pub provider: String,
        pub endpoint_url: String,
        pub cache_ttl_seconds: u32,
        pub enable_geo_cache: bool,
        pub fallback_to_s3: bool,
    }

    impl Default for CdnConfig {
        fn default() -> Self {
            Self {
                provider: "cloudflare".to_string(),
                endpoint_url: "https://video.nova.dev".to_string(),
                cache_ttl_seconds: 3600,
                enable_geo_cache: true,
                fallback_to_s3: true,
            }
        }
    }

    impl VideoConfig {
        pub fn from_env() -> Self {
            Self {
                cdn: CdnConfig {
                    provider: std::env::var("CDN_PROVIDER").unwrap_or_else(|_| "cloudflare".into()),
                    endpoint_url: std::env::var("CDN_ENDPOINT_URL")
                        .unwrap_or_else(|_| "https://video.nova.dev".into()),
                    cache_ttl_seconds: std::env::var("CDN_CACHE_TTL_SECONDS")
                        .ok()
                        .and_then(|v| v.parse().ok())
                        .unwrap_or(3600),
                    enable_geo_cache: std::env::var("CDN_ENABLE_GEO_CACHE")
                        .unwrap_or_else(|_| "true".into())
                        .parse()
                        .unwrap_or(true),
                    fallback_to_s3: std::env::var("CDN_FALLBACK_TO_S3")
                        .unwrap_or_else(|_| "true".into())
                        .parse()
                        .unwrap_or(true),
                },
            }
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub app: AppConfig,
    pub database: DatabaseConfig,
    pub video: video_config::VideoConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub env: String,
    pub port: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
}

impl Config {
    pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Config {
            app: AppConfig {
                env: std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string()),
                port: std::env::var("APP_PORT")
                    .unwrap_or_else(|_| "8000".to_string())
                    .parse()?,
            },
            database: DatabaseConfig {
                url: std::env::var("DATABASE_URL")?,
                max_connections: std::env::var("DATABASE_MAX_CONNECTIONS")
                    .unwrap_or_else(|_| "10".to_string())
                    .parse()?,
            },
            video: video_config::VideoConfig::from_env(),
        })
    }
}
