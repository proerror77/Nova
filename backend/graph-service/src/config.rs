use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// gRPC server configuration, flattened so SERVER_GRPC_PORT maps correctly
    #[serde(flatten, default)]
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

fn default_grpc_port() -> u16 {
    9080
}

fn default_neo4j_uri() -> String {
    "bolt://neo4j:7687".to_string()
}

fn default_neo4j_user() -> String {
    "neo4j".to_string()
}

fn default_neo4j_password() -> String {
    "CHANGE_ME".to_string()
}

impl Config {
    pub fn from_env() -> Result<Self, envy::Error> {
        envy::from_env()
    }
}
