//! Health check implementations for external dependencies

use crate::error::{HealthCheckError, Result};
use async_trait::async_trait;
use rdkafka::admin::AdminClient;
use rdkafka::client::DefaultClientContext;
use rdkafka::config::ClientConfig;
use redis::aio::ConnectionManager;
use sqlx::PgPool;
use std::time::Duration;

/// Trait for health check implementations
///
/// Implement this trait to create custom health checks for your dependencies.
#[async_trait]
pub trait HealthCheck: Send + Sync {
    /// Perform the health check
    ///
    /// Returns `Ok(())` if the dependency is healthy, or an error describing the problem.
    async fn check(&self) -> Result<()>;
}

/// PostgreSQL health check
///
/// Verifies database connectivity by executing a simple query.
pub struct PostgresHealthCheck {
    pool: PgPool,
}

impl PostgresHealthCheck {
    /// Create a new PostgreSQL health check
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl HealthCheck for PostgresHealthCheck {
    async fn check(&self) -> Result<()> {
        sqlx::query("SELECT 1")
            .execute(&self.pool)
            .await
            .map_err(|e| HealthCheckError::database(format!("Failed to execute health check query: {}", e)))?;

        Ok(())
    }
}

/// Redis health check
///
/// Verifies Redis connectivity by sending a PING command.
pub struct RedisHealthCheck {
    client: ConnectionManager,
}

impl RedisHealthCheck {
    /// Create a new Redis health check
    pub fn new(client: ConnectionManager) -> Self {
        Self { client }
    }
}

#[async_trait]
impl HealthCheck for RedisHealthCheck {
    async fn check(&self) -> Result<()> {
        let mut conn = self.client.clone();
        redis::cmd("PING")
            .query_async::<_, String>(&mut conn)
            .await
            .map_err(|e| HealthCheckError::cache(format!("Failed to ping Redis: {}", e)))?;

        Ok(())
    }
}

/// Kafka health check
///
/// Verifies Kafka connectivity by fetching cluster metadata.
pub struct KafkaHealthCheck {
    brokers: String,
}

impl KafkaHealthCheck {
    /// Create a new Kafka health check
    ///
    /// # Arguments
    ///
    /// * `brokers` - Comma-separated list of Kafka brokers (e.g., "localhost:9092,localhost:9093")
    pub fn new(brokers: impl Into<String>) -> Self {
        Self {
            brokers: brokers.into(),
        }
    }
}

#[async_trait]
impl HealthCheck for KafkaHealthCheck {
    async fn check(&self) -> Result<()> {
        let brokers = self.brokers.clone();

        // Fetch cluster metadata in blocking context
        let result = tokio::task::spawn_blocking(move || {
            // Create AdminClient for metadata queries
            let admin: AdminClient<DefaultClientContext> = ClientConfig::new()
                .set("bootstrap.servers", &brokers)
                .set("request.timeout.ms", "5000")
                .create()
                .map_err(|e| format!("Failed to create Kafka admin client: {}", e))?;

            // Fetch cluster metadata
            let metadata = admin
                .inner()
                .fetch_metadata(None, Duration::from_secs(5))
                .map_err(|e| format!("Failed to fetch Kafka metadata: {}", e))?;

            // Verify at least one broker is available
            if metadata.brokers().is_empty() {
                return Err("No Kafka brokers available".to_string());
            }

            Ok(())
        })
        .await
        .map_err(|e| HealthCheckError::message_queue(format!("Failed to join task: {}", e)))?;

        result.map_err(HealthCheckError::message_queue)?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_postgres_health_check_with_invalid_pool() {
        // This test verifies error handling, not actual database connection
        // In real tests, you would use a test database or mock
        let pool = PgPool::connect("postgres://invalid:invalid@localhost:5432/invalid")
            .await;

        // If connection fails (expected), we test error handling
        if let Ok(pool) = pool {
            let check = PostgresHealthCheck::new(pool);
            // May fail if no database is running, which is fine for this test
            let _ = check.check().await;
        }
    }

    #[tokio::test]
    async fn test_redis_health_check_creation() {
        // Test that we can create a health check instance
        // Actual connection testing requires a running Redis instance
        let client = redis::Client::open("redis://localhost:6379");

        if let Ok(client) = client {
            if let Ok(manager) = client.get_connection_manager().await {
                let check = RedisHealthCheck::new(manager);
                // May fail if no Redis is running, which is fine for this test
                let _ = check.check().await;
            }
        }
    }

    #[test]
    fn test_kafka_health_check_creation() {
        // Test that we can create a health check instance
        let check = KafkaHealthCheck::new("localhost:9092");
        assert_eq!(check.brokers, "localhost:9092");
    }
}
