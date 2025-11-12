use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use dotenvy::dotenv;
use std::env;

#[derive(Debug, Clone)]
pub struct RedisSentinelConfig {
    pub endpoints: Vec<String>,
    pub master_name: String,
    pub poll_interval_ms: u64,
}

#[derive(Debug, Clone)]
pub struct IceServerConfig {
    pub urls: Vec<String>,
    pub username: Option<String>,
    pub credential: Option<String>,
    pub credential_type: Option<String>,
}

#[derive(Debug, Clone)]
pub struct S3Config {
    pub bucket: String,
    pub region: String,
    pub endpoint: Option<String>,
}

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub redis_url: String,
    pub redis_sentinel: Option<RedisSentinelConfig>,
    pub port: u16,
    pub grpc_port: u16,
    pub ice_servers: Vec<IceServerConfig>,
    pub ice_ttl_seconds: u32,
    pub encryption_master_key: [u8; 32],
    pub s3: S3Config,
    pub auth_service_url: String,
}

impl Config {
    fn parse_urls(value: &str) -> Vec<String> {
        value
            .split(',')
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
            .collect()
    }

    fn default_stun_urls() -> Vec<String> {
        vec![
            "stun:stun.l.google.com:19302".to_string(),
            "stun:stun1.l.google.com:19302".to_string(),
        ]
    }

    pub fn from_env() -> Result<Self, crate::error::AppError> {
        dotenv().ok();
        let database_url = env::var("DATABASE_URL")
            .map_err(|_| crate::error::AppError::Config("DATABASE_URL missing".into()))?;
        let redis_url = env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".into());
        let port = env::var("PORT")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(3000);
        let grpc_port = env::var("GRPC_PORT")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(50051);

        // Redis Sentinel configuration
        let redis_sentinel = if let Ok(endpoints_str) = env::var("REDIS_SENTINEL_ENDPOINTS") {
            let endpoints = endpoints_str
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect::<Vec<_>>();

            if !endpoints.is_empty() {
                let master_name = env::var("REDIS_SENTINEL_MASTER_NAME")
                    .unwrap_or_else(|_| "mymaster".to_string());
                let poll_interval_ms = env::var("REDIS_SENTINEL_POLL_INTERVAL_MS")
                    .ok()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(5000);

                Some(RedisSentinelConfig {
                    endpoints,
                    master_name,
                    poll_interval_ms,
                })
            } else {
                None
            }
        } else {
            None
        };

        // WebRTC ICE/TURN configuration
        let stun_urls_env =
            env::var("RTC_STUN_URLS").unwrap_or_else(|_| Self::default_stun_urls().join(","));
        let stun_urls = Self::parse_urls(&stun_urls_env);

        let turn_urls = env::var("RTC_TURN_URLS")
            .ok()
            .map(|value| Self::parse_urls(&value))
            .unwrap_or_default();
        let turn_username = env::var("RTC_TURN_USERNAME").ok();
        let turn_password = env::var("RTC_TURN_PASSWORD").ok();
        let credential_type = env::var("RTC_TURN_CREDENTIAL_TYPE").ok();

        let mut ice_servers: Vec<IceServerConfig> = Vec::new();
        if !stun_urls.is_empty() {
            ice_servers.push(IceServerConfig {
                urls: stun_urls,
                username: None,
                credential: None,
                credential_type: None,
            });
        }
        if !turn_urls.is_empty() {
            ice_servers.push(IceServerConfig {
                urls: turn_urls,
                username: turn_username,
                credential: turn_password.clone(),
                credential_type: match (&turn_password, &credential_type) {
                    (Some(_), Some(t)) => Some(t.clone()),
                    (Some(_), None) => Some("password".to_string()),
                    _ => None,
                },
            });
        }

        let ice_ttl_seconds = env::var("ICE_TTL_SECONDS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(86400);

        // E2EE encryption master key
        let master_key_env = env::var("ENCRYPTION_MASTER_KEY").map_err(|_| {
            crate::error::AppError::Config("ENCRYPTION_MASTER_KEY missing (required for E2EE)".into())
        })?;

        let master_key_bytes = STANDARD
            .decode(master_key_env.as_bytes())
            .map_err(|e| crate::error::AppError::Config(format!("ENCRYPTION_MASTER_KEY decode: {e}")))?;

        if master_key_bytes.len() != 32 {
            return Err(crate::error::AppError::Config(
                "ENCRYPTION_MASTER_KEY must be 32 bytes".into(),
            ));
        }

        let mut encryption_master_key = [0u8; 32];
        encryption_master_key.copy_from_slice(&master_key_bytes);

        // S3 configuration
        let s3 = S3Config {
            bucket: env::var("S3_BUCKET").unwrap_or_else(|_| "nova-media".to_string()),
            region: env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".to_string()),
            endpoint: env::var("S3_ENDPOINT").ok(),
        };

        // Auth service URL
        let auth_service_url = env::var("AUTH_SERVICE_URL")
            .unwrap_or_else(|_| "http://auth-service:50051".to_string());

        Ok(Self {
            database_url,
            redis_url,
            redis_sentinel,
            port,
            grpc_port,
            ice_servers,
            ice_ttl_seconds,
            encryption_master_key,
            s3,
            auth_service_url,
        })
    }
}
