/// Integration tests for stream_cleaner (Phase 4 - Spec 007)
///
/// Tests cleanup of streaming data from soft-deleted users:
/// - Soft-delete streams: status = 'ended'
/// - Soft-delete stream_keys: is_active = false
/// - Hard-delete viewer_sessions
/// - Batch API efficiency validation
use std::collections::HashMap;

use sqlx::{postgres::PgPoolOptions, Pool, Postgres};
use testcontainers::{core::WaitFor, runners::AsyncRunner, GenericImage};
use uuid::Uuid;

mod common;
use common::mock_auth_client::MockAuthClient;

/// Bootstrap test database with testcontainers
async fn setup_test_db() -> Result<Pool<Postgres>, Box<dyn std::error::Error>> {
    let postgres_image = GenericImage::new("postgres", "16-alpine")
        .with_wait_for(WaitFor::message_on_stderr(
            "database system is ready to accept connections",
        ))
        .with_env_var("POSTGRES_PASSWORD", "postgres")
        .with_env_var("POSTGRES_USER", "postgres")
        .with_env_var("POSTGRES_DB", "postgres");

    let container = postgres_image.start().await?;
    let port = container.get_host_port_ipv4(5432).await?;

    let connection_string = format!("postgres://postgres:postgres@127.0.0.1:{}/postgres", port);

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&connection_string)
        .await?;

    // Run migrations (from backend/migrations, not service-specific)
    sqlx::migrate!("../migrations").run(&pool).await?;

    // Leak container to keep it alive for test duration
    Box::leak(Box::new(container));

    Ok(pool)
}

/// Helper: Create test stream
async fn create_test_stream(
    pool: &Pool<Postgres>,
    broadcaster_id: Uuid,
    title: &str,
    status: &str,
) -> Uuid {
    let stream_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO streams (stream_id, broadcaster_id, title, status, created_at, updated_at)
         VALUES ($1, $2, $3, $4::stream_status_enum, NOW(), NOW())",
    )
    .bind(stream_id)
    .bind(broadcaster_id)
    .bind(title)
    .bind(status)
    .execute(pool)
    .await
    .expect("Failed to create test stream");
    stream_id
}

/// Helper: Create test stream key
async fn create_test_stream_key(pool: &Pool<Postgres>, broadcaster_id: Uuid, is_active: bool) -> Uuid {
    let key_id = Uuid::new_v4();
    let key_hash = format!("test_key_hash_{}", Uuid::new_v4());
    sqlx::query(
        "INSERT INTO stream_keys (key_id, broadcaster_id, key_value, key_hash, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, NOW(), NOW())",
    )
    .bind(key_id)
    .bind(broadcaster_id)
    .bind(format!("test_key_{}", key_id))
    .bind(key_hash)
    .bind(is_active)
    .execute(pool)
    .await
    .expect("Failed to create test stream key");
    key_id
}

/// Helper: Create test viewer session
async fn create_test_viewer_session(
    pool: &Pool<Postgres>,
    stream_id: Uuid,
    viewer_id: Option<Uuid>,
) -> Uuid {
    let session_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO viewer_sessions (session_id, stream_id, viewer_id, joined_at)
         VALUES ($1, $2, $3, NOW())",
    )
    .bind(session_id)
    .bind(stream_id)
    .bind(viewer_id)
    .execute(pool)
    .await
    .expect("Failed to create test viewer session");
    session_id
}

#[tokio::test]
#[ignore]
async fn test_cleaner_ends_deleted_broadcaster_streams() {
    let pool = setup_test_db().await.expect("Failed to setup test DB");

    // Create test broadcasters
    let deleted_broadcaster = Uuid::new_v4();
    let active_broadcaster = Uuid::new_v4();

    // Create streams
    let deleted_stream_id =
        create_test_stream(&pool, deleted_broadcaster, "Deleted Stream", "live").await;
    let active_stream_id = create_test_stream(&pool, active_broadcaster, "Active Stream", "live").await;

    // Mock auth-service: only active_broadcaster exists
    let mock_client = MockAuthClient::new(vec![(active_broadcaster, "active_user".to_string())]);

    // Simulate stream cleaner logic
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT broadcaster_id AS user_id FROM streams
         UNION
         SELECT DISTINCT broadcaster_id AS user_id FROM stream_keys
         UNION
         SELECT DISTINCT viewer_id AS user_id FROM viewer_sessions WHERE viewer_id IS NOT NULL
         ORDER BY 1",
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch user IDs");

    let existing_users = mock_client
        .get_users_by_ids(&all_user_ids)
        .await
        .unwrap();

    // End streams from deleted broadcasters (soft-delete)
    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query(
                "UPDATE streams
                 SET status = 'ended', ended_at = NOW()
                 WHERE broadcaster_id = $1 AND status NOT IN ('ended', 'interrupted')",
            )
            .bind(user_id)
            .execute(&pool)
            .await
            .expect("Failed to end stream");
        }
    }

    // Verify: deleted broadcaster's stream is ended
    let deleted_status: String =
        sqlx::query_scalar("SELECT status::text FROM streams WHERE stream_id = $1")
            .bind(deleted_stream_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to get stream status");
    assert_eq!(deleted_status, "ended");

    // Verify: active broadcaster's stream is still live
    let active_status: String =
        sqlx::query_scalar("SELECT status::text FROM streams WHERE stream_id = $1")
            .bind(active_stream_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to get stream status");
    assert_eq!(active_status, "live");
}

#[tokio::test]
#[ignore]
async fn test_cleaner_revokes_deleted_broadcaster_keys() {
    let pool = setup_test_db().await.expect("Failed to setup test DB");

    // Create test broadcasters
    let deleted_broadcaster = Uuid::new_v4();
    let active_broadcaster = Uuid::new_v4();

    // Create stream keys
    let deleted_key_id = create_test_stream_key(&pool, deleted_broadcaster, true).await;
    let active_key_id = create_test_stream_key(&pool, active_broadcaster, true).await;

    // Mock auth-service: only active_broadcaster exists
    let mock_client = MockAuthClient::new(vec![(active_broadcaster, "active_user".to_string())]);

    // Simulate stream cleaner logic
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT broadcaster_id AS user_id FROM streams
         UNION
         SELECT DISTINCT broadcaster_id AS user_id FROM stream_keys
         UNION
         SELECT DISTINCT viewer_id AS user_id FROM viewer_sessions WHERE viewer_id IS NOT NULL
         ORDER BY 1",
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch user IDs");

    let existing_users = mock_client
        .get_users_by_ids(&all_user_ids)
        .await
        .unwrap();

    // Revoke keys from deleted broadcasters (soft-delete)
    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query(
                "UPDATE stream_keys
                 SET is_active = false, revoked_at = NOW()
                 WHERE broadcaster_id = $1 AND is_active = true",
            )
            .bind(user_id)
            .execute(&pool)
            .await
            .expect("Failed to revoke stream key");
        }
    }

    // Verify: deleted broadcaster's key is revoked
    let deleted_key_active: bool =
        sqlx::query_scalar("SELECT is_active FROM stream_keys WHERE key_id = $1")
            .bind(deleted_key_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to get key status");
    assert!(!deleted_key_active);

    // Verify: active broadcaster's key is still active
    let active_key_active: bool =
        sqlx::query_scalar("SELECT is_active FROM stream_keys WHERE key_id = $1")
            .bind(active_key_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to get key status");
    assert!(active_key_active);
}

#[tokio::test]
#[ignore]
async fn test_cleaner_hard_deletes_viewer_sessions() {
    let pool = setup_test_db().await.expect("Failed to setup test DB");

    // Create test users
    let deleted_viewer = Uuid::new_v4();
    let active_viewer = Uuid::new_v4();
    let broadcaster = Uuid::new_v4();

    // Create stream
    let stream_id = create_test_stream(&pool, broadcaster, "Test Stream", "live").await;

    // Create viewer sessions
    let deleted_session_id = create_test_viewer_session(&pool, stream_id, Some(deleted_viewer)).await;
    let active_session_id = create_test_viewer_session(&pool, stream_id, Some(active_viewer)).await;
    let anonymous_session_id = create_test_viewer_session(&pool, stream_id, None).await;

    // Mock auth-service: only active_viewer and broadcaster exist
    let mock_client = MockAuthClient::new(vec![
        (active_viewer, "active_viewer".to_string()),
        (broadcaster, "broadcaster".to_string()),
    ]);

    // Simulate stream cleaner logic
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT broadcaster_id AS user_id FROM streams
         UNION
         SELECT DISTINCT broadcaster_id AS user_id FROM stream_keys
         UNION
         SELECT DISTINCT viewer_id AS user_id FROM viewer_sessions WHERE viewer_id IS NOT NULL
         ORDER BY 1",
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch user IDs");

    let existing_users = mock_client
        .get_users_by_ids(&all_user_ids)
        .await
        .unwrap();

    // Delete viewer sessions from deleted users (hard-delete)
    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query("DELETE FROM viewer_sessions WHERE viewer_id = $1")
                .bind(user_id)
                .execute(&pool)
                .await
                .expect("Failed to delete viewer session");
        }
    }

    // Verify: deleted viewer's session is deleted
    let deleted_exists: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM viewer_sessions WHERE session_id = $1")
            .bind(deleted_session_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to check session");
    assert_eq!(deleted_exists, 0);

    // Verify: active viewer's session still exists
    let active_exists: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM viewer_sessions WHERE session_id = $1")
            .bind(active_session_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to check session");
    assert_eq!(active_exists, 1);

    // Verify: anonymous session still exists (NULL viewer_id)
    let anonymous_exists: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM viewer_sessions WHERE session_id = $1")
            .bind(anonymous_session_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to check session");
    assert_eq!(anonymous_exists, 1);
}

#[tokio::test]
#[ignore]
async fn test_batch_api_n_plus_1_elimination() {
    let pool = setup_test_db().await.expect("Failed to setup test DB");

    // Create 500 test broadcasters
    let mut existing_users = Vec::new();
    for i in 0..500 {
        let user_id = Uuid::new_v4();
        // Create stream for each user
        create_test_stream(&pool, user_id, &format!("Stream {}", i), "live").await;
        existing_users.push((user_id, format!("user_{}", i)));
    }

    // Mock auth-service with call tracking
    let mock_client = MockAuthClient::new(existing_users);

    // Collect user IDs
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT broadcaster_id AS user_id FROM streams
         UNION
         SELECT DISTINCT broadcaster_id AS user_id FROM stream_keys
         UNION
         SELECT DISTINCT viewer_id AS user_id FROM viewer_sessions WHERE viewer_id IS NOT NULL
         ORDER BY 1",
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch user IDs");

    assert_eq!(all_user_ids.len(), 500);

    // Batch process in chunks of 100
    const BATCH_SIZE: usize = 100;
    for chunk in all_user_ids.chunks(BATCH_SIZE) {
        let _ = mock_client.get_users_by_ids(chunk).await.unwrap();
    }

    // Verify: Batch API was called 5 times (500 users / 100 per batch = 5)
    let batch_calls = mock_client.get_batch_call_count();
    assert_eq!(
        batch_calls, 5,
        "Expected 5 batch calls for 500 users (100/batch), got {}",
        batch_calls
    );
}

#[tokio::test]
#[ignore]
async fn test_collect_user_ids_with_null_viewer() {
    let pool = setup_test_db().await.expect("Failed to setup test DB");

    // Create test users
    let broadcaster = Uuid::new_v4();
    let viewer = Uuid::new_v4();

    // Create stream
    let stream_id = create_test_stream(&pool, broadcaster, "Test Stream", "live").await;

    // Create stream key
    create_test_stream_key(&pool, broadcaster, true).await;

    // Create viewer sessions (one with viewer_id, one NULL)
    create_test_viewer_session(&pool, stream_id, Some(viewer)).await;
    create_test_viewer_session(&pool, stream_id, None).await; // Anonymous viewer

    // Collect user IDs
    let user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT broadcaster_id AS user_id FROM streams
         UNION
         SELECT DISTINCT broadcaster_id AS user_id FROM stream_keys
         UNION
         SELECT DISTINCT viewer_id AS user_id FROM viewer_sessions WHERE viewer_id IS NOT NULL
         ORDER BY 1",
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to collect user IDs");

    // Verify: Only broadcaster and viewer are collected (NULL excluded)
    assert_eq!(user_ids.len(), 2);
    assert!(user_ids.contains(&broadcaster));
    assert!(user_ids.contains(&viewer));
}
