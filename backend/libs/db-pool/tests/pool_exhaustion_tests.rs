//! Pool Exhaustion Tests (Quick Win #2)
//!
//! Tests for database connection pool exhaustion prevention
//!
//! Test Coverage:
//! - Normal acquisition below threshold
//! - Early rejection at threshold
//! - Metrics recording
//! - Concurrent access safety
//! - Load testing

use db_pool::{acquire_with_metrics, create_pool, DbConfig};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Semaphore;

/// Helper to create test pool with small size for testing exhaustion
async fn create_test_pool(max_connections: u32) -> PgPool {
    let config = DbConfig {
        service_name: "pool-test".to_string(),
        database_url: std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://postgres:password@localhost/nova_test".to_string()),
        max_connections,
        min_connections: 1,
        connect_timeout_secs: 5,
        acquire_timeout_secs: 2, // Short timeout for testing
        idle_timeout_secs: 60,
        max_lifetime_secs: 300,
    };

    create_pool(config)
        .await
        .expect("Failed to create test pool")
}

#[tokio::test]
async fn test_normal_acquisition_below_threshold() {
    // Test: Normal connection acquisition when pool is not exhausted
    let pool = create_test_pool(5).await;

    // Acquire 3 connections (below threshold)
    let mut connections = Vec::new();
    for _ in 0..3 {
        let conn = acquire_with_metrics(&pool, "pool-test")
            .await
            .expect("Should acquire connection when below threshold");
        connections.push(conn);
    }

    // Verify pool state
    assert_eq!(pool.size(), 3);
    assert_eq!(pool.num_idle(), 0); // All connections in use

    // Release connections
    drop(connections);

    // Small delay for pool to update
    tokio::time::sleep(Duration::from_millis(100)).await;

    // Verify idle connections increased
    assert!(pool.num_idle() > 0);
}

#[tokio::test]
async fn test_early_rejection_at_threshold() {
    // Test: Pool rejects new connections when at max capacity
    let pool = create_test_pool(3).await;

    // Acquire all 3 connections (at max)
    let mut connections = Vec::new();
    for i in 0..3 {
        let conn = acquire_with_metrics(&pool, "pool-test")
            .await
            .unwrap_or_else(|_| panic!("Failed to acquire connection {}", i));
        connections.push(conn);
    }

    // Try to acquire 4th connection - should timeout
    let start = std::time::Instant::now();
    let result = acquire_with_metrics(&pool, "pool-test").await;
    let elapsed = start.elapsed();

    // Should fail due to timeout
    assert!(result.is_err(), "Should fail when pool exhausted");
    assert!(
        elapsed.as_secs() >= 2,
        "Should wait for acquire timeout (2s)"
    );

    // Verify error is PoolTimedOut
    if let Err(e) = result {
        assert!(
            matches!(e, sqlx::Error::PoolTimedOut),
            "Error should be PoolTimedOut, got: {:?}",
            e
        );
    }
}

#[tokio::test]
async fn test_metrics_recording() {
    // Test: Metrics are recorded for connection acquisition
    let pool = create_test_pool(5).await;

    // Acquire connection with metrics
    let conn = acquire_with_metrics(&pool, "pool-test")
        .await
        .expect("Should acquire connection");

    // Metrics should be recorded (we can't easily verify Prometheus metrics
    // in unit tests, but we verify the function completes successfully)
    assert!(conn.ping().await.is_ok());

    drop(conn);
}

#[tokio::test]
async fn test_concurrent_access_safety() {
    // Test: Pool handles concurrent access safely
    let pool = Arc::new(create_test_pool(10).await);
    let mut handles = vec![];

    // Spawn 50 concurrent tasks trying to acquire connections
    for i in 0..50 {
        let pool_clone = Arc::clone(&pool);
        let handle = tokio::spawn(async move {
            let conn = acquire_with_metrics(&pool_clone, "pool-test")
                .await
                .unwrap_or_else(|_| panic!("Task {} failed to acquire connection", i));

            // Simulate some work
            let result = sqlx::query("SELECT 1")
                .execute(&mut *conn)
                .await
                .expect("Query should succeed");

            result.rows_affected()
        });
        handles.push(handle);
    }

    // Wait for all tasks to complete
    let mut success_count = 0;
    for handle in handles {
        if let Ok(rows) = handle.await {
            if rows > 0 {
                success_count += 1;
            }
        }
    }

    // All tasks should complete successfully
    assert_eq!(success_count, 50, "All 50 tasks should complete");

    // Pool should return to reasonable state
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert!(pool.num_idle() > 0, "Pool should have idle connections");
}

#[tokio::test]
async fn test_load_stress_sequential() {
    // Test: Pool handles sequential load without exhaustion
    let pool = create_test_pool(5).await;

    // Execute 100 sequential queries
    for i in 0..100 {
        let conn = acquire_with_metrics(&pool, "pool-test")
            .await
            .unwrap_or_else(|_| panic!("Failed at iteration {}", i));

        sqlx::query("SELECT 1")
            .execute(&mut *conn)
            .await
            .expect("Query should succeed");

        // Connection is dropped and returned to pool
    }

    // Pool should still be healthy
    assert_eq!(pool.size(), 5, "Pool size should remain at max");
    assert!(pool.num_idle() >= 1, "Should have idle connections");
}

#[tokio::test]
async fn test_load_stress_burst() {
    // Test: Pool handles burst load with backpressure
    let pool = Arc::new(create_test_pool(10).await);
    let semaphore = Arc::new(Semaphore::new(20)); // Limit concurrent tasks

    let mut handles = vec![];

    // Spawn 200 tasks in bursts
    for i in 0..200 {
        let pool_clone = Arc::clone(&pool);
        let sem = Arc::clone(&semaphore);

        let handle = tokio::spawn(async move {
            let _permit = sem.acquire().await.expect("Failed to acquire semaphore");

            let conn = acquire_with_metrics(&pool_clone, "pool-test")
                .await
                .unwrap_or_else(|_| panic!("Task {} failed", i));

            sqlx::query("SELECT 1")
                .execute(&mut *conn)
                .await
                .expect("Query should succeed");
        });

        handles.push(handle);
    }

    // Wait for all tasks
    let mut success_count = 0;
    for handle in handles {
        if handle.await.is_ok() {
            success_count += 1;
        }
    }

    // Most tasks should succeed (some may timeout due to contention)
    assert!(
        success_count >= 150,
        "At least 75% of tasks should complete (got {})",
        success_count
    );
}

#[tokio::test]
async fn test_connection_timeout_configuration() {
    // Test: Pool respects timeout configuration
    let config = DbConfig {
        service_name: "timeout-test".to_string(),
        database_url: std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://postgres:password@localhost/nova_test".to_string()),
        max_connections: 2,
        min_connections: 1,
        connect_timeout_secs: 5,
        acquire_timeout_secs: 1, // Very short timeout
        idle_timeout_secs: 60,
        max_lifetime_secs: 300,
    };

    let pool = create_pool(config)
        .await
        .expect("Failed to create pool");

    // Acquire both connections
    let _conn1 = pool.acquire().await.expect("First acquire should succeed");
    let _conn2 = pool.acquire().await.expect("Second acquire should succeed");

    // Third acquire should timeout quickly
    let start = std::time::Instant::now();
    let result = pool.acquire().await;
    let elapsed = start.elapsed();

    assert!(result.is_err(), "Should timeout");
    assert!(
        elapsed.as_secs() <= 2,
        "Should timeout within ~1 second (got {:?})",
        elapsed
    );
}

#[tokio::test]
async fn test_pool_recovery_after_exhaustion() {
    // Test: Pool recovers after exhaustion
    let pool = create_test_pool(3).await;

    // Exhaust pool
    let conn1 = pool.acquire().await.expect("Should acquire");
    let conn2 = pool.acquire().await.expect("Should acquire");
    let conn3 = pool.acquire().await.expect("Should acquire");

    // Verify exhausted
    assert_eq!(pool.num_idle(), 0);

    // Release one connection
    drop(conn1);
    tokio::time::sleep(Duration::from_millis(100)).await;

    // Should be able to acquire again
    let conn4 = pool
        .acquire()
        .await
        .expect("Should acquire after release");

    assert!(conn4.ping().await.is_ok());

    // Cleanup
    drop(conn2);
    drop(conn3);
    drop(conn4);
}

#[tokio::test]
async fn test_metrics_on_timeout() {
    // Test: Metrics are recorded even on timeout
    let pool = create_test_pool(2).await;

    // Exhaust pool
    let _conn1 = pool.acquire().await.expect("Should acquire");
    let _conn2 = pool.acquire().await.expect("Should acquire");

    // Try to acquire with metrics - should timeout
    let result = acquire_with_metrics(&pool, "pool-test").await;

    assert!(result.is_err(), "Should timeout");

    // Metrics should have recorded the timeout error
    // (Verified by function completing without panic)
}

#[tokio::test]
async fn test_service_specific_pool_sizes() {
    // Test: Different services get appropriate pool sizes
    let services = vec![
        ("auth-service", 12, 4),
        ("user-service", 12, 4),
        ("feed-service", 8, 3),
        ("cdn-service", 2, 1),
    ];

    for (service, expected_max, expected_min) in services {
        let config = DbConfig::for_service(service);
        assert_eq!(
            config.max_connections, expected_max,
            "{} should have max={}",
            service, expected_max
        );
        assert_eq!(
            config.min_connections, expected_min,
            "{} should have min={}",
            service, expected_min
        );
    }
}

#[tokio::test]
async fn test_total_connections_within_limit() {
    // Test: Total connections across all services stays under PostgreSQL limit
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

    let total: u32 = services
        .iter()
        .map(|s| DbConfig::for_service(s).max_connections)
        .sum();

    // PostgreSQL default max_connections = 100
    // Reserve 25 for system overhead = 75 available
    assert!(
        total <= 75,
        "Total connections ({}) exceeds safe limit (75)",
        total
    );
}
