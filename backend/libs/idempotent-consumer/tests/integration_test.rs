//! Integration tests for idempotent consumer library
//!
//! These tests verify:
//! 1. Basic idempotency check and marking
//! 2. Concurrent processing safety (10 parallel consumers)
//! 3. Process-if-new atomic operation
//! 4. Cleanup of old events
//! 5. Error handling for invalid event IDs
//!
//! Prerequisites:
//! - PostgreSQL running locally or via Docker
//! - Environment variable: DATABASE_URL
//! - Migration applied: 001_create_processed_events_table.sql
//!
//! Run tests:
//! ```bash
//! export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/nova_test"
//! cargo test --package idempotent-consumer --test integration_test -- --nocapture
//! ```
//!
//! Start test database:
//! ```bash
//! docker run --name postgres-test -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:15
//! sqlx database create --database-url $DATABASE_URL
//! sqlx migrate run --source backend/libs/idempotent-consumer/migrations
//! ```

use idempotent_consumer::{IdempotencyGuard, ProcessingResult};
use sqlx::{PgPool, Row};
use std::env;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::time::sleep;

/// Helper function to get database URL from environment
fn get_database_url() -> String {
    env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgresql://postgres:postgres@localhost:5432/nova_test".to_string())
}

/// Helper function to create a test database pool
async fn create_test_pool() -> PgPool {
    let database_url = get_database_url();
    PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to test database")
}

/// Helper function to clean up test data
async fn cleanup_test_events(pool: &PgPool) {
    sqlx::query("DELETE FROM processed_events WHERE event_id LIKE 'test-%'")
        .execute(pool)
        .await
        .expect("Failed to cleanup test events");
}

/// Test: Basic idempotency check - event not processed
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_is_processed_returns_false_for_new_event() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = IdempotencyGuard::new(pool.clone(), Duration::from_secs(86400));
    let event_id = "test-new-event-1";

    let is_processed = guard
        .is_processed(event_id)
        .await
        .expect("Failed to check if processed");

    assert!(!is_processed, "New event should not be processed");

    cleanup_test_events(&pool).await;
}

/// Test: Mark event as processed and verify
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_mark_processed_and_verify() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = IdempotencyGuard::new(pool.clone(), Duration::from_secs(86400));
    let event_id = "test-mark-event-1";

    // Mark as processed
    let was_inserted = guard
        .mark_processed(event_id, None)
        .await
        .expect("Failed to mark as processed");

    assert!(was_inserted, "First insert should return true");

    // Verify it's now marked as processed
    let is_processed = guard
        .is_processed(event_id)
        .await
        .expect("Failed to check if processed");

    assert!(is_processed, "Event should be marked as processed");

    cleanup_test_events(&pool).await;
}

/// Test: Duplicate mark returns false (ON CONFLICT DO NOTHING)
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_duplicate_mark_returns_false() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = IdempotencyGuard::new(pool.clone(), Duration::from_secs(86400));
    let event_id = "test-duplicate-event-1";

    // First mark
    let first_result = guard
        .mark_processed(event_id, None)
        .await
        .expect("Failed to mark as processed");

    assert!(first_result, "First insert should return true");

    // Second mark (duplicate)
    let second_result = guard
        .mark_processed(event_id, None)
        .await
        .expect("Failed to mark as processed");

    assert!(
        !second_result,
        "Duplicate insert should return false (ON CONFLICT DO NOTHING)"
    );

    cleanup_test_events(&pool).await;
}

/// Test: Mark with metadata
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_mark_processed_with_metadata() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = IdempotencyGuard::new(pool.clone(), Duration::from_secs(86400));
    let event_id = "test-metadata-event-1";

    let metadata = serde_json::json!({
        "consumer_group": "test-consumer",
        "partition": 0,
        "offset": 12345,
        "correlation_id": "abc-123",
    });

    guard
        .mark_processed(event_id, Some(metadata.clone()))
        .await
        .expect("Failed to mark as processed");

    // Verify metadata was stored
    let row = sqlx::query("SELECT metadata FROM processed_events WHERE event_id = $1")
        .bind(event_id)
        .fetch_one(&pool)
        .await
        .expect("Failed to fetch event");

    let stored_metadata: Option<serde_json::Value> = row
        .try_get("metadata")
        .expect("Failed to get metadata column");

    assert_eq!(stored_metadata, Some(metadata));

    cleanup_test_events(&pool).await;
}

/// Test: Process if new - first time processing
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_process_if_new_success() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = IdempotencyGuard::new(pool.clone(), Duration::from_secs(86400));
    let event_id = "test-process-new-1";

    let counter = Arc::new(AtomicU32::new(0));
    let counter_clone = counter.clone();

    let result = guard
        .process_if_new(event_id, || async move {
            counter_clone.fetch_add(1, Ordering::SeqCst);
            Ok(())
        })
        .await
        .expect("Failed to process event");

    assert_eq!(result, ProcessingResult::Success);
    assert_eq!(
        counter.load(Ordering::SeqCst),
        1,
        "Function should be called once"
    );

    // Verify event was marked as processed
    let is_processed = guard
        .is_processed(event_id)
        .await
        .expect("Failed to check if processed");
    assert!(is_processed);

    cleanup_test_events(&pool).await;
}

/// Test: Process if new - already processed
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_process_if_new_already_processed() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = IdempotencyGuard::new(pool.clone(), Duration::from_secs(86400));
    let event_id = "test-process-existing-1";

    // Pre-mark as processed
    guard
        .mark_processed(event_id, None)
        .await
        .expect("Failed to pre-mark");

    let counter = Arc::new(AtomicU32::new(0));
    let counter_clone = counter.clone();

    let result = guard
        .process_if_new(event_id, || async move {
            counter_clone.fetch_add(1, Ordering::SeqCst);
            Ok(())
        })
        .await
        .expect("Failed to process event");

    assert_eq!(result, ProcessingResult::AlreadyProcessed);
    assert_eq!(
        counter.load(Ordering::SeqCst),
        0,
        "Function should NOT be called"
    );

    cleanup_test_events(&pool).await;
}

/// Test: Process if new - processing fails
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_process_if_new_processing_fails() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = IdempotencyGuard::new(pool.clone(), Duration::from_secs(86400));
    let event_id = "test-process-fail-1";

    let result = guard
        .process_if_new(event_id, || async {
            Err(anyhow::anyhow!("Business logic failed"))
        })
        .await
        .expect("Should not return database error");

    match result {
        ProcessingResult::Failed(msg) => {
            assert!(msg.contains("Business logic failed"));
        }
        _ => panic!("Expected Failed result, got {:?}", result),
    }

    // Event should NOT be marked as processed after failure
    let is_processed = guard
        .is_processed(event_id)
        .await
        .expect("Failed to check if processed");
    assert!(
        !is_processed,
        "Failed event should not be marked as processed"
    );

    cleanup_test_events(&pool).await;
}

/// Test: Concurrent processing - 10 parallel consumers, same event_id
///
/// This test simulates 10 Kafka consumers processing the same event simultaneously.
/// Only 1 should succeed, others should get AlreadyProcessed.
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_concurrent_processing_same_event() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = Arc::new(IdempotencyGuard::new(
        pool.clone(),
        Duration::from_secs(86400),
    ));
    let event_id = "test-concurrent-event-1";

    // Counter to track how many times processing function was called
    let execution_counter = Arc::new(AtomicU32::new(0));

    // Spawn 10 parallel tasks
    let mut handles = vec![];
    for i in 0..10 {
        let guard_clone = guard.clone();
        let event_id_clone = event_id.to_string();
        let counter_clone = execution_counter.clone();

        let handle = tokio::spawn(async move {
            sleep(Duration::from_millis(i * 10)).await; // Stagger slightly

            guard_clone
                .process_if_new(&event_id_clone, || async move {
                    counter_clone.fetch_add(1, Ordering::SeqCst);
                    sleep(Duration::from_millis(100)).await; // Simulate work
                    Ok(())
                })
                .await
        });

        handles.push(handle);
    }

    // Wait for all tasks
    let results: Vec<_> = futures_util::future::join_all(handles)
        .await
        .into_iter()
        .map(|r| r.expect("Task panicked").expect("Database error"))
        .collect();

    // Count results
    let success_count = results
        .iter()
        .filter(|r| **r == ProcessingResult::Success)
        .count();
    let already_processed_count = results
        .iter()
        .filter(|r| **r == ProcessingResult::AlreadyProcessed)
        .count();

    println!(
        "Success: {}, AlreadyProcessed: {}",
        success_count, already_processed_count
    );

    // Assertions
    assert_eq!(
        success_count, 1,
        "Exactly 1 task should succeed (exactly-once semantics)"
    );
    assert_eq!(
        already_processed_count, 9,
        "9 tasks should get AlreadyProcessed"
    );
    assert_eq!(
        execution_counter.load(Ordering::SeqCst),
        1,
        "Processing function should be called exactly once"
    );

    cleanup_test_events(&pool).await;
}

/// Test: Concurrent marking - 10 parallel mark_processed calls
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_concurrent_marking_same_event() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = Arc::new(IdempotencyGuard::new(
        pool.clone(),
        Duration::from_secs(86400),
    ));
    let event_id = "test-concurrent-mark-1";

    // Spawn 10 parallel tasks
    let mut handles = vec![];
    for _ in 0..10 {
        let guard_clone = guard.clone();
        let event_id_clone = event_id.to_string();

        let handle =
            tokio::spawn(async move { guard_clone.mark_processed(&event_id_clone, None).await });

        handles.push(handle);
    }

    // Wait for all tasks
    let results: Vec<_> = futures_util::future::join_all(handles)
        .await
        .into_iter()
        .map(|r| r.expect("Task panicked").expect("Database error"))
        .collect();

    // Count successes
    let success_count = results.iter().filter(|&&was_inserted| was_inserted).count();

    println!("Successful inserts: {}", success_count);

    assert_eq!(
        success_count, 1,
        "Exactly 1 insert should succeed (UNIQUE constraint)"
    );

    cleanup_test_events(&pool).await;
}

/// Test: Cleanup old events
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_cleanup_old_events() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    // Create guard with 2-second retention for testing
    let guard = IdempotencyGuard::new(pool.clone(), Duration::from_secs(2));

    // Insert test events
    let old_event = "test-old-event-1";
    let new_event = "test-new-event-1";

    guard
        .mark_processed(old_event, None)
        .await
        .expect("Failed to mark old event");

    // Manually update old event to be older than retention
    sqlx::query(
        "UPDATE processed_events SET processed_at = NOW() - INTERVAL '3 seconds' WHERE event_id = $1"
    )
    .bind(old_event)
    .execute(&pool)
    .await
    .expect("Failed to update old event timestamp");

    sleep(Duration::from_millis(100)).await;

    guard
        .mark_processed(new_event, None)
        .await
        .expect("Failed to mark new event");

    // Run cleanup
    let deleted_count = guard
        .cleanup_old_events()
        .await
        .expect("Failed to cleanup old events");

    assert_eq!(deleted_count, 1, "Should delete 1 old event");

    // Verify old event was deleted
    let old_exists = guard
        .is_processed(old_event)
        .await
        .expect("Failed to check old event");
    assert!(!old_exists, "Old event should be deleted");

    // Verify new event was NOT deleted
    let new_exists = guard
        .is_processed(new_event)
        .await
        .expect("Failed to check new event");
    assert!(new_exists, "New event should still exist");

    cleanup_test_events(&pool).await;
}

/// Test: Invalid event ID - empty string
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_invalid_event_id_empty() {
    let pool = create_test_pool().await;
    let guard = IdempotencyGuard::new(pool, Duration::from_secs(86400));

    let result = guard.is_processed("").await;
    assert!(result.is_err(), "Empty event_id should return error");
}

/// Test: Invalid event ID - too long (>255 characters)
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_invalid_event_id_too_long() {
    let pool = create_test_pool().await;
    let guard = IdempotencyGuard::new(pool, Duration::from_secs(86400));

    let long_id = "x".repeat(256);
    let result = guard.is_processed(&long_id).await;
    assert!(
        result.is_err(),
        "Event_id >255 characters should return error"
    );
}

/// Test: Multiple different event IDs
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn test_multiple_different_events() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = IdempotencyGuard::new(pool.clone(), Duration::from_secs(86400));

    // Process 100 different events
    for i in 0..100 {
        let event_id = format!("test-multi-event-{}", i);
        guard
            .mark_processed(&event_id, None)
            .await
            .expect("Failed to mark event");
    }

    // Verify all were marked
    for i in 0..100 {
        let event_id = format!("test-multi-event-{}", i);
        let is_processed = guard
            .is_processed(&event_id)
            .await
            .expect("Failed to check event");
        assert!(is_processed, "Event {} should be processed", i);
    }

    cleanup_test_events(&pool).await;
}

/// Test: Processing result helpers
#[test]
fn test_processing_result_helpers() {
    assert!(ProcessingResult::Success.is_ok());
    assert!(ProcessingResult::AlreadyProcessed.is_ok());
    assert!(!ProcessingResult::Failed("error".to_string()).is_ok());

    assert!(!ProcessingResult::Success.is_failed());
    assert!(!ProcessingResult::AlreadyProcessed.is_failed());
    assert!(ProcessingResult::Failed("error".to_string()).is_failed());
}

/// Benchmark: Mark 1000 events sequentially (for performance reference)
///
/// This is not a rigorous benchmark, just a sanity check.
/// Expected: <1ms per event on local PostgreSQL
#[ignore = "Requires PostgreSQL database"]
#[tokio::test]
async fn benchmark_mark_1000_events() {
    let pool = create_test_pool().await;
    cleanup_test_events(&pool).await;

    let guard = IdempotencyGuard::new(pool.clone(), Duration::from_secs(86400));

    let start = std::time::Instant::now();

    for i in 0..1000 {
        let event_id = format!("test-bench-event-{}", i);
        guard
            .mark_processed(&event_id, None)
            .await
            .expect("Failed to mark event");
    }

    let elapsed = start.elapsed();
    let avg_time = elapsed / 1000;

    println!(
        "Marked 1000 events in {:?} (avg: {:?}/event)",
        elapsed, avg_time
    );
    println!("Throughput: {} events/sec", 1000.0 / elapsed.as_secs_f64());

    cleanup_test_events(&pool).await;
}
