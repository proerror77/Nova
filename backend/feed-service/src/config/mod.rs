use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub app: AppConfig,
    pub database: DatabaseConfig,
    pub recommendation: RecommendationConfig,
    pub grpc: GrpcConfig,
    #[serde(default)]
    pub kafka: KafkaConfig,
    #[serde(default)]
    pub graph: GraphConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub env: String,
    pub port: u16,
    pub log_level: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecommendationConfig {
    pub collaborative_model_path: String,
    pub content_model_path: String,
    pub onnx_model_path: String,
    pub enable_ab_testing: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GrpcConfig {
    pub user_service_url: String,
    #[serde(default = "default_grpc_timeout_secs")]
    pub timeout_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaConfig {
    #[serde(default = "default_kafka_bootstrap_servers")]
    pub bootstrap_servers: String,
    #[serde(default = "default_kafka_group_id")]
    pub group_id: String,
}

impl Default for KafkaConfig {
    fn default() -> Self {
        Self {
            bootstrap_servers: default_kafka_bootstrap_servers(),
            group_id: default_kafka_group_id(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct GraphConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default = "default_neo4j_uri")]
    pub neo4j_uri: String,
    #[serde(default)]
    pub neo4j_user: String,
    #[serde(default)]
    pub neo4j_password: String,
}

impl Config {
    pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Config {
            app: AppConfig {
                env: std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string()),
                port: std::env::var("APP_PORT")
                    .unwrap_or_else(|_| "8000".to_string())
                    .parse()?,
                log_level: std::env::var("LOG_LEVEL").unwrap_or_else(|_| "info".to_string()),
            },
            database: DatabaseConfig {
                url: std::env::var("DATABASE_URL")?,
                max_connections: std::env::var("DATABASE_MAX_CONNECTIONS")
                    .unwrap_or_else(|_| "10".to_string())
                    .parse()?,
            },
            recommendation: RecommendationConfig {
                collaborative_model_path: std::env::var("COLLAB_MODEL_PATH")
                    .unwrap_or_else(|_| "./models/collaborative.bin".to_string()),
                content_model_path: std::env::var("CONTENT_MODEL_PATH")
                    .unwrap_or_else(|_| "./models/content.bin".to_string()),
                onnx_model_path: std::env::var("ONNX_MODEL_PATH")
                    .unwrap_or_else(|_| "./models/ranker.onnx".to_string()),
                enable_ab_testing: std::env::var("ENABLE_AB_TESTING")
                    .unwrap_or_else(|_| "false".to_string())
                    .parse()?,
            },
            grpc: GrpcConfig {
                user_service_url: std::env::var("USER_SERVICE_GRPC_URL")
                    .unwrap_or_else(|_| "http://127.0.0.1:50051".to_string()),
                timeout_secs: std::env::var("USER_SERVICE_GRPC_TIMEOUT_SECS")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or_else(default_grpc_timeout_secs),
            },
            kafka: KafkaConfig {
                bootstrap_servers: std::env::var("KAFKA_BOOTSTRAP_SERVERS")
                    .unwrap_or_else(|_| default_kafka_bootstrap_servers()),
                group_id: std::env::var("KAFKA_GROUP_ID")
                    .unwrap_or_else(|_| default_kafka_group_id()),
            },
            graph: GraphConfig {
                enabled: std::env::var("NEO4J_ENABLED")
                    .unwrap_or_else(|_| "false".to_string())
                    .parse()
                    .unwrap_or(false),
                neo4j_uri: std::env::var("NEO4J_URI").unwrap_or_else(|_| default_neo4j_uri()),
                neo4j_user: std::env::var("NEO4J_USER").unwrap_or_else(|_| "neo4j".to_string()),
                neo4j_password: std::env::var("NEO4J_PASSWORD")
                    .unwrap_or_else(|_| "password".to_string()),
            },
        })
    }
}

fn default_grpc_timeout_secs() -> u64 {
    30
}

fn default_kafka_bootstrap_servers() -> String {
    "localhost:9092".to_string()
}

fn default_kafka_group_id() -> String {
    "recommendation-service-group".to_string()
}

fn default_neo4j_uri() -> String {
    "neo4j://localhost:7687".to_string()
}
