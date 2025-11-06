//! Shared testcontainers fixtures for integration tests
//!
//! Provides reusable container fixtures for Postgres and Redis to enable
//! integration tests to run in CI without manual infrastructure setup.

use std::sync::Arc;
use testcontainers::core::WaitFor;
use testcontainers::{runners::AsyncRunner, GenericImage};

/// PostgreSQL test container fixture
pub struct PostgresContainer {
    _container: Arc<dyn std::any::Any + Send>,
    connection_string: String,
}

impl PostgresContainer {
    /// Start a new PostgreSQL container
    pub async fn start() -> Result<Self, Box<dyn std::error::Error>> {
        let image = GenericImage::new("postgres", "15-alpine")
            .with_env_var("POSTGRES_DB", "test_db")
            .with_env_var("POSTGRES_USER", "testuser")
            .with_env_var("POSTGRES_PASSWORD", "testpass")
            .with_wait_for(WaitFor::message_on_stderr(
                "database system is ready to accept connections",
            ));

        let container = image.start().await?;
        let port = container.get_host_port_ipv4(5432).await?;
        let connection_string =
            format!("postgresql://testuser:testpass@localhost:{}/test_db", port);

        Ok(Self {
            _container: Arc::new(container),
            connection_string,
        })
    }

    /// Get the connection string for this container
    pub fn connection_string(&self) -> &str {
        &self.connection_string
    }
}

/// Redis test container fixture
pub struct RedisContainer {
    _container: Arc<dyn std::any::Any + Send>,
    connection_string: String,
}

impl RedisContainer {
    /// Start a new Redis container
    pub async fn start() -> Result<Self, Box<dyn std::error::Error>> {
        let image = GenericImage::new("redis", "7-alpine")
            .with_wait_for(WaitFor::message_on_stdout("Ready to accept connections"));

        let container = image.start().await?;
        let port = container.get_host_port_ipv4(6379).await?;
        let connection_string = format!("redis://localhost:{}", port);

        Ok(Self {
            _container: Arc::new(container),
            connection_string,
        })
    }

    /// Get the connection string for this container
    pub fn connection_string(&self) -> &str {
        &self.connection_string
    }
}
