use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use dotenvy::dotenv;
pub use nova_apns_shared::ApnsConfig;
use std::env;

#[derive(Debug, Clone)]
pub struct FcmConfig {
    pub api_key: String,
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
    pub kafka_brokers: String,
    pub port: u16,
    pub ice_servers: Vec<IceServerConfig>,
    pub ice_ttl_seconds: u32,
    pub apns: Option<ApnsConfig>,
    pub fcm: Option<FcmConfig>,
    pub encryption_master_key: [u8; 32],
    pub s3: S3Config,
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
        let kafka_brokers = env::var("KAFKA_BROKERS").unwrap_or_else(|_| "localhost:9092".into());
        let port = env::var("PORT")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(3000);

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
                    _ => credential_type,
                },
            });
        }

        let ice_ttl_seconds = env::var("RTC_ICE_TTL_SECONDS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(3600);

        let master_key_b64 = env::var("MESSAGE_ENCRYPTION_MASTER_KEY").map_err(|_| {
            crate::error::AppError::Config("MESSAGE_ENCRYPTION_MASTER_KEY missing".into())
        })?;
        let master_key_bytes = STANDARD.decode(master_key_b64.trim()).map_err(|_| {
            crate::error::AppError::Config("MESSAGE_ENCRYPTION_MASTER_KEY invalid base64".into())
        })?;
        if master_key_bytes.len() != 32 {
            return Err(crate::error::AppError::Config(
                "MESSAGE_ENCRYPTION_MASTER_KEY must decode to 32 bytes".into(),
            ));
        }
        let mut encryption_master_key = [0u8; 32];
        encryption_master_key.copy_from_slice(&master_key_bytes);

        let apns = match env::var("APNS_CERTIFICATE_PATH") {
            Ok(path) if !path.trim().is_empty() => {
                let bundle_id = env::var("APNS_BUNDLE_ID")
                    .map_err(|_| crate::error::AppError::Config("APNS_BUNDLE_ID missing".into()))?;
                let passphrase = env::var("APNS_CERTIFICATE_PASSPHRASE").ok();
                let is_production = env::var("APNS_IS_PRODUCTION")
                    .unwrap_or_else(|_| "false".to_string())
                    .eq_ignore_ascii_case("true");
                Some(ApnsConfig {
                    certificate_path: path,
                    certificate_passphrase: passphrase,
                    bundle_id,
                    is_production,
                })
            }
            _ => None,
        };

        let fcm = match env::var("FCM_API_KEY") {
            Ok(api_key) if !api_key.trim().is_empty() => Some(FcmConfig { api_key }),
            _ => None,
        };

        let s3 = S3Config {
            bucket: env::var("S3_BUCKET").unwrap_or_else(|_| "nova-audio".to_string()),
            region: env::var("AWS_REGION").unwrap_or_else(|_| "us-east-1".to_string()),
            endpoint: env::var("S3_ENDPOINT").ok(),
        };

        Ok(Self {
            database_url,
            redis_url,
            redis_sentinel: parse_sentinel_config(),
            kafka_brokers,
            port,
            ice_servers,
            ice_ttl_seconds,
            apns,
            fcm,
            encryption_master_key,
            s3,
        })
    }

    #[cfg(test)]
    pub fn test_defaults() -> Self {
        Self {
            database_url: "postgres://localhost/test".into(),
            redis_url: "redis://127.0.0.1:6379/0".into(),
            redis_sentinel: None,
            kafka_brokers: "localhost:9092".into(),
            port: 3000,
            ice_servers: Vec::new(),
            ice_ttl_seconds: 3600,
            apns: None,
            fcm: None,
            encryption_master_key: [0u8; 32],
            s3: S3Config {
                bucket: "nova-audio".into(),
                region: "us-east-1".into(),
                endpoint: None,
            },
        }
    }
}

#[derive(Debug, Clone)]
pub struct RedisSentinelConfig {
    pub endpoints: Vec<String>,
    pub master_name: String,
    pub poll_interval_ms: u64,
}

fn parse_sentinel_config() -> Option<RedisSentinelConfig> {
    let raw = env::var("REDIS_SENTINEL_ENDPOINTS").ok()?;
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
        env::var("REDIS_SENTINEL_MASTER_NAME").unwrap_or_else(|_| "mymaster".to_string());
    let poll_interval_ms = env::var("REDIS_SENTINEL_POLL_INTERVAL_MS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(5000);

    Some(RedisSentinelConfig {
        endpoints,
        master_name,
        poll_interval_ms,
    })
}
