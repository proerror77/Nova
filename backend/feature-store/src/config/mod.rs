use anyhow::{anyhow, Result};
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    // HTTP server config
    pub http_host: String,
    pub http_port: u16,

    // gRPC server config
    pub grpc_host: String,
    pub grpc_port: u16,

    // PostgreSQL (for metadata)
    pub database_url: String,

    // Redis (hot features)
    pub redis_url: String,
    pub redis_default_ttl_seconds: u64,

    // ClickHouse (near-line features)
    pub clickhouse_url: String,
    pub clickhouse_database: String,
    pub clickhouse_sync_interval_seconds: u64,

    // Feature serving config
    pub feature_cache_size: usize,
    pub batch_fetch_max_size: usize,

    // Observability
    pub log_level: String,
    pub enable_metrics: bool,
}

impl Config {
    pub fn from_env() -> Result<Self, config::ConfigError> {
        dotenv::dotenv().ok();

        let config = config::Config::builder()
            .set_default("http_host", "0.0.0.0")?
            .set_default("http_port", 8010)?
            .set_default("grpc_host", "0.0.0.0")?
            .set_default("grpc_port", 9010)?
            .set_default("redis_default_ttl_seconds", 3600)? // 1 hour
            .set_default("clickhouse_database", "feature_store")?
            .set_default("clickhouse_sync_interval_seconds", 300)? // 5 minutes
            .set_default("feature_cache_size", 10000)?
            .set_default("batch_fetch_max_size", 100)?
            .set_default("log_level", "info")?
            .set_default("enable_metrics", true)?
            .add_source(config::Environment::default().separator("__"))
            .build()?;

        config.try_deserialize()
    }

    pub fn validate(&self) -> Result<()> {
        if self.http_port == 0 {
            return Err(anyhow!("HTTP port must be greater than 0"));
        }

        if self.grpc_port == 0 {
            return Err(anyhow!("gRPC port must be greater than 0"));
        }

        if self.database_url.is_empty() {
            return Err(anyhow!("Database URL is required"));
        }

        if self.redis_url.is_empty() {
            return Err(anyhow!("Redis URL is required"));
        }

        if self.clickhouse_url.is_empty() {
            return Err(anyhow!("ClickHouse URL is required"));
        }

        if self.batch_fetch_max_size == 0 || self.batch_fetch_max_size > 1000 {
            return Err(anyhow!("Batch fetch max size must be between 1 and 1000"));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_validation() {
        let config = Config {
            http_host: "0.0.0.0".to_string(),
            http_port: 8010,
            grpc_host: "0.0.0.0".to_string(),
            grpc_port: 9010,
            database_url: "postgres://localhost/test".to_string(),
            redis_url: "redis://localhost".to_string(),
            redis_default_ttl_seconds: 3600,
            clickhouse_url: "http://localhost:8123".to_string(),
            clickhouse_database: "feature_store".to_string(),
            clickhouse_sync_interval_seconds: 300,
            feature_cache_size: 10000,
            batch_fetch_max_size: 100,
            log_level: "info".to_string(),
            enable_metrics: true,
        };

        assert!(config.validate().is_ok());
    }

    #[test]
    fn test_invalid_batch_size() {
        let mut config = Config {
            http_host: "0.0.0.0".to_string(),
            http_port: 8010,
            grpc_host: "0.0.0.0".to_string(),
            grpc_port: 9010,
            database_url: "postgres://localhost/test".to_string(),
            redis_url: "redis://localhost".to_string(),
            redis_default_ttl_seconds: 3600,
            clickhouse_url: "http://localhost:8123".to_string(),
            clickhouse_database: "feature_store".to_string(),
            clickhouse_sync_interval_seconds: 300,
            feature_cache_size: 10000,
            batch_fetch_max_size: 0,
            log_level: "info".to_string(),
            enable_metrics: true,
        };

        assert!(config.validate().is_err());

        config.batch_fetch_max_size = 2000;
        assert!(config.validate().is_err());
    }
}
