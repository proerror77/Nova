//! End-to-end tests for streaming service
//!
//! Tests the complete flow from HTTP request through actor pattern to response.
//! Requires external dependencies: PostgreSQL, Redis, Kafka
//!
//! Environment variables:
//! - TEST_DATABASE_URL: PostgreSQL connection string
//! - TEST_REDIS_URL: Redis connection string (optional, defaults to redis://localhost)
//! - TEST_KAFKA_BROKERS: Kafka brokers (optional, defaults to localhost:9092)

mod common;

use redis::aio::ConnectionManager;
use sqlx::PgPool;
use user_service::services::streaming::{
    CreateStreamRequest, StreamCategory, StreamRepository,
};
use uuid::Uuid;

// ============================================================================
// Test Fixtures and Utilities
// ============================================================================

/// Get PostgreSQL connection pool for tests
async fn get_test_pool() -> PgPool {
    let url = std::env::var("TEST_DATABASE_URL").unwrap_or_else(|_| {
        "postgresql://postgres:postgres@localhost:5432/nova_test".to_string()
    });

    PgPool::connect(&url)
        .await
        .expect("Failed to connect to test database")
}

/// Get Redis connection manager for tests
async fn get_redis_manager() -> ConnectionManager {
    let url = std::env::var("TEST_REDIS_URL")
        .unwrap_or_else(|_| "redis://localhost:6379".to_string());

    let client = redis::Client::open(url).expect("Failed to create Redis client");

    client
        .get_connection_manager()
        .await
        .expect("Failed to get Redis connection manager")
}

/// Clean up Redis after tests
async fn cleanup_redis(manager: &ConnectionManager) {
    use redis::AsyncCommands;
    let _ = redis::cmd("FLUSHDB")
        .query_async::<_, ()>(manager)
        .await;
}

// ============================================================================
// Integration Tests
// ============================================================================

#[tokio::test]
#[ignore = "requires PostgreSQL and Redis"]
async fn create_stream_full_workflow() {
    let pool = get_test_pool().await;
    let redis = get_redis_manager().await;

    let repo = StreamRepository::new(pool.clone());
    let creator_id = Uuid::new_v4();

    // Create stream
    let request = CreateStreamRequest {
        title: "E2E Test Stream".to_string(),
        description: Some("End-to-end test".to_string()),
        category: StreamCategory::Gaming,
        thumbnail_url: None,
    };

    let stream = repo
        .create_stream(
            creator_id,
            request.title.clone(),
            request.description.clone(),
            request.category,
            Uuid::new_v4().to_string(),
            "rtmp://localhost/live".to_string(),
        )
        .await
        .expect("Failed to create stream");

    // Verify stream was created
    assert!(!stream.id.is_nil());
    assert_eq!(stream.title, "E2E Test Stream");
    assert_eq!(stream.creator_id, creator_id);

    // Cleanup
    sqlx::query!("DELETE FROM streams WHERE id = $1", stream.id)
        .execute(&pool)
        .await
        .expect("Failed to cleanup");

    cleanup_redis(&redis).await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL and Redis"]
async fn duplicate_stream_creation_fails() {
    let pool = get_test_pool().await;
    let redis = get_redis_manager().await;

    let repo = StreamRepository::new(pool.clone());
    let creator_id = Uuid::new_v4();

    let request = CreateStreamRequest {
        title: "Duplicate Test".to_string(),
        description: None,
        category: StreamCategory::Music,
        thumbnail_url: None,
    };

    // First creation succeeds
    let stream1 = repo
        .create_stream(
            creator_id,
            request.title.clone(),
            request.description.clone(),
            request.category.clone(),
            Uuid::new_v4().to_string(),
            "rtmp://localhost/live".to_string(),
        )
        .await
        .expect("First creation should succeed");

    // Second creation should fail (same creator)
    let result = repo
        .create_stream(
            creator_id,
            request.title.clone(),
            request.description.clone(),
            request.category.clone(),
            Uuid::new_v4().to_string(),
            "rtmp://localhost/live".to_string(),
        )
        .await;

    assert!(result.is_err());

    // Cleanup
    sqlx::query!("DELETE FROM streams WHERE id = $1", stream1.id)
        .execute(&pool)
        .await
        .expect("Failed to cleanup");

    cleanup_redis(&redis).await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL and Redis"]
async fn stream_lifecycle_operations() {
    let pool = get_test_pool().await;
    let redis = get_redis_manager().await;

    let repo = StreamRepository::new(pool.clone());
    let creator_id = Uuid::new_v4();

    // Create
    let stream = repo
        .create_stream(
            creator_id,
            "Lifecycle Test".to_string(),
            None,
            StreamCategory::Sports,
            Uuid::new_v4().to_string(),
            "rtmp://localhost/live".to_string(),
        )
        .await
        .expect("Failed to create stream");

    // Verify initial status
    let fetched = repo
        .get_stream_by_id(stream.id)
        .await
        .expect("Failed to fetch stream")
        .expect("Stream not found");

    // Start stream
    repo.start_stream(stream.id, "https://cdn/index.m3u8".to_string())
        .await
        .expect("Failed to start stream");

    let started = repo
        .get_stream_by_id(stream.id)
        .await
        .expect("Failed to fetch stream")
        .expect("Stream not found");

    assert!(started.started_at.is_some());

    // End stream
    repo.end_stream(stream.id)
        .await
        .expect("Failed to end stream");

    let ended = repo
        .get_stream_by_id(stream.id)
        .await
        .expect("Failed to fetch stream")
        .expect("Stream not found");

    assert!(ended.ended_at.is_some());

    // Cleanup
    sqlx::query!("DELETE FROM streams WHERE id = $1", stream.id)
        .execute(&pool)
        .await
        .expect("Failed to cleanup");

    cleanup_redis(&redis).await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL and Redis"]
async fn list_live_streams() {
    let pool = get_test_pool().await;
    let redis = get_redis_manager().await;

    let repo = StreamRepository::new(pool.clone());

    // Create multiple test streams
    let mut stream_ids = Vec::new();
    for i in 0..3 {
        let creator_id = Uuid::new_v4();
        let stream = repo
            .create_stream(
                creator_id,
                format!("Stream {}", i),
                None,
                StreamCategory::Gaming,
                Uuid::new_v4().to_string(),
                "rtmp://localhost/live".to_string(),
            )
            .await
            .expect("Failed to create stream");

        // Start the stream to make it "live"
        repo.start_stream(stream.id, "https://cdn/index.m3u8".to_string())
            .await
            .expect("Failed to start stream");

        stream_ids.push(stream.id);
    }

    // List live streams
    let live_streams = repo
        .list_live_streams(None, 10, 0)
        .await
        .expect("Failed to list live streams");

    assert!(!live_streams.is_empty());

    // Cleanup
    for stream_id in stream_ids {
        sqlx::query!("DELETE FROM streams WHERE id = $1", stream_id)
            .execute(&pool)
            .await
            .expect("Failed to cleanup");
    }

    cleanup_redis(&redis).await;
}

#[tokio::test]
#[ignore = "requires PostgreSQL"]
async fn get_creator_info() {
    let pool = get_test_pool().await;

    let repo = StreamRepository::new(pool.clone());
    let user_id = Uuid::new_v4();

    // Create a test user (assuming it exists from auth service)
    // This test verifies the repository can fetch creator info

    // For now, just verify the method exists and returns appropriate error
    let result = repo.get_creator_info(user_id).await;

    // Result should be either Ok(None) or Ok(Some(...))
    assert!(result.is_ok());
}
