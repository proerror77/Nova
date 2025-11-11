//! Configuration for GraphQL Gateway

use serde::{Deserialize, Serialize};
use std::env;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Server configuration
    pub server: ServerConfig,

    /// Service endpoints
    pub services: ServiceEndpoints,

    /// Database configuration (for caching)
    pub database: DatabaseConfig,

    /// JWT configuration
    pub jwt: JwtConfig,

    /// GraphQL configuration
    pub graphql: GraphQLConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub workers: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceEndpoints {
    pub auth_service: String,
    pub user_service: String,
    pub content_service: String,
    pub messaging_service: String,
    pub notification_service: String,
    pub feed_service: String,
    pub video_service: String,
    pub media_service: String,
    pub streaming_service: String,
    pub search_service: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
    pub min_connections: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JwtConfig {
    pub secret: String,
    pub issuer: String,
    pub audience: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphQLConfig {
    /// Enable GraphQL Playground
    pub playground: bool,
    /// Max query depth
    pub max_depth: usize,
    /// Max query complexity
    pub max_complexity: usize,
    /// Enable introspection
    pub introspection: bool,
}

impl Config {
    /// Load configuration from environment variables
    pub fn from_env() -> Result<Self, anyhow::Error> {
        dotenv::dotenv().ok();

        Ok(Self {
            server: ServerConfig {
                host: env::var("SERVER_HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
                port: env::var("SERVER_PORT")
                    .ok()
                    .and_then(|p| p.parse().ok())
                    .unwrap_or(8080),
                workers: env::var("SERVER_WORKERS")
                    .ok()
                    .and_then(|w| w.parse().ok())
                    .unwrap_or(num_cpus::get()),
            },
            services: ServiceEndpoints {
                auth_service: env::var("AUTH_SERVICE_URL")
                    .unwrap_or_else(|_| "http://auth-service:50051".to_string()),
                user_service: env::var("USER_SERVICE_URL")
                    .unwrap_or_else(|_| "http://user-service:50052".to_string()),
                content_service: env::var("CONTENT_SERVICE_URL")
                    .unwrap_or_else(|_| "http://content-service:50053".to_string()),
                messaging_service: env::var("MESSAGING_SERVICE_URL")
                    .unwrap_or_else(|_| "http://messaging-service:50054".to_string()),
                notification_service: env::var("NOTIFICATION_SERVICE_URL")
                    .unwrap_or_else(|_| "http://notification-service:50055".to_string()),
                feed_service: env::var("FEED_SERVICE_URL")
                    .unwrap_or_else(|_| "http://feed-service:50056".to_string()),
                video_service: env::var("VIDEO_SERVICE_URL")
                    .unwrap_or_else(|_| "http://video-service:50057".to_string()),
                media_service: env::var("MEDIA_SERVICE_URL")
                    .unwrap_or_else(|_| "http://media-service:50058".to_string()),
                streaming_service: env::var("STREAMING_SERVICE_URL")
                    .unwrap_or_else(|_| "http://streaming-service:50059".to_string()),
                search_service: env::var("SEARCH_SERVICE_URL")
                    .unwrap_or_else(|_| "http://search-service:50060".to_string()),
            },
            database: DatabaseConfig {
                url: env::var("DATABASE_URL")
                    .unwrap_or_else(|_| "postgres://postgres:password@localhost/nova".to_string()),
                max_connections: env::var("DB_MAX_CONNECTIONS")
                    .ok()
                    .and_then(|c| c.parse().ok())
                    .unwrap_or(10),
                min_connections: env::var("DB_MIN_CONNECTIONS")
                    .ok()
                    .and_then(|c| c.parse().ok())
                    .unwrap_or(2),
            },
            jwt: JwtConfig {
                secret: env::var("JWT_SECRET")
                    .expect("JWT_SECRET must be set"),
                issuer: env::var("JWT_ISSUER")
                    .unwrap_or_else(|_| "nova-graphql-gateway".to_string()),
                audience: env::var("JWT_AUDIENCE")
                    .unwrap_or_else(|_| "nova-api".to_string()),
            },
            graphql: GraphQLConfig {
                playground: env::var("GRAPHQL_PLAYGROUND")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(true),
                max_depth: env::var("GRAPHQL_MAX_DEPTH")
                    .ok()
                    .and_then(|d| d.parse().ok())
                    .unwrap_or(10),
                max_complexity: env::var("GRAPHQL_MAX_COMPLEXITY")
                    .ok()
                    .and_then(|c| c.parse().ok())
                    .unwrap_or(1000),
                introspection: env::var("GRAPHQL_INTROSPECTION")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(true),
            },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_defaults() {
        // This will use defaults for missing env vars
        let config = Config::from_env();
        assert!(config.is_ok());
    }
}
