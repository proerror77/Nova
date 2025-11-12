//! Builder pattern for easy health manager construction

use crate::checks::{KafkaHealthCheck, PostgresHealthCheck, RedisHealthCheck};
use crate::manager::HealthManager;
use redis::aio::ConnectionManager;
use sqlx::PgPool;
use tonic_health::pb::health_server::{Health, HealthServer};

/// Builder for HealthManager with common dependency checks
///
/// Provides a fluent API for constructing a HealthManager with
/// pre-configured health checks for common dependencies.
///
/// # Example
///
/// ```rust,no_run
/// use grpc_health::HealthManagerBuilder;
/// use sqlx::PgPool;
///
/// # async fn example() -> anyhow::Result<()> {
/// # let database_url = "postgres://localhost/db";
/// # let redis_url = "redis://localhost";
/// let pg_pool = PgPool::connect(database_url).await?;
/// let redis_client = redis::Client::open(redis_url)?
///     .get_tokio_connection_manager()
///     .await?;
///
/// let (health_manager, health_service) = HealthManagerBuilder::new()
///     .with_postgres(pg_pool)
///     .with_redis(redis_client)
///     .with_kafka("localhost:9092")
///     .build()
///     .await;
/// # Ok(())
/// # }
/// ```
pub struct HealthManagerBuilder {
    postgres: Option<PgPool>,
    redis: Option<ConnectionManager>,
    kafka_brokers: Option<String>,
}

impl HealthManagerBuilder {
    /// Create a new builder
    pub fn new() -> Self {
        Self {
            postgres: None,
            redis: None,
            kafka_brokers: None,
        }
    }

    /// Add PostgreSQL health check
    ///
    /// # Arguments
    ///
    /// * `pool` - PostgreSQL connection pool
    pub fn with_postgres(mut self, pool: PgPool) -> Self {
        self.postgres = Some(pool);
        self
    }

    /// Add Redis health check
    ///
    /// # Arguments
    ///
    /// * `client` - Redis connection manager
    pub fn with_redis(mut self, client: ConnectionManager) -> Self {
        self.redis = Some(client);
        self
    }

    /// Add Kafka health check
    ///
    /// # Arguments
    ///
    /// * `brokers` - Comma-separated list of Kafka brokers (e.g., "localhost:9092")
    pub fn with_kafka(mut self, brokers: impl Into<String>) -> Self {
        self.kafka_brokers = Some(brokers.into());
        self
    }

    /// Build the HealthManager with all configured checks
    ///
    /// Returns a tuple of (HealthManager, HealthServer) where HealthServer
    /// should be added to your gRPC server.
    pub async fn build(self) -> (HealthManager, HealthServer<impl Health>) {
        let (manager, service) = HealthManager::new();

        if let Some(pool) = self.postgres {
            manager
                .register_check(Box::new(PostgresHealthCheck::new(pool)))
                .await;
        }

        if let Some(client) = self.redis {
            manager
                .register_check(Box::new(RedisHealthCheck::new(client)))
                .await;
        }

        if let Some(brokers) = self.kafka_brokers {
            manager
                .register_check(Box::new(KafkaHealthCheck::new(brokers)))
                .await;
        }

        (manager, service)
    }
}

impl Default for HealthManagerBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_builder_with_no_checks() {
        let (manager, _service) = HealthManagerBuilder::new().build().await;

        // Should be able to execute checks even with no registered checks
        let result = manager.execute_checks().await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_builder_default() {
        let _builder = HealthManagerBuilder::default();
    }
}
