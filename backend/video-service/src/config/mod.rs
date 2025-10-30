use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub app: AppConfig,
    pub database: DatabaseConfig,
    pub grpc: GrpcConfig,
    pub s3: S3Config,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GrpcConfig {
    pub user_service_url: String,
    #[serde(default = "default_grpc_timeout_secs")]
    pub timeout_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct S3Config {
    pub bucket_name: String,
    pub region: String,
    pub aws_access_key_id: String,
    pub aws_secret_access_key: String,
    pub cloudfront_url: String,
    #[serde(default = "default_presigned_url_expiry_secs")]
    pub presigned_url_expiry_secs: u64,
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
            grpc: GrpcConfig {
                user_service_url: std::env::var("USER_SERVICE_GRPC_URL")
                    .unwrap_or_else(|_| "http://127.0.0.1:50052".to_string()),
                timeout_secs: std::env::var("USER_SERVICE_GRPC_TIMEOUT_SECS")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or_else(default_grpc_timeout_secs),
            },
            s3: S3Config {
                bucket_name: std::env::var("S3_BUCKET_NAME")
                    .unwrap_or_else(|_| "nova-videos".to_string()),
                region: std::env::var("S3_REGION")
                    .unwrap_or_else(|_| "us-east-1".to_string()),
                aws_access_key_id: std::env::var("AWS_ACCESS_KEY_ID")?,
                aws_secret_access_key: std::env::var("AWS_SECRET_ACCESS_KEY")?,
                cloudfront_url: std::env::var("CLOUDFRONT_URL")
                    .unwrap_or_else(|_| "https://d1234567890.cloudfront.net".to_string()),
                presigned_url_expiry_secs: std::env::var("S3_PRESIGNED_URL_EXPIRY_SECS")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or_else(default_presigned_url_expiry_secs),
            },
        })
    }
}

fn default_grpc_timeout_secs() -> u64 {
    30
}

fn default_presigned_url_expiry_secs() -> u64 {
    900 // 15 minutes
}
