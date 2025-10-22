use dotenvy::dotenv;
use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub redis_url: String,
    pub kafka_brokers: String,
    pub port: u16,
}

impl Config {
    pub fn from_env() -> Result<Self, crate::error::AppError> {
        dotenv().ok();
        let database_url = env::var("DATABASE_URL")
            .map_err(|_| crate::error::AppError::Config("DATABASE_URL missing".into()))?;
        let redis_url = env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".into());
        let kafka_brokers = env::var("KAFKA_BROKERS").unwrap_or_else(|_| "localhost:9092".into());
        let port = env::var("PORT").ok().and_then(|s| s.parse().ok()).unwrap_or(3000);

        Ok(Self { database_url, redis_url, kafka_brokers, port })
    }
}

