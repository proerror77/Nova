//! Database connection pool management
//!
//! Provides unified database pool creation and configuration for all services

mod metrics;

use metrics::update_pool_metrics;
pub use metrics::{
    acquire_with_backpressure, acquire_with_metrics, BackpressureConfig, PoolExhaustedError,
};

use deadpool_postgres::{Manager, ManagerConfig, Pool, RecyclingMethod};
use deadpool_postgres::tokio_postgres::{Config as PgConfig, NoTls};
pub use deadpool_postgres::PoolError;
use deadpool::managed::TimeoutType;
use std::time::Duration;
use tracing::{debug, error, info};

/// Database connection pool configuration
#[derive(Debug, Clone)]
pub struct DbConfig {
    /// Service name for metrics labeling
    pub service_name: String,
    /// PostgreSQL connection URL
    pub database_url: String,
    /// Maximum number of connections
    pub max_connections: u32,
    /// Minimum number of connections
    pub min_connections: u32,
    /// Connection creation timeout (new connection to PostgreSQL)
    pub connect_timeout_secs: u64,
    /// Connection acquisition timeout (get connection from pool)
    pub acquire_timeout_secs: u64,
    /// Connection idle timeout
    pub idle_timeout_secs: u64,
    /// Connection maximum lifetime
    pub max_lifetime_secs: u64,
}

impl Default for DbConfig {
    fn default() -> Self {
        Self {
            service_name: String::from("unknown"),
            database_url: String::new(),
            max_connections: 20,
            min_connections: 5,
            connect_timeout_secs: 5,
            acquire_timeout_secs: 10,
            idle_timeout_secs: 600,
            max_lifetime_secs: 1800,
        }
    }
}

impl DbConfig {
    /// Create a new DbConfig from environment variables
    pub fn from_env(service_name: &str) -> Result<Self, String> {
        let database_url = std::env::var("DATABASE_URL")
            .map_err(|_| "DATABASE_URL environment variable not set".to_string())?;

        Ok(Self {
            service_name: service_name.to_string(),
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
            acquire_timeout_secs: std::env::var("DB_ACQUIRE_TIMEOUT_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(10),
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
    ///
    /// Connection allocation strategy:
    /// - Reserve 20% of PostgreSQL max_connections (default 100) for system overhead
    /// - Allocate remaining 80 connections (80 max) across all services
    /// - Scale based on service traffic patterns
    ///
    /// Historical note: Previous total was 263 connections - far exceeding PostgreSQL's
    /// 100 connection default. This caused connection exhaustion in production.
    pub fn for_service(service_name: &str) -> Self {
        let database_url = std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://localhost/nova".to_string());

        // CRITICAL: Stay under PostgreSQL max_connections (default 100)
        // Reserve 25 for system + overhead = 75 available for application
        // Total new allocation: 75 connections (vs old 263, previous 111)
        let (max, min) = match service_name {
            // High-traffic services: 16% of total each
            "auth-service" => (12, 4),    // was 16 (30 originally)
            "user-service" => (12, 4),    // was 18 (35 originally)
            "content-service" => (12, 4), // was 18 (40 originally)

            // Medium-high traffic: 10-11% of total
            "feed-service" => (8, 3),   // was 12 (30 originally)
            "search-service" => (8, 3), // was 12 (28 originally)

            // Medium traffic: 6-7% of total
            "media-service" => (5, 2),        // was 8 (25 originally)
            "notification-service" => (5, 2), // was 8 (20 originally)
            "events-service" => (5, 2),       // was 8 (18 originally)

            // Light traffic: 3-4% of total
            "video-service" => (3, 1),     // was 4 (15 originally)
            "streaming-service" => (3, 1), // was 4 (12 originally)
            "cdn-service" => (2, 1),       // was 3 (10 originally)

            // Default for unknown services (very conservative)
            _ => (2, 1),
        };

        Self {
            service_name: service_name.to_string(),
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
                .unwrap_or(5),
            acquire_timeout_secs: std::env::var("DB_ACQUIRE_TIMEOUT_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(10),
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
             connect_timeout={}s, acquire_timeout={}s, idle_timeout={}s, max_lifetime={}s",
            self.max_connections,
            self.min_connections,
            self.connect_timeout_secs,
            self.acquire_timeout_secs,
            self.idle_timeout_secs,
            self.max_lifetime_secs
        );
    }
}

/// Create a PostgreSQL connection pool with automatic metrics monitoring
pub type PgPool = Pool;

/// Build a deadpool-postgres pool
pub async fn create_pool(config: DbConfig) -> Result<PgPool, PoolError> {
    debug!(
        "Creating database pool: service={}, max={}, min={}, \
         acquire_timeout={}s, verify_timeout={}s, idle_timeout={}s",
        config.service_name,
        config.max_connections,
        config.min_connections,
        config.acquire_timeout_secs,
        config.connect_timeout_secs,
        config.idle_timeout_secs
    );

    // Parse connection string into tokio_postgres Config
    let pg_config: PgConfig = config
        .database_url
        .parse()
        .map_err(|e: tokio_postgres::Error| PoolError::Backend(e))?;

    let mgr_config = ManagerConfig {
        recycling_method: RecyclingMethod::Fast,
    };
    let mgr = Manager::from_config(pg_config, NoTls, mgr_config);
    let pool = Pool::builder(mgr)
        .max_size(config.max_connections as usize)
        .build()
        .unwrap();

    // Verify connection with connect timeout
    match tokio::time::timeout(
        Duration::from_secs(config.connect_timeout_secs),
        async {
            let client = pool.get().await.map_err(|e| match e {
                deadpool::managed::PoolError::Backend(e) => PoolError::Backend(e),
                deadpool::managed::PoolError::Timeout(t) => PoolError::Timeout(t),
                _ => PoolError::Timeout(TimeoutType::Wait),
            })?;
            client.simple_query("SELECT 1").await.map_err(PoolError::Backend)?;
            Ok::<(), PoolError>(())
        },
    )
    .await
    {
        Ok(Ok(())) => {
            info!(
                service = %config.service_name,
                "Database pool created and verified successfully"
            );

            // Initialize metrics immediately
            update_pool_metrics(&pool, &config.service_name);

            // Start background metrics updater
            {
                let pool_clone = pool.clone();
                let service = config.service_name.clone();
                tokio::spawn(async move {
                    let mut interval = tokio::time::interval(Duration::from_secs(30));
                    loop {
                        interval.tick().await;
                        update_pool_metrics(&pool_clone, &service);
                    }
                });
            }

            Ok(pool)
        }
        Ok(Err(e)) => {
            error!(
                service = %config.service_name,
                error = %e,
                "Database connection verification failed"
            );
            Err(e)
        }
        Err(_) => {
            error!(
                service = %config.service_name,
                timeout_secs = config.connect_timeout_secs,
                "Database connection verification timeout"
            );
            Err(PoolError::Timeout(TimeoutType::Wait))
        }
    }
}

/// Migrate database schema
pub async fn migrate(_pool: &PgPool, _migrations_path: &str) -> Result<(), PoolError> {
    // TODO: replace sqlx migrate with custom runner if needed
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
        std::env::remove_var("DB_ACQUIRE_TIMEOUT_SECS");

        let config = DbConfig::default();
        assert_eq!(config.max_connections, 20);
        assert_eq!(config.min_connections, 5);
        assert_eq!(config.connect_timeout_secs, 5);
        assert_eq!(config.acquire_timeout_secs, 10);
    }

    #[test]
    #[serial_test::serial]
    fn test_config_from_env_without_override() {
        // Clear ALL related env vars to ensure clean state
        std::env::remove_var("DB_MAX_CONNECTIONS");
        std::env::remove_var("DB_MIN_CONNECTIONS");
        std::env::remove_var("DB_CONNECT_TIMEOUT_SECS");
        std::env::remove_var("DB_ACQUIRE_TIMEOUT_SECS");
        std::env::remove_var("DB_IDLE_TIMEOUT_SECS");
        std::env::remove_var("DB_MAX_LIFETIME_SECS");

        std::env::set_var("DATABASE_URL", "postgres://localhost/test");
        let config = DbConfig::from_env("test-service").unwrap();

        // Verify service name
        assert_eq!(config.service_name, "test-service");

        // Should use defaults since we removed all overrides
        assert_eq!(
            config.max_connections, 20,
            "Expected default max_connections=20"
        );
        assert_eq!(
            config.min_connections, 5,
            "Expected default min_connections=5"
        );
        assert_eq!(config.connect_timeout_secs, 5);
        assert_eq!(config.acquire_timeout_secs, 10);

        // Clean up
        std::env::remove_var("DATABASE_URL");
    }

    #[test]
    fn test_for_service_high_traffic() {
        // High-traffic services should have higher connection limits (proportional)
        let auth_config = DbConfig::for_service("auth-service");
        assert_eq!(auth_config.service_name, "auth-service");
        assert_eq!(auth_config.max_connections, 12);
        assert_eq!(auth_config.min_connections, 4);

        let user_config = DbConfig::for_service("user-service");
        assert_eq!(user_config.service_name, "user-service");
        assert_eq!(user_config.max_connections, 12);
        assert_eq!(user_config.min_connections, 4);

        let content_config = DbConfig::for_service("content-service");
        assert_eq!(content_config.service_name, "content-service");
        assert_eq!(content_config.max_connections, 12);
        assert_eq!(content_config.min_connections, 4);
    }

    #[test]
    fn test_for_service_medium_traffic() {
        // Medium-traffic services should have moderate connection limits
        let feed_config = DbConfig::for_service("feed-service");
        assert_eq!(feed_config.max_connections, 8);

        let media_config = DbConfig::for_service("media-service");
        assert_eq!(media_config.max_connections, 5);

        let notification_config = DbConfig::for_service("notification-service");
        assert_eq!(notification_config.max_connections, 5);
    }

    #[test]
    fn test_for_service_light_traffic() {
        // Light-traffic services should have lower connection limits
        let video_config = DbConfig::for_service("video-service");
        assert_eq!(video_config.max_connections, 3);

        let cdn_config = DbConfig::for_service("cdn-service");
        assert_eq!(cdn_config.max_connections, 2);
    }

    #[test]
    fn test_for_service_unknown_service() {
        // Unknown services should use conservative defaults
        let unknown_config = DbConfig::for_service("unknown-service");
        assert_eq!(unknown_config.max_connections, 2);
        assert_eq!(unknown_config.min_connections, 1);
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
    #[serial_test::serial]
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
        // PostgreSQL default max_connections = 100
        // Strategy: Reserve 25 for system/overhead, allocate 75 to services
        let services = vec![
            "auth-service",         // 12
            "user-service",         // 12
            "content-service",      // 12
            "feed-service",         // 8
            "search-service",       // 8
            "media-service",        // 5
            "notification-service", // 5
            "events-service",       // 5
            "video-service",        // 3
            "streaming-service",    // 3
            "cdn-service",          // 2
        ];

        let total: u32 = services
            .iter()
            .map(|s| DbConfig::for_service(s).max_connections)
            .sum();

        // CRITICAL: Must stay well under PostgreSQL max_connections (100)
        // Reserve 25 for system + overhead = max 75 for application
        // Current total: 75 connections (reduced from 111, originally 263)
        // This ensures safe operation with adequate headroom for:
        // - System maintenance connections
        // - Replication connections
        // - Backup processes
        // - Temporary spikes
        assert!(
            total <= 75,
            "Total connections ({}) exceeds safe limit. \
             PostgreSQL default max_connections=100, MUST reserve ≥25 for system + overhead.",
            total
        );

        // Verify exact allocation
        assert_eq!(total, 75, "Total connections should be exactly 75");

        // Log for verification
        println!("Total DB connections across 11 services: {}", total);
    }

    #[test]
    fn test_backpressure_config_default() {
        let config = BackpressureConfig::default();
        assert_eq!(config.threshold, 0.85);
    }

    #[test]
    #[serial_test::serial]
    fn test_backpressure_config_from_env() {
        // Test default
        std::env::remove_var("DB_POOL_BACKPRESSURE_THRESHOLD");
        let config = BackpressureConfig::from_env();
        assert_eq!(config.threshold, 0.85);

        // Test custom threshold
        std::env::set_var("DB_POOL_BACKPRESSURE_THRESHOLD", "0.90");
        let config = BackpressureConfig::from_env();
        assert_eq!(config.threshold, 0.90);

        // Test invalid threshold (should use default)
        std::env::set_var("DB_POOL_BACKPRESSURE_THRESHOLD", "1.5");
        let config = BackpressureConfig::from_env();
        assert_eq!(config.threshold, 0.85);

        // Test invalid threshold (should use default)
        std::env::set_var("DB_POOL_BACKPRESSURE_THRESHOLD", "invalid");
        let config = BackpressureConfig::from_env();
        assert_eq!(config.threshold, 0.85);

        // Clean up
        std::env::remove_var("DB_POOL_BACKPRESSURE_THRESHOLD");
    }

    #[test]
    fn test_pool_exhausted_error_display() {
        let error = PoolExhaustedError {
            service: "test-service".to_string(),
            utilization: 0.92,
            threshold: 0.85,
        };

        let msg = error.to_string();
        assert!(msg.contains("test-service"));
        assert!(msg.contains("92.00%"));
        assert!(msg.contains("85.00%"));
    }
}
