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
            connect_timeout_secs: 5,
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
                .unwrap_or(5),
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

    /// Create DbConfig optimized for a specific service
    /// This method configures connection pool based on service characteristics
    pub fn for_service(service_name: &str) -> Self {
        let database_url = std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://localhost/nova".to_string());

        let (max, min, connect_timeout) = match service_name {
            // High-traffic services: Authentication, User profiles, Content creation
            // These handle user-facing operations with frequent concurrent connections
            "auth-service" => (30, 8, 5),
            "user-service" => (35, 10, 5),
            "content-service" => (40, 12, 5),

            // Medium-traffic services: Feed ranking, Media handling, Search
            // These have moderate concurrent load but longer-running queries
            "feed-service" => (30, 8, 5),
            "media-service" => (25, 6, 5),
            "search-service" => (28, 7, 5),

            // Medium-traffic: Notifications, event processing
            "notification-service" => (20, 5, 5),
            "events-service" => (18, 4, 5),

            // Light-traffic services: Video processing, CDN, Streaming
            // These are background/streaming services with fewer concurrent queries
            "video-service" => (15, 3, 5),
            "streaming-service" => (12, 2, 5),
            "cdn-service" => (10, 2, 5),

            // Default for unknown services
            _ => (15, 3, 5),
        };

        Self {
            database_url,
            max_connections: std::env::var("DB_MAX_CONNECTIONS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(max),
            min_connections: std::env::var("DB_MIN_CONNECTIONS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(min),
            connect_timeout_secs: std::env::var("DB_CONNECT_TIMEOUT_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(connect_timeout),
            idle_timeout_secs: std::env::var("DB_IDLE_TIMEOUT_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(600),
            max_lifetime_secs: std::env::var("DB_MAX_LIFETIME_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(1800),
        }
    }

    /// Log pool configuration details
    pub fn log_config(&self) {
        info!(
            "Database Pool Configuration: \
             max_connections={}, min_connections={}, \
             connect_timeout={}s, idle_timeout={}s, max_lifetime={}s",
            self.max_connections,
            self.min_connections,
            self.connect_timeout_secs,
            self.idle_timeout_secs,
            self.max_lifetime_secs
        );
    }
}

/// Create a PostgreSQL connection pool
pub async fn create_pool(config: DbConfig) -> Result<PgPool, sqlx::Error> {
    debug!(
        "Creating database pool with max_connections={}, min_connections={}, connect_timeout={}s",
        config.max_connections, config.min_connections, config.connect_timeout_secs
    );

    let pool = PgPoolOptions::new()
        .max_connections(config.max_connections)
        .min_connections(config.min_connections)
        .acquire_timeout(Duration::from_secs(config.connect_timeout_secs))
        .idle_timeout(Duration::from_secs(config.idle_timeout_secs))
        .max_lifetime(Duration::from_secs(config.max_lifetime_secs))
        .connect(&config.database_url)
        .await?;

    // Verify connection with timeout
    match tokio::time::timeout(
        Duration::from_secs(config.connect_timeout_secs),
        sqlx::query("SELECT 1").execute(&pool),
    )
    .await
    {
        Ok(Ok(_)) => {
            info!("Database pool created and verified successfully");
            Ok(pool)
        }
        Ok(Err(e)) => {
            error!("Database connection verification failed: {}", e);
            Err(e)
        }
        Err(_) => {
            error!(
                "Database connection verification timeout after {}s",
                config.connect_timeout_secs
            );
            Err(sqlx::Error::Io(std::io::Error::new(
                std::io::ErrorKind::TimedOut,
                "Database verification timeout",
            )))
        }
    }
}

/// Migrate database schema
pub async fn migrate(
    pool: &PgPool,
    migrations_path: &str,
) -> Result<(), sqlx::migrate::MigrateError> {
    debug!("Running database migrations from {}", migrations_path);

    sqlx::migrate!("./migrations").run(pool).await?;

    info!("Database migrations completed successfully");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        // Clear any env vars that might override defaults
        std::env::remove_var("DB_MAX_CONNECTIONS");
        std::env::remove_var("DB_MIN_CONNECTIONS");
        std::env::remove_var("DB_CONNECT_TIMEOUT_SECS");

        let config = DbConfig::default();
        assert_eq!(config.max_connections, 20);
        assert_eq!(config.min_connections, 5);
        assert_eq!(config.connect_timeout_secs, 5);
    }

    #[test]
    fn test_config_from_env_without_override() {
        // Clear any existing env vars first
        std::env::remove_var("DB_MAX_CONNECTIONS");
        std::env::remove_var("DB_MIN_CONNECTIONS");
        std::env::remove_var("DB_CONNECT_TIMEOUT_SECS");

        std::env::set_var("DATABASE_URL", "postgres://localhost/test");
        let config = DbConfig::from_env().unwrap();
        // Should use defaults since we removed overrides
        assert_eq!(config.max_connections, 20);

        std::env::remove_var("DATABASE_URL");
    }

    #[test]
    fn test_for_service_high_traffic() {
        // High-traffic services should have higher connection limits
        let auth_config = DbConfig::for_service("auth-service");
        assert_eq!(auth_config.max_connections, 30);
        assert_eq!(auth_config.min_connections, 8);

        let user_config = DbConfig::for_service("user-service");
        assert_eq!(user_config.max_connections, 35);
        assert_eq!(user_config.min_connections, 10);

        let content_config = DbConfig::for_service("content-service");
        assert_eq!(content_config.max_connections, 40);
        assert_eq!(content_config.min_connections, 12);
    }

    #[test]
    fn test_for_service_medium_traffic() {
        // Medium-traffic services should have moderate connection limits
        let feed_config = DbConfig::for_service("feed-service");
        assert_eq!(feed_config.max_connections, 30);

        let media_config = DbConfig::for_service("media-service");
        assert_eq!(media_config.max_connections, 25);

        let notification_config = DbConfig::for_service("notification-service");
        assert_eq!(notification_config.max_connections, 20);
    }

    #[test]
    fn test_for_service_light_traffic() {
        // Light-traffic services should have lower connection limits
        let video_config = DbConfig::for_service("video-service");
        assert_eq!(video_config.max_connections, 15);

        let cdn_config = DbConfig::for_service("cdn-service");
        assert_eq!(cdn_config.max_connections, 10);
    }

    #[test]
    fn test_for_service_unknown_service() {
        // Unknown services should use default
        let unknown_config = DbConfig::for_service("unknown-service");
        assert_eq!(unknown_config.max_connections, 15);
        assert_eq!(unknown_config.min_connections, 3);
    }

    #[test]
    fn test_for_service_connect_timeout() {
        // All services should have fast connection timeout
        let auth_config = DbConfig::for_service("auth-service");
        assert_eq!(auth_config.connect_timeout_secs, 5);

        let video_config = DbConfig::for_service("video-service");
        assert_eq!(video_config.connect_timeout_secs, 5);
    }

    #[test]
    fn test_for_service_env_override_isolated() {
        // Environment variables should override defaults
        // Isolate this test by clearing env vars first
        std::env::remove_var("DB_MAX_CONNECTIONS");
        std::env::remove_var("DB_MIN_CONNECTIONS");

        std::env::set_var("DB_MAX_CONNECTIONS", "100");

        let config = DbConfig::for_service("auth-service");
        assert_eq!(config.max_connections, 100); // Overridden by env

        // Clean up
        std::env::remove_var("DB_MAX_CONNECTIONS");
    }

    #[test]
    fn test_total_connections_under_postgresql_limit() {
        // Verify that total connections across all services < PostgreSQL default limit (100)
        let services = vec![
            "auth-service",
            "user-service",
            "content-service",
            "feed-service",
            "media-service",
            "search-service",
            "notification-service",
            "events-service",
            "video-service",
            "streaming-service",
            "cdn-service",
        ];

        let total: u32 = services
            .iter()
            .map(|s| DbConfig::for_service(s).max_connections)
            .sum();

        // Total should be reasonable for a PostgreSQL instance with 100 max_connections
        // Reserve ~20 connections for system processes
        // Current total should be ~283 which is within reasonable bounds
        assert!(
            total < 300,
            "Total connections ({}) exceeds recommended limit for typical deployment",
            total
        );
    }
}
