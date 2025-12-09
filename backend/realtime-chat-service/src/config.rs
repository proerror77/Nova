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
pub struct MatrixConfig {
    pub enabled: bool,
    pub homeserver_url: String,
    pub service_user: String,
    pub access_token: Option<String>,
    pub device_name: String,
}

/// VoIP configuration combining ICE servers and Matrix settings
///
/// This structure aggregates all VoIP-related configuration for easy access
/// in VoIP signaling operations.
#[derive(Debug, Clone)]
pub struct VoipConfig {
    /// TURN/STUN servers for WebRTC ICE
    pub ice_servers: Vec<IceServerConfig>,
    /// TTL for ICE credentials in seconds
    pub ice_ttl_seconds: u32,
    /// Matrix configuration (for E2EE VoIP signaling)
    pub matrix: MatrixConfig,
}

impl VoipConfig {
    /// Create VoipConfig from main Config
    pub fn from_config(config: &Config) -> Self {
        Self {
            ice_servers: config.ice_servers.clone(),
            ice_ttl_seconds: config.ice_ttl_seconds,
            matrix: config.matrix.clone(),
        }
    }

    /// Convert ICE servers to JSON format for m.call.invite
    ///
    /// Returns a JSON array suitable for WebRTC RTCConfiguration.iceServers
    pub fn ice_servers_json(&self) -> serde_json::Value {
        use serde_json::json;

        let servers: Vec<serde_json::Value> = self
            .ice_servers
            .iter()
            .map(|server| {
                let mut obj = json!({
                    "urls": server.urls,
                });

                if let Some(username) = &server.username {
                    obj["username"] = json!(username);
                }

                if let Some(credential) = &server.credential {
                    obj["credential"] = json!(credential);
                }

                if let Some(credential_type) = &server.credential_type {
                    obj["credentialType"] = json!(credential_type);
                }

                obj
            })
            .collect();

        json!(servers)
    }
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
    pub matrix: MatrixConfig,
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
            crate::error::AppError::Config(
                "ENCRYPTION_MASTER_KEY missing (required for E2EE)".into(),
            )
        })?;

        let master_key_bytes = STANDARD.decode(master_key_env.as_bytes()).map_err(|e| {
            crate::error::AppError::Config(format!("ENCRYPTION_MASTER_KEY decode: {e}"))
        })?;

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

        // Matrix configuration (optional, for external E2EE bridge)
        let matrix_enabled = env::var("MATRIX_ENABLED")
            .ok()
            .map(|v| v.eq_ignore_ascii_case("true") || v == "1")
            .unwrap_or(false);
        let matrix = MatrixConfig {
            enabled: matrix_enabled,
            homeserver_url: env::var("MATRIX_HOMESERVER_URL")
                .unwrap_or_else(|_| "https://chat.yourcorp.com".to_string()),
            service_user: env::var("MATRIX_SERVICE_USER")
                .unwrap_or_else(|_| "@service:chat.yourcorp.com".to_string()),
            access_token: env::var("MATRIX_ACCESS_TOKEN").ok(),
            device_name: env::var("MATRIX_DEVICE_NAME")
                .unwrap_or_else(|_| "nova-realtime-chat-service".to_string()),
        };

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
            matrix,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_voip_config_ice_servers_json() {
        let ice_servers = vec![
            IceServerConfig {
                urls: vec!["stun:stun.l.google.com:19302".to_string()],
                username: None,
                credential: None,
                credential_type: None,
            },
            IceServerConfig {
                urls: vec!["turn:turn.example.com:3478".to_string()],
                username: Some("testuser".to_string()),
                credential: Some("testpass".to_string()),
                credential_type: Some("password".to_string()),
            },
        ];

        let voip_config = VoipConfig {
            ice_servers,
            ice_ttl_seconds: 86400,
            matrix: MatrixConfig {
                enabled: false,
                homeserver_url: "https://matrix.example.com".to_string(),
                service_user: "@service:example.com".to_string(),
                access_token: None,
                device_name: "test".to_string(),
            },
        };

        let json = voip_config.ice_servers_json();

        // Verify JSON structure
        assert!(json.is_array());
        let servers = json.as_array().unwrap();
        assert_eq!(servers.len(), 2);

        // Check STUN server
        let stun = &servers[0];
        assert_eq!(stun["urls"][0], "stun:stun.l.google.com:19302");
        assert!(stun.get("username").is_none());

        // Check TURN server
        let turn = &servers[1];
        assert_eq!(turn["urls"][0], "turn:turn.example.com:3478");
        assert_eq!(turn["username"], "testuser");
        assert_eq!(turn["credential"], "testpass");
        assert_eq!(turn["credentialType"], "password");
    }

    #[test]
    fn test_voip_config_from_config() {
        let config = Config {
            database_url: "postgres://localhost/test".to_string(),
            redis_url: "redis://localhost".to_string(),
            redis_sentinel: None,
            port: 3000,
            grpc_port: 50051,
            ice_servers: vec![
                IceServerConfig {
                    urls: vec!["stun:stun.test.com:19302".to_string()],
                    username: None,
                    credential: None,
                    credential_type: None,
                },
            ],
            ice_ttl_seconds: 3600,
            encryption_master_key: [0u8; 32],
            s3: S3Config {
                bucket: "test-bucket".to_string(),
                region: "us-east-1".to_string(),
                endpoint: None,
            },
            auth_service_url: "http://localhost:50051".to_string(),
            matrix: MatrixConfig {
                enabled: true,
                homeserver_url: "https://matrix.test.com".to_string(),
                service_user: "@service:test.com".to_string(),
                access_token: Some("token".to_string()),
                device_name: "test-device".to_string(),
            },
        };

        let voip_config = VoipConfig::from_config(&config);

        assert_eq!(voip_config.ice_servers.len(), 1);
        assert_eq!(voip_config.ice_ttl_seconds, 3600);
        assert_eq!(voip_config.matrix.homeserver_url, "https://matrix.test.com");
    }
}
