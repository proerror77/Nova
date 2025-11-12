use serde::Deserialize;
use std::env;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub service: ServiceConfig,
    pub redis: RedisConfig,
    pub grpc_clients: GrpcClientsConfig,
    pub recall: RecallConfig,
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
        dotenv::dotenv().ok();

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
        })
    }
}
