//! Shared testcontainers fixtures for integration tests
//!
//! Provides reusable container fixtures for Postgres and Redis to enable
//! integration tests to run in CI without manual infrastructure setup.

use testcontainers::{clients, images};
use std::sync::Arc;

/// PostgreSQL test container fixture
pub struct PostgresContainer {
    container: testcontainers::Container<'static, images::postgres::Postgres>,
    connection_string: String,
}

impl PostgresContainer {
    /// Start a new PostgreSQL container
    pub async fn start() -> Result<Self, Box<dyn std::error::Error>> {
        let docker = clients::Cli::default();
        let image = images::postgres::Postgres::default()
            .with_db_name("test_db")
            .with_user("testuser")
            .with_password("testpass");

        let container = docker.run(image);

        let port = container.get_host_port_ipv4(5432);
        let connection_string = format!(
            "postgresql://testuser:testpass@localhost:{}/test_db",
            port
        );

        Ok(PostgresContainer {
            container,
            connection_string,
        })
    }

    /// Get the connection string for this PostgreSQL container
    pub fn connection_string(&self) -> &str {
        &self.connection_string
    }

    /// Wait for the database to be ready (with retries)
    pub async fn wait_ready(&self) -> Result<(), Box<dyn std::error::Error>> {
        let mut retries = 0;
        const MAX_RETRIES: u32 = 30;

        loop {
            match sqlx::postgres::PgPool::connect(&self.connection_string).await {
                Ok(_) => {
                    tracing::info!("PostgreSQL container ready at {}", self.connection_string);
                    return Ok(());
                }
                Err(e) if retries < MAX_RETRIES => {
                    retries += 1;
                    tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
                }
                Err(e) => return Err(format!("Failed to connect to PostgreSQL: {}", e).into()),
            }
        }
    }
}

/// Redis test container fixture
pub struct RedisContainer {
    container: testcontainers::Container<'static, images::redis::Redis>,
    connection_string: String,
}

impl RedisContainer {
    /// Start a new Redis container
    pub async fn start() -> Result<Self, Box<dyn std::error::Error>> {
        let docker = clients::Cli::default();
        let image = images::redis::Redis::default();
        let container = docker.run(image);

        let port = container.get_host_port_ipv4(6379);
        let connection_string = format!("redis://localhost:{}", port);

        Ok(RedisContainer {
            container,
            connection_string,
        })
    }

    /// Get the connection string for this Redis container
    pub fn connection_string(&self) -> &str {
        &self.connection_string
    }

    /// Wait for Redis to be ready (with retries)
    pub async fn wait_ready(&self) -> Result<(), Box<dyn std::error::Error>> {
        let mut retries = 0;
        const MAX_RETRIES: u32 = 30;

        loop {
            match redis::Client::open(self.connection_string.as_str()) {
                Ok(client) => {
                    match client.get_connection() {
                        Ok(mut conn) => {
                            if redis::cmd("PING").query::<String>(&mut conn).is_ok() {
                                tracing::info!("Redis container ready at {}", self.connection_string);
                                return Ok(());
                            }
                        }
                        Err(_) if retries < MAX_RETRIES => {
                            retries += 1;
                            tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
                        }
                        Err(e) => return Err(format!("Failed to connect to Redis: {}", e).into()),
                    }
                }
                Err(e) if retries < MAX_RETRIES => {
                    retries += 1;
                    tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
                }
                Err(e) => return Err(format!("Failed to parse Redis connection string: {}", e).into()),
            }
        }
    }
}

/// Combined test environment with both PostgreSQL and Redis
pub struct TestEnvironment {
    pub postgres: PostgresContainer,
    pub redis: RedisContainer,
}

impl TestEnvironment {
    /// Start a complete test environment with both databases
    pub async fn start() -> Result<Self, Box<dyn std::error::Error>> {
        let postgres = PostgresContainer::start().await?;
        postgres.wait_ready().await?;

        let redis = RedisContainer::start().await?;
        redis.wait_ready().await?;

        Ok(TestEnvironment { postgres, redis })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Only run with `--ignored` flag for manual testing
    async fn test_postgres_container_starts() {
        let container = PostgresContainer::start().await.expect("Failed to start PostgreSQL");
        let result = container.wait_ready().await;
        assert!(result.is_ok(), "PostgreSQL container should be ready");
    }

    #[tokio::test]
    #[ignore] // Only run with `--ignored` flag for manual testing
    async fn test_redis_container_starts() {
        let container = RedisContainer::start().await.expect("Failed to start Redis");
        let result = container.wait_ready().await;
        assert!(result.is_ok(), "Redis container should be ready");
    }
}
