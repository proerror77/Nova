use serde::Deserialize;
use std::env;

fn default_redis_url() -> String {
    env::var("REDIS_URL").unwrap_or_else(|_| "redis://redis:6379".to_string())
}

fn default_cache_enabled() -> bool {
    env::var("CACHE_ENABLED")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(true)
}

fn default_grpc_port() -> u16 {
    env::var("SERVER_GRPC_PORT")
        .ok()
        .and_then(|v| v.parse::<u16>().ok())
        .unwrap_or(9080)
}

fn default_neo4j_uri() -> String {
    env::var("NEO4J_URI").unwrap_or_else(|_| "bolt://neo4j:7687".to_string())
}

fn default_neo4j_user() -> String {
    env::var("NEO4J_USER").unwrap_or_else(|_| "neo4j".to_string())
}

fn default_neo4j_password() -> String {
    env::var("NEO4J_PASSWORD").unwrap_or_else(|_| "CHANGE_ME".to_string())
}

fn default_database_url() -> String {
    env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nova:nova123@postgres:5432/nova_graph".to_string())
}

fn default_enable_dual_write() -> bool {
    env::var("ENABLE_DUAL_WRITE")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(true) // Default to enabled
}

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// gRPC server configuration
    pub server: ServerConfig,
    /// Neo4j connection configuration, flattened from NEO4J_* env vars
    #[serde(flatten)]
    pub neo4j: Neo4jConfig,
    /// Redis configuration
    #[serde(flatten)]
    pub redis: RedisConfig,
    /// PostgreSQL connection string
    #[serde(rename = "DATABASE_URL", default = "default_database_url")]
    pub database_url: String,
    /// Enable dual-write mode (PostgreSQL + Neo4j)
    #[serde(rename = "ENABLE_DUAL_WRITE", default = "default_enable_dual_write")]
    pub enable_dual_write: bool,
    /// Internal token required for write operations; if absent, writes are disabled.
    #[serde(default)]
    pub internal_write_token: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RedisConfig {
    /// Redis connection URL
    #[serde(rename = "REDIS_URL", default = "default_redis_url")]
    pub url: String,
    /// Enable caching (can be disabled for debugging)
    #[serde(rename = "CACHE_ENABLED", default = "default_cache_enabled")]
    pub enabled: bool,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct ServerConfig {
    /// gRPC port, defaults to 9080 when not set
    #[serde(rename = "SERVER_GRPC_PORT", default = "default_grpc_port")]
    pub grpc_port: u16,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Neo4jConfig {
    /// Neo4j bolt URI, e.g. bolt://neo4j:7687
    #[serde(rename = "NEO4J_URI", default = "default_neo4j_uri")]
    pub uri: String,
    /// Neo4j username from secret
    #[serde(rename = "NEO4J_USER", default = "default_neo4j_user")]
    pub user: String,
    /// Neo4j password from secret
    #[serde(rename = "NEO4J_PASSWORD", default = "default_neo4j_password")]
    pub password: String,
}

impl Config {
    pub fn from_env() -> Result<Self, anyhow::Error> {
        // SERVER_GRPC_PORT is optional; default to 9080
        let grpc_port = env::var("SERVER_GRPC_PORT")
            .ok()
            .and_then(|v| v.parse::<u16>().ok())
            .unwrap_or(9080);

        // NEO4J_* variables: use env when present, otherwise sensible defaults so
        // the service can still start (and fail health checks) instead of CrashLooping.
        let uri = env::var("NEO4J_URI").unwrap_or_else(|_| "bolt://neo4j:7687".to_string());
        let user = env::var("NEO4J_USER").unwrap_or_else(|_| "neo4j".to_string());
        let password = env::var("NEO4J_PASSWORD").unwrap_or_else(|_| "CHANGE_ME".to_string());

        // PostgreSQL DATABASE_URL
        let database_url = env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nova:nova123@postgres:5432/nova_graph".to_string());

        // Dual-write mode (default enabled)
        let enable_dual_write = env::var("ENABLE_DUAL_WRITE")
            .ok()
            .and_then(|v| v.parse::<bool>().ok())
            .unwrap_or(true);

        let internal_write_token = env::var("INTERNAL_GRAPH_WRITE_TOKEN").ok();

        // Redis configuration
        let redis_url = env::var("REDIS_URL").unwrap_or_else(|_| "redis://redis:6379".to_string());
        let cache_enabled = env::var("CACHE_ENABLED")
            .ok()
            .and_then(|v| v.parse::<bool>().ok())
            .unwrap_or(true);

        Ok(Self {
            server: ServerConfig { grpc_port },
            neo4j: Neo4jConfig {
                uri,
                user,
                password,
            },
            redis: RedisConfig {
                url: redis_url,
                enabled: cache_enabled,
            },
            database_url,
            enable_dual_write,
            internal_write_token,
        })
    }
}
