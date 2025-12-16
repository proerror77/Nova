use serde::Deserialize;
use std::env;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub service: ServiceConfig,
    pub redis: RedisConfig,
    pub grpc_clients: GrpcClientsConfig,
    pub recall: RecallConfig,
    pub clickhouse: ClickHouseConfig,
    pub llm: LlmConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ClickHouseConfig {
    pub url: String,
    pub database: String,
    pub username: String,
    pub password: String,
    pub query_timeout_ms: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct LlmConfig {
    pub enabled: bool,
    pub provider: String, // "openai", "anthropic", "local"
    pub api_key: String,
    pub model: String,
    pub embedding_model: String,
    pub max_tokens: u32,
    pub temperature: f32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServiceConfig {
    pub http_port: u16,
    pub grpc_port: u16,
    pub service_name: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RedisConfig {
    pub url: String,
    pub pool_size: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GrpcClientsConfig {
    pub graph_service_url: String,
    pub content_service_url: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RecallConfig {
    pub graph_recall_limit: i32,
    pub trending_recall_limit: i32,
    pub personalized_recall_limit: i32,
    pub graph_recall_weight: f32,
    pub trending_recall_weight: f32,
    pub personalized_recall_weight: f32,
}

impl Config {
    pub fn from_env() -> Result<Self, envy::Error> {
        dotenvy::dotenv().ok();

        Ok(Config {
            service: ServiceConfig {
                http_port: env::var("HTTP_PORT")
                    .unwrap_or_else(|_| "8011".to_string())
                    .parse()
                    .expect("HTTP_PORT must be a valid u16"),
                grpc_port: env::var("GRPC_PORT")
                    .unwrap_or_else(|_| "9011".to_string())
                    .parse()
                    .expect("GRPC_PORT must be a valid u16"),
                service_name: env::var("SERVICE_NAME")
                    .unwrap_or_else(|_| "ranking-service".to_string()),
            },
            redis: RedisConfig {
                url: env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".to_string()),
                pool_size: env::var("REDIS_POOL_SIZE")
                    .unwrap_or_else(|_| "10".to_string())
                    .parse()
                    .expect("REDIS_POOL_SIZE must be a valid u32"),
            },
            grpc_clients: GrpcClientsConfig {
                graph_service_url: env::var("GRAPH_SERVICE_URL")
                    .unwrap_or_else(|_| "http://localhost:9008".to_string()),
                content_service_url: env::var("CONTENT_SERVICE_URL")
                    .unwrap_or_else(|_| "http://localhost:9002".to_string()),
            },
            recall: RecallConfig {
                graph_recall_limit: env::var("GRAPH_RECALL_LIMIT")
                    .unwrap_or_else(|_| "200".to_string())
                    .parse()
                    .expect("GRAPH_RECALL_LIMIT must be a valid i32"),
                trending_recall_limit: env::var("TRENDING_RECALL_LIMIT")
                    .unwrap_or_else(|_| "100".to_string())
                    .parse()
                    .expect("TRENDING_RECALL_LIMIT must be a valid i32"),
                personalized_recall_limit: env::var("PERSONALIZED_RECALL_LIMIT")
                    .unwrap_or_else(|_| "100".to_string())
                    .parse()
                    .expect("PERSONALIZED_RECALL_LIMIT must be a valid i32"),
                graph_recall_weight: env::var("GRAPH_RECALL_WEIGHT")
                    .unwrap_or_else(|_| "0.6".to_string())
                    .parse()
                    .expect("GRAPH_RECALL_WEIGHT must be a valid f32"),
                trending_recall_weight: env::var("TRENDING_RECALL_WEIGHT")
                    .unwrap_or_else(|_| "0.3".to_string())
                    .parse()
                    .expect("TRENDING_RECALL_WEIGHT must be a valid f32"),
                personalized_recall_weight: env::var("PERSONALIZED_RECALL_WEIGHT")
                    .unwrap_or_else(|_| "0.1".to_string())
                    .parse()
                    .expect("PERSONALIZED_RECALL_WEIGHT must be a valid f32"),
            },
            clickhouse: ClickHouseConfig {
                url: env::var("CLICKHOUSE_URL")
                    .unwrap_or_else(|_| "http://localhost:8123".to_string()),
                database: env::var("CLICKHOUSE_DATABASE")
                    .unwrap_or_else(|_| "nova_feed".to_string()),
                username: env::var("CLICKHOUSE_USERNAME").unwrap_or_else(|_| "default".to_string()),
                password: env::var("CLICKHOUSE_PASSWORD").unwrap_or_else(|_| "".to_string()),
                query_timeout_ms: env::var("CLICKHOUSE_QUERY_TIMEOUT_MS")
                    .unwrap_or_else(|_| "30000".to_string())
                    .parse()
                    .expect("CLICKHOUSE_QUERY_TIMEOUT_MS must be a valid u64"),
            },
            llm: LlmConfig {
                enabled: env::var("LLM_ENABLED")
                    .unwrap_or_else(|_| "false".to_string())
                    .parse()
                    .unwrap_or(false),
                provider: env::var("LLM_PROVIDER").unwrap_or_else(|_| "anthropic".to_string()),
                api_key: env::var("LLM_API_KEY").unwrap_or_else(|_| "".to_string()),
                model: env::var("LLM_MODEL")
                    .unwrap_or_else(|_| "claude-3-haiku-20240307".to_string()),
                embedding_model: env::var("LLM_EMBEDDING_MODEL")
                    .unwrap_or_else(|_| "text-embedding-3-small".to_string()),
                max_tokens: env::var("LLM_MAX_TOKENS")
                    .unwrap_or_else(|_| "1024".to_string())
                    .parse()
                    .expect("LLM_MAX_TOKENS must be a valid u32"),
                temperature: env::var("LLM_TEMPERATURE")
                    .unwrap_or_else(|_| "0.3".to_string())
                    .parse()
                    .expect("LLM_TEMPERATURE must be a valid f32"),
            },
        })
    }
}
