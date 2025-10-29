//! Database connection pool management
//!
//! Provides unified database pool creation and configuration for all services

use sqlx::postgres::{PgPool, PgPoolOptions};
use std::time::Duration;
use tracing::{debug, error, info};

/// Database connection pool configuration
#[derive(Debug, Clone)]
pub struct DbConfig {
    /// PostgreSQL connection URL
    pub database_url: String,
    /// Maximum number of connections
    pub max_connections: u32,
    /// Minimum number of connections
    pub min_connections: u32,
    /// Connection acquisition timeout
    pub connect_timeout_secs: u64,
    /// Connection idle timeout
    pub idle_timeout_secs: u64,
    /// Connection maximum lifetime
    pub max_lifetime_secs: u64,
}

impl Default for DbConfig {
    fn default() -> Self {
        Self {
            database_url: String::new(),
            max_connections: 20,
            min_connections: 5,
            connect_timeout_secs: 30,
            idle_timeout_secs: 600,
            max_lifetime_secs: 1800,
        }
    }
}

impl DbConfig {
    /// Create a new DbConfig from environment variables
    pub fn from_env() -> Result<Self, String> {
        let database_url = std::env::var("DATABASE_URL")
            .map_err(|_| "DATABASE_URL environment variable not set".to_string())?;

        Ok(Self {
            database_url,
            max_connections: std::env::var("DB_MAX_CONNECTIONS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(20),
            min_connections: std::env::var("DB_MIN_CONNECTIONS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(5),
            connect_timeout_secs: std::env::var("DB_CONNECT_TIMEOUT_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(30),
            idle_timeout_secs: std::env::var("DB_IDLE_TIMEOUT_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(600),
            max_lifetime_secs: std::env::var("DB_MAX_LIFETIME_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(1800),
        })
    }
}

/// Create a PostgreSQL connection pool
pub async fn create_pool(config: DbConfig) -> Result<PgPool, sqlx::Error> {
    debug!(
        "Creating database pool with max_connections={}, min_connections={}",
        config.max_connections, config.min_connections
    );

    let pool = PgPoolOptions::new()
        .max_connections(config.max_connections)
        .min_connections(config.min_connections)
        .idle_timeout(Duration::from_secs(config.idle_timeout_secs))
        .max_lifetime(Duration::from_secs(config.max_lifetime_secs))
        .connect(&config.database_url)
        .await?;

    // Verify connection
    sqlx::query("SELECT 1")
        .execute(&pool)
        .await
        .map_err(|e| {
            error!("Database connection verification failed: {}", e);
            e
        })?;

    info!("Database pool created successfully");
    Ok(pool)
}

/// Migrate database schema
pub async fn migrate(pool: &PgPool, migrations_path: &str) -> Result<(), sqlx::migrate::MigrateError> {
    debug!("Running database migrations from {}", migrations_path);

    sqlx::migrate!("./migrations")
        .run(pool)
        .await?;

    info!("Database migrations completed successfully");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = DbConfig::default();
        assert_eq!(config.max_connections, 20);
        assert_eq!(config.min_connections, 5);
        assert_eq!(config.connect_timeout_secs, 30);
    }

    #[test]
    fn test_config_from_env() {
        std::env::set_var("DATABASE_URL", "postgres://localhost/test");
        std::env::set_var("DB_MAX_CONNECTIONS", "50");

        let config = DbConfig::from_env().unwrap();
        assert_eq!(config.max_connections, 50);

        std::env::remove_var("DATABASE_URL");
        std::env::remove_var("DB_MAX_CONNECTIONS");
    }
}
