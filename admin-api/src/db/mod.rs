use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

use crate::config::Config;

#[derive(Clone)]
pub struct Database {
    pub pg: PgPool,
    pub redis: redis::Client,
}

impl Database {
    pub async fn connect(config: &Config) -> anyhow::Result<Self> {
        // PostgreSQL connection
        let pg = PgPoolOptions::new()
            .max_connections(config.database.max_connections)
            .connect(&config.database.url)
            .await?;

        tracing::info!("PostgreSQL connection pool established");

        // Redis connection
        let redis = redis::Client::open(config.redis.url.as_str())?;

        tracing::info!("Redis client created");

        Ok(Self { pg, redis })
    }

    pub async fn run_migrations(&self) -> anyhow::Result<()> {
        tracing::info!("Running database migrations...");
        sqlx::migrate!("./migrations")
            .run(&self.pg)
            .await?;
        tracing::info!("Database migrations completed");
        Ok(())
    }

    pub async fn get_redis_conn(&self) -> anyhow::Result<redis::aio::MultiplexedConnection> {
        Ok(self.redis.get_multiplexed_async_connection().await?)
    }
}
