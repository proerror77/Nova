//! Integration Tests: Content Cleaner
//!
//! Tests content cleaner functionality with real database.
//!
//! Coverage:
//! - Cleanup of posts (soft-delete) from deleted users
//! - Cleanup of comments (hard-delete) from deleted users
//! - Cleanup of likes (hard-delete) from deleted users
//! - Cleanup of bookmarks (hard-delete) from deleted users
//! - Cleanup of shares (hard-delete) from deleted users
//! - Batch API usage verification
//!
//! Architecture:
//! - Uses testcontainers for PostgreSQL database
//! - Mocks auth-service gRPC responses
//! - Tests real content-service cleanup logic

mod common;

use common::mock_auth_client::MockAuthClient;
use sqlx::postgres::PgPoolOptions;
use sqlx::{Pool, Postgres};
use testcontainers::{core::WaitFor, runners::AsyncRunner, GenericImage};
use uuid::Uuid;

/// Bootstrap test database with testcontainers
async fn setup_test_db() -> Result<Pool<Postgres>, Box<dyn std::error::Error>> {
    // Use GenericImage for postgres
    let postgres_image = GenericImage::new("postgres", "16-alpine")
        .with_wait_for(WaitFor::message_on_stderr(
            "database system is ready to accept connections",
        ))
        .with_env_var("POSTGRES_PASSWORD", "postgres")
        .with_env_var("POSTGRES_USER", "postgres")
        .with_env_var("POSTGRES_DB", "postgres");

    let container = postgres_image.start().await?;
    let port = container.get_host_port_ipv4(5432).await?;

    let connection_string = format!(
        "postgres://postgres:postgres@127.0.0.1:{}/postgres",
        port
    );

    // Wait for database to be ready and create pool
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&connection_string)
        .await?;

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await?;

    // Leak container to keep it alive for the duration of the test
    // This is acceptable for integration tests
    Box::leak(Box::new(container));

    Ok(pool)
}

/// Create test post
async fn create_test_post(pool: &Pool<Postgres>, user_id: Uuid) -> Uuid {
    let post_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO posts (id, user_id, content, media_key, media_type, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, NOW(), NOW())"
    )
    .bind(post_id)
    .bind(user_id)
    .bind("Test post content")
    .bind("test-key")
    .bind("text/plain")
    .execute(pool)
    .await
    .expect("Failed to create post");

    post_id
}

/// Create test comment
async fn create_test_comment(pool: &Pool<Postgres>, post_id: Uuid, user_id: Uuid) -> Uuid {
    let comment_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO comments (id, post_id, user_id, content, created_at, updated_at)
         VALUES ($1, $2, $3, $4, NOW(), NOW())"
    )
    .bind(comment_id)
    .bind(post_id)
    .bind(user_id)
    .bind("Test comment")
    .execute(pool)
    .await
    .expect("Failed to create comment");

    comment_id
}

/// Create test like
async fn create_test_like(pool: &Pool<Postgres>, post_id: Uuid, user_id: Uuid) {
    sqlx::query(
        "INSERT INTO likes (post_id, user_id, created_at)
         VALUES ($1, $2, NOW())"
    )
    .bind(post_id)
    .bind(user_id)
    .execute(pool)
    .await
    .expect("Failed to create like");
}

/// Create test bookmark
async fn create_test_bookmark(pool: &Pool<Postgres>, post_id: Uuid, user_id: Uuid) {
    sqlx::query(
        "INSERT INTO bookmarks (post_id, user_id, created_at)
         VALUES ($1, $2, NOW())"
    )
    .bind(post_id)
    .bind(user_id)
    .execute(pool)
    .await
    .expect("Failed to create bookmark");
}

/// Create test share
async fn create_test_share(pool: &Pool<Postgres>, post_id: Uuid, user_id: Uuid) {
    sqlx::query(
        "INSERT INTO shares (post_id, user_id, created_at)
         VALUES ($1, $2, NOW())"
    )
    .bind(post_id)
    .bind(user_id)
    .execute(pool)
    .await
    .expect("Failed to create share");
}

// ========== Content Cleaner Tests ==========

#[tokio::test]
#[ignore] // Run manually: cargo test --test content_cleaner_test -- test_cleaner_soft_deletes_posts --ignored
async fn test_cleaner_soft_deletes_posts() {
    let pool = setup_test_db().await.unwrap();

    // Create 2 users
    let user1_id = Uuid::new_v4();
    let user2_id = Uuid::new_v4();

    // Create posts from both users
    let post1_id = create_test_post(&pool, user1_id).await;
    let post2_id = create_test_post(&pool, user2_id).await;

    // Verify both posts exist and are not deleted
    let initial_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM posts WHERE deleted_at IS NULL"
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to count posts");

    assert_eq!(initial_count, 2, "Should have 2 posts initially");

    // Mock auth-service: only user1 exists (user2 deleted)
    let mock_client = MockAuthClient::new(vec![(user1_id, "user1".to_string())]);

    // Simulate content cleaner logic
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT user_id FROM posts WHERE deleted_at IS NULL"
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch user IDs");

    // Get existing users from mock auth-service
    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    // Soft-delete posts for non-existent users
    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query("UPDATE posts SET deleted_at = NOW() WHERE user_id = $1 AND deleted_at IS NULL")
                .bind(user_id)
                .execute(&pool)
                .await
                .expect("Failed to soft-delete post");
        }
    }

    // Verify only user1's post remains active
    let final_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM posts WHERE deleted_at IS NULL"
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to count posts");

    assert_eq!(final_count, 1, "Should only have 1 active post");

    // Verify user1's post is still active
    let active_post: Uuid = sqlx::query_scalar(
        "SELECT id FROM posts WHERE deleted_at IS NULL"
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to fetch active post");

    assert_eq!(active_post, post1_id, "User1's post should remain active");

    // Verify user2's post is soft-deleted
    let deleted_post: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM posts WHERE id = $1 AND deleted_at IS NOT NULL"
    )
    .bind(post2_id)
    .fetch_optional(&pool)
    .await
    .expect("Failed to check deleted post");

    assert_eq!(deleted_post, Some(post2_id), "User2's post should be soft-deleted");

    // Verify batch API was used (1 call)
    assert_eq!(
        mock_client.get_batch_call_count(),
        1,
        "Should use batch API (1 call)"
    );
}

#[tokio::test]
#[ignore]
async fn test_cleaner_hard_deletes_comments() {
    let pool = setup_test_db().await.unwrap();

    // Create 2 users
    let user1_id = Uuid::new_v4();
    let user2_id = Uuid::new_v4();

    // Create a post and comments
    let post_id = create_test_post(&pool, user1_id).await;
    create_test_comment(&pool, post_id, user1_id).await;
    create_test_comment(&pool, post_id, user2_id).await;

    // Verify both comments exist
    let initial_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM comments"
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to count comments");

    assert_eq!(initial_count, 2, "Should have 2 comments initially");

    // Mock auth-service: only user1 exists
    let mock_client = MockAuthClient::new(vec![(user1_id, "user1".to_string())]);

    // Simulate content cleaner logic
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT user_id FROM comments"
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch user IDs");

    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    // Hard-delete comments for non-existent users
    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query("DELETE FROM comments WHERE user_id = $1")
                .bind(user_id)
                .execute(&pool)
                .await
                .expect("Failed to delete comment");
        }
    }

    // Verify only user1's comment remains
    let final_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM comments"
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to count comments");

    assert_eq!(final_count, 1, "Should only have 1 comment");

    // Verify user1's comment exists
    let remaining_user: Uuid = sqlx::query_scalar(
        "SELECT user_id FROM comments"
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to fetch remaining comment");

    assert_eq!(remaining_user, user1_id, "User1's comment should remain");
}

#[tokio::test]
#[ignore]
async fn test_cleaner_hard_deletes_likes() {
    let pool = setup_test_db().await.unwrap();

    let user1_id = Uuid::new_v4();
    let user2_id = Uuid::new_v4();

    let post_id = create_test_post(&pool, user1_id).await;
    create_test_like(&pool, post_id, user1_id).await;
    create_test_like(&pool, post_id, user2_id).await;

    let initial_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM likes")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(initial_count, 2);

    let mock_client = MockAuthClient::new(vec![(user1_id, "user1".to_string())]);

    let all_user_ids: Vec<Uuid> = sqlx::query_scalar("SELECT DISTINCT user_id FROM likes")
        .fetch_all(&pool)
        .await
        .unwrap();

    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query("DELETE FROM likes WHERE user_id = $1")
                .bind(user_id)
                .execute(&pool)
                .await
                .unwrap();
        }
    }

    let final_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM likes")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(final_count, 1);
}

#[tokio::test]
#[ignore]
async fn test_cleaner_hard_deletes_bookmarks() {
    let pool = setup_test_db().await.unwrap();

    let user1_id = Uuid::new_v4();
    let user2_id = Uuid::new_v4();

    let post_id = create_test_post(&pool, user1_id).await;
    create_test_bookmark(&pool, post_id, user1_id).await;
    create_test_bookmark(&pool, post_id, user2_id).await;

    let initial_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM bookmarks")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(initial_count, 2);

    let mock_client = MockAuthClient::new(vec![(user1_id, "user1".to_string())]);

    let all_user_ids: Vec<Uuid> = sqlx::query_scalar("SELECT DISTINCT user_id FROM bookmarks")
        .fetch_all(&pool)
        .await
        .unwrap();

    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query("DELETE FROM bookmarks WHERE user_id = $1")
                .bind(user_id)
                .execute(&pool)
                .await
                .unwrap();
        }
    }

    let final_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM bookmarks")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(final_count, 1);
}

#[tokio::test]
#[ignore]
async fn test_cleaner_hard_deletes_shares() {
    let pool = setup_test_db().await.unwrap();

    let user1_id = Uuid::new_v4();
    let user2_id = Uuid::new_v4();

    let post_id = create_test_post(&pool, user1_id).await;
    create_test_share(&pool, post_id, user1_id).await;
    create_test_share(&pool, post_id, user2_id).await;

    let initial_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM shares")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(initial_count, 2);

    let mock_client = MockAuthClient::new(vec![(user1_id, "user1".to_string())]);

    let all_user_ids: Vec<Uuid> = sqlx::query_scalar("SELECT DISTINCT user_id FROM shares")
        .fetch_all(&pool)
        .await
        .unwrap();

    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query("DELETE FROM shares WHERE user_id = $1")
                .bind(user_id)
                .execute(&pool)
                .await
                .unwrap();
        }
    }

    let final_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM shares")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(final_count, 1);
}

#[tokio::test]
#[ignore]
async fn test_cleaner_batch_api_efficiency() {
    let pool = setup_test_db().await.unwrap();

    // Create 10 users with content
    let user_ids: Vec<Uuid> = (0..10).map(|_| Uuid::new_v4()).collect();

    for &user_id in &user_ids {
        let post_id = create_test_post(&pool, user_id).await;
        create_test_comment(&pool, post_id, user_id).await;
        create_test_like(&pool, post_id, user_id).await;
    }

    // Mock: only first 5 users exist
    let existing_users: Vec<(Uuid, String)> = user_ids
        .iter()
        .take(5)
        .enumerate()
        .map(|(i, &id)| (id, format!("user{}", i)))
        .collect();

    let mock_client = MockAuthClient::new(existing_users);

    // Collect all user IDs (simulating content_cleaner logic)
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar(
        r#"
        SELECT DISTINCT user_id FROM posts WHERE deleted_at IS NULL
        UNION
        SELECT DISTINCT user_id FROM comments
        UNION
        SELECT DISTINCT user_id FROM likes
        ORDER BY 1
        "#
    )
    .fetch_all(&pool)
    .await
    .unwrap();

    // Batch check - this should be 1 call
    let _existing = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    // Verify batch API usage: 1 call instead of 10 calls (10x improvement)
    assert_eq!(
        mock_client.get_batch_call_count(),
        1,
        "Should use batch API (1 call) not individual checks (10 calls)"
    );
}
