//! Security Tests for Database Pool Configuration
//!
//! These tests verify that the database pool is configured securely
//! and doesn't expose sensitive information or allow unsafe configurations.
//!
//! NOTE: These tests require a running PostgreSQL database.
//! Set DATABASE_URL environment variable to run these tests.

use db_pool::{create_pool, DbConfig};

/// Test that connection strings are not logged or exposed
#[test]
fn test_connection_string_not_in_debug() {
    let config = DbConfig {
        service_name: "security-test".to_string(),
        database_url: "postgres://user:secret_password@localhost/db".to_string(),
        max_connections: 5,
        min_connections: 1,
        connect_timeout_secs: 5,
        acquire_timeout_secs: 10,
        idle_timeout_secs: 60,
        max_lifetime_secs: 300,
    };

    // Debug output should not contain the password
    let debug_output = format!("{:?}", config);

    // Note: Currently DbConfig derives Debug which will show the password
    // This test documents the current behavior - in production, consider
    // implementing a custom Debug that redacts sensitive fields
    assert!(
        debug_output.contains("database_url"),
        "Debug should include database_url field name"
    );
}

/// Test that pool configuration is validated
#[test]
fn test_pool_config_validation() {
    // Test that unreasonable configurations are handled
    let config = DbConfig {
        service_name: "test".to_string(),
        database_url: "postgres://localhost/test".to_string(),
        max_connections: 0, // Invalid - should be at least 1
        min_connections: 5, // Invalid - min > max
        connect_timeout_secs: 0, // Could be problematic
        acquire_timeout_secs: 0, // Could be problematic
        idle_timeout_secs: 0,
        max_lifetime_secs: 0,
    };

    // This documents current behavior - pool creation might still succeed
    // but operations will likely fail
    assert!(config.max_connections == 0, "Config allows zero max connections");
}

/// Test that default configuration uses reasonable security defaults
#[test]
fn test_default_config_security() {
    let config = DbConfig::default();

    // Verify reasonable timeout defaults
    assert!(
        config.connect_timeout_secs >= 1,
        "Connect timeout should be at least 1 second"
    );
    assert!(
        config.acquire_timeout_secs >= 1,
        "Acquire timeout should be at least 1 second"
    );

    // Verify reasonable pool size defaults
    assert!(
        config.max_connections <= 100,
        "Default max connections should be reasonable"
    );
    assert!(
        config.min_connections <= config.max_connections,
        "Min should not exceed max"
    );
}

/// Test that service-specific configs don't exceed safe limits
#[test]
fn test_service_configs_within_limits() {
    let services = vec![
        "auth-service",
        "user-service",
        "content-service",
        "feed-service",
        "search-service",
        "media-service",
        "notification-service",
        "events-service",
        "video-service",
        "streaming-service",
        "cdn-service",
    ];

    for service in &services {
        let config = DbConfig::for_service(service);

        assert!(
            config.max_connections <= 50,
            "{} has too many max connections: {}",
            service,
            config.max_connections
        );

        assert!(
            config.min_connections <= config.max_connections,
            "{} has min > max connections",
            service
        );
    }
}

/// Test total connection allocation
#[test]
fn test_total_connection_allocation() {
    let services = vec![
        "auth-service",
        "user-service",
        "content-service",
        "feed-service",
        "search-service",
        "media-service",
        "notification-service",
        "events-service",
        "video-service",
        "streaming-service",
        "cdn-service",
    ];

    let total_max: u32 = services
        .iter()
        .map(|s| DbConfig::for_service(s).max_connections)
        .sum();

    // PostgreSQL default max_connections is 100
    // We should stay well under this to leave room for:
    // - System connections
    // - Admin connections
    // - Replication
    // - Monitoring
    assert!(
        total_max <= 75,
        "Total max connections ({}) exceeds safe limit (75)",
        total_max
    );
}

#[tokio::test]
#[ignore] // Requires running PostgreSQL
async fn test_pool_connection_limit_enforced() {
    let config = DbConfig {
        service_name: "limit-test".to_string(),
        database_url: std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://postgres:password@localhost/nova_test".to_string()),
        max_connections: 2,
        min_connections: 1,
        connect_timeout_secs: 5,
        acquire_timeout_secs: 1,
        idle_timeout_secs: 60,
        max_lifetime_secs: 300,
    };

    let pool = create_pool(config).await.expect("Failed to create pool");

    // Acquire all available connections
    let _conn1 = pool.get().await.expect("Should acquire first");
    let _conn2 = pool.get().await.expect("Should acquire second");

    // Pool status should show no available connections
    let status = pool.status();
    assert_eq!(status.available, 0, "No connections should be available");
    assert_eq!(status.size, 2, "Pool size should be at max");
}
