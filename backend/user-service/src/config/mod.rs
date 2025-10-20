pub mod job_config;
pub mod video_config;

use serde::Deserialize;
use std::env;
use base64::{Engine as _, engine::general_purpose};

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub app: AppConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,
    pub jwt: JwtConfig,
    pub email: EmailConfig,
    pub rate_limit: RateLimitConfig,
    pub s3: S3Config,
    pub cors: CorsConfig,
    pub clickhouse: ClickHouseConfig,
    pub kafka: KafkaConfig,
    // pub video: video_config::VideoConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AppConfig {
    #[serde(default = "default_app_env")]
    pub env: String,

    #[serde(default = "default_app_host")]
    pub host: String,

    #[serde(default = "default_app_port")]
    pub port: u16,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,

    #[serde(default = "default_db_max_connections")]
    pub max_connections: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RedisConfig {
    pub url: String,

    #[serde(default = "default_redis_pool_size")]
    pub pool_size: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct JwtConfig {
    pub secret: String,

    #[serde(default = "default_jwt_access_ttl")]
    pub access_token_ttl: i64,

    #[serde(default = "default_jwt_refresh_ttl")]
    pub refresh_token_ttl: i64,

    /// Private key for signing tokens (PEM format, base64-encoded for env var)
    pub private_key_pem: String,

    /// Public key for validating tokens (PEM format, base64-encoded for env var)
    pub public_key_pem: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EmailConfig {
    pub smtp_host: String,

    #[serde(default = "default_smtp_port")]
    pub smtp_port: u16,

    #[serde(default)]
    pub smtp_username: String,

    #[serde(default)]
    pub smtp_password: String,

    pub smtp_from: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RateLimitConfig {
    #[serde(default = "default_rate_limit_max_requests")]
    pub max_requests: u32,

    #[serde(default = "default_rate_limit_window_secs")]
    pub window_secs: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct S3Config {
    pub bucket_name: String,
    pub region: String,
    pub aws_access_key_id: String,
    pub aws_secret_access_key: String,
    pub cloudfront_url: String,

    #[serde(default = "default_s3_presigned_url_expiry_secs")]
    pub presigned_url_expiry_secs: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CorsConfig {
    /// Comma-separated list of allowed origins (e.g., "https://example.com,https://app.example.com")
    /// Set to "*" to allow all origins (NOT recommended for production)
    pub allowed_origins: String,

    #[serde(default = "default_cors_max_age")]
    pub max_age: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ClickHouseConfig {
    pub url: String,
    #[serde(default = "default_clickhouse_database")]
    pub database: String,
    #[serde(default = "default_clickhouse_user")]
    pub username: String,
    #[serde(default = "default_clickhouse_password")]
    pub password: String,
    #[serde(default = "default_clickhouse_timeout_ms")]
    pub timeout_ms: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct KafkaConfig {
    pub brokers: String,
    #[serde(default = "default_events_topic")]
    pub events_topic: String,
}

// Default value functions
fn default_app_env() -> String {
    "development".to_string()
}

fn default_app_host() -> String {
    "0.0.0.0".to_string()
}

fn default_app_port() -> u16 {
    8080
}

fn default_db_max_connections() -> u32 {
    20
}

fn default_redis_pool_size() -> u32 {
    10
}

fn default_jwt_access_ttl() -> i64 {
    900 // 15 minutes
}

fn default_jwt_refresh_ttl() -> i64 {
    604800 // 7 days
}

fn default_smtp_port() -> u16 {
    587
}

fn default_rate_limit_max_requests() -> u32 {
    100
}

fn default_rate_limit_window_secs() -> u64 {
    60
}

fn default_s3_presigned_url_expiry_secs() -> u64 {
    900 // 15 minutes
}

fn default_cors_max_age() -> u64 {
    3600 // 1 hour
}

fn default_clickhouse_database() -> String {
    "nova_feed".to_string()
}

fn default_clickhouse_user() -> String {
    "default".to_string()
}

fn default_clickhouse_password() -> String {
    "clickhouse".to_string()
}

fn default_clickhouse_timeout_ms() -> u64 {
    5000
}

fn default_events_topic() -> String {
    "events".to_string()
}

impl Config {
    pub fn from_env() -> Result<Self, envy::Error> {
        dotenv::dotenv().ok();

        let app = AppConfig {
            env: env::var("APP_ENV").unwrap_or_else(|_| default_app_env()),
            host: env::var("APP_HOST").unwrap_or_else(|_| default_app_host()),
            port: env::var("APP_PORT")
                .unwrap_or_else(|_| default_app_port().to_string())
                .parse()
                .unwrap_or(default_app_port()),
        };

        let database = DatabaseConfig {
            url: env::var("DATABASE_URL").expect("DATABASE_URL must be set"),
            max_connections: env::var("DATABASE_MAX_CONNECTIONS")
                .unwrap_or_else(|_| default_db_max_connections().to_string())
                .parse()
                .unwrap_or(default_db_max_connections()),
        };

        let redis = RedisConfig {
            url: env::var("REDIS_URL").expect("REDIS_URL must be set"),
            pool_size: env::var("REDIS_POOL_SIZE")
                .unwrap_or_else(|_| default_redis_pool_size().to_string())
                .parse()
                .unwrap_or(default_redis_pool_size()),
        };

        let jwt = JwtConfig {
            secret: env::var("JWT_SECRET").expect("JWT_SECRET must be set"),
            access_token_ttl: env::var("JWT_ACCESS_TOKEN_TTL")
                .unwrap_or_else(|_| default_jwt_access_ttl().to_string())
                .parse()
                .unwrap_or(default_jwt_access_ttl()),
            refresh_token_ttl: env::var("JWT_REFRESH_TOKEN_TTL")
                .unwrap_or_else(|_| default_jwt_refresh_ttl().to_string())
                .parse()
                .unwrap_or(default_jwt_refresh_ttl()),
            private_key_pem: {
                let base64_encoded = env::var("JWT_PRIVATE_KEY_PEM")
                    .expect("JWT_PRIVATE_KEY_PEM must be set (base64-encoded PEM content)");
                let decoded = general_purpose::STANDARD.decode(&base64_encoded)
                    .expect("Failed to decode JWT_PRIVATE_KEY_PEM from base64");
                String::from_utf8(decoded)
                    .expect("JWT_PRIVATE_KEY_PEM is not valid UTF-8")
            },
            public_key_pem: {
                let base64_encoded = env::var("JWT_PUBLIC_KEY_PEM")
                    .expect("JWT_PUBLIC_KEY_PEM must be set (base64-encoded PEM content)");
                let decoded = general_purpose::STANDARD.decode(&base64_encoded)
                    .expect("Failed to decode JWT_PUBLIC_KEY_PEM from base64");
                String::from_utf8(decoded)
                    .expect("JWT_PUBLIC_KEY_PEM is not valid UTF-8")
            },
        };

        let email = EmailConfig {
            smtp_host: env::var("SMTP_HOST").unwrap_or_else(|_| "localhost".to_string()),
            smtp_port: env::var("SMTP_PORT")
                .unwrap_or_else(|_| default_smtp_port().to_string())
                .parse()
                .unwrap_or(default_smtp_port()),
            smtp_username: env::var("SMTP_USERNAME").unwrap_or_default(),
            smtp_password: env::var("SMTP_PASSWORD").unwrap_or_default(),
            smtp_from: env::var("SMTP_FROM").unwrap_or_else(|_| "noreply@nova.dev".to_string()),
        };

        let rate_limit = RateLimitConfig {
            max_requests: env::var("RATE_LIMIT_MAX_REQUESTS")
                .unwrap_or_else(|_| default_rate_limit_max_requests().to_string())
                .parse()
                .unwrap_or(default_rate_limit_max_requests()),
            window_secs: env::var("RATE_LIMIT_WINDOW_SECS")
                .unwrap_or_else(|_| default_rate_limit_window_secs().to_string())
                .parse()
                .unwrap_or(default_rate_limit_window_secs()),
        };

        let s3 = S3Config {
            bucket_name: env::var("S3_BUCKET_NAME").expect("S3_BUCKET_NAME must be set"),
            region: env::var("S3_REGION").expect("S3_REGION must be set"),
            aws_access_key_id: env::var("AWS_ACCESS_KEY_ID")
                .expect("AWS_ACCESS_KEY_ID must be set"),
            aws_secret_access_key: env::var("AWS_SECRET_ACCESS_KEY")
                .expect("AWS_SECRET_ACCESS_KEY must be set"),
            cloudfront_url: env::var("CLOUDFRONT_URL").expect("CLOUDFRONT_URL must be set"),
            presigned_url_expiry_secs: env::var("S3_PRESIGNED_URL_EXPIRY_SECS")
                .unwrap_or_else(|_| default_s3_presigned_url_expiry_secs().to_string())
                .parse()
                .unwrap_or(default_s3_presigned_url_expiry_secs()),
        };

        let cors = CorsConfig {
            allowed_origins: env::var("CORS_ALLOWED_ORIGINS")
                .unwrap_or_else(|_| "http://localhost:3000".to_string()),
            max_age: env::var("CORS_MAX_AGE")
                .unwrap_or_else(|_| default_cors_max_age().to_string())
                .parse()
                .unwrap_or(default_cors_max_age()),
        };

        let clickhouse = ClickHouseConfig {
            url: env::var("CLICKHOUSE_URL").expect("CLICKHOUSE_URL must be set"),
            database: env::var("CLICKHOUSE_DB").unwrap_or_else(|_| default_clickhouse_database()),
            username: env::var("CLICKHOUSE_USER").unwrap_or_else(|_| default_clickhouse_user()),
            password: env::var("CLICKHOUSE_PASSWORD")
                .unwrap_or_else(|_| default_clickhouse_password()),
            timeout_ms: env::var("CLICKHOUSE_TIMEOUT_MS")
                .unwrap_or_else(|_| default_clickhouse_timeout_ms().to_string())
                .parse()
                .unwrap_or(default_clickhouse_timeout_ms()),
        };

        let kafka = KafkaConfig {
            brokers: env::var("KAFKA_BROKERS").expect("KAFKA_BROKERS must be set"),
            events_topic: env::var("KAFKA_EVENTS_TOPIC").unwrap_or_else(|_| default_events_topic()),
        };

        // let video = video_config::VideoConfig::from_env();

        Ok(Config {
            app,
            database,
            redis,
            jwt,
            email,
            rate_limit,
            s3,
            cors,
            clickhouse,
            kafka,
            // video,
        })
    }

    pub fn is_production(&self) -> bool {
        self.app.env == "production"
    }

    pub fn is_development(&self) -> bool {
        self.app.env == "development"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_values() {
        assert_eq!(default_app_env(), "development");
        assert_eq!(default_app_host(), "0.0.0.0");
        assert_eq!(default_app_port(), 8080);
        assert_eq!(default_db_max_connections(), 20);
        assert_eq!(default_redis_pool_size(), 10);
        assert_eq!(default_jwt_access_ttl(), 900);
        assert_eq!(default_jwt_refresh_ttl(), 604800);
    }
}
