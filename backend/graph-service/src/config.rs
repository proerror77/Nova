use serde::Deserialize;
use std::env;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// gRPC server configuration
    pub server: ServerConfig,
    /// Neo4j connection configuration, flattened from NEO4J_* env vars
    #[serde(flatten)]
    pub neo4j: Neo4jConfig,
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

        Ok(Self {
            server: ServerConfig { grpc_port },
            neo4j: Neo4jConfig { uri, user, password },
        })
    }
}
