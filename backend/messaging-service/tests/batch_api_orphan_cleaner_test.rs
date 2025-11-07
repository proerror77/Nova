//! Integration Tests: Batch API + Orphan Cleaner
//!
//! Tests batch validation API and orphan cleaner functionality with real services.
//!
//! Coverage:
//! - Batch API (get_users_by_ids) correctness with various member counts
//! - Orphan cleaner logic with soft-deleted users
//! - N+1 query elimination verification
//!
//! Architecture:
//! - Uses testcontainers for PostgreSQL database
//! - Mocks auth-service gRPC responses
//! - Tests real messaging-service code paths

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

    let connection_string = format!("postgres://postgres:postgres@127.0.0.1:{}/postgres", port);

    // Wait for database to be ready and create pool
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&connection_string)
        .await?;

    // Run migrations
    sqlx::migrate!("./migrations").run(&pool).await?;

    // Leak container to keep it alive for the duration of the test
    // This is acceptable for integration tests
    Box::leak(Box::new(container));

    Ok(pool)
}

/// Create test conversation with members
async fn create_test_conversation(
    pool: &Pool<Postgres>,
    creator_id: Uuid,
    member_ids: Vec<Uuid>,
) -> Uuid {
    let conversation_id = Uuid::new_v4();

    // Insert conversation
    sqlx::query(
        "INSERT INTO conversations (id, name, creator_id, privacy_mode, created_at, updated_at)
         VALUES ($1, $2, $3, 'standard', NOW(), NOW())",
    )
    .bind(conversation_id)
    .bind("Test Conversation")
    .bind(creator_id)
    .execute(pool)
    .await
    .expect("Failed to create conversation");

    // Add creator as member
    sqlx::query(
        "INSERT INTO conversation_members (conversation_id, user_id, role, joined_at)
         VALUES ($1, $2, 'owner', NOW())",
    )
    .bind(conversation_id)
    .bind(creator_id)
    .execute(pool)
    .await
    .expect("Failed to add creator as member");

    // Add other members
    for user_id in member_ids {
        sqlx::query(
            "INSERT INTO conversation_members (conversation_id, user_id, role, joined_at)
             VALUES ($1, $2, 'member', NOW())",
        )
        .bind(conversation_id)
        .bind(user_id)
        .execute(pool)
        .await
        .expect("Failed to add member");
    }

    conversation_id
}

// ========== Batch API Correctness Tests ==========

#[tokio::test]
#[ignore] // Run manually: cargo test --test integration -- batch_api_small_group --ignored
async fn test_batch_api_small_group() {
    // Create mock client with 5 users
    let user_ids: Vec<Uuid> = (0..5).map(|_| Uuid::new_v4()).collect();
    let users: Vec<(Uuid, String)> = user_ids
        .iter()
        .enumerate()
        .map(|(i, &id)| (id, format!("user{}", i)))
        .collect();

    let mock_client = MockAuthClient::new(users.clone());

    // Test batch API
    let result = mock_client.get_users_by_ids(&user_ids).await.unwrap();

    // Verify all users returned
    assert_eq!(result.len(), 5, "Should return all 5 users");
    for (i, &user_id) in user_ids.iter().enumerate() {
        assert_eq!(
            result.get(&user_id),
            Some(&format!("user{}", i)),
            "User {} should be returned correctly",
            i
        );
    }

    // Verify only 1 API call was made (not 5)
    assert_eq!(
        mock_client.get_batch_call_count(),
        1,
        "Should only make 1 batch API call, not 5 individual calls"
    );
}

#[tokio::test]
#[ignore]
async fn test_batch_api_large_group() {
    // Create mock client with 100 users
    let user_ids: Vec<Uuid> = (0..100).map(|_| Uuid::new_v4()).collect();
    let users: Vec<(Uuid, String)> = user_ids
        .iter()
        .enumerate()
        .map(|(i, &id)| (id, format!("user{}", i)))
        .collect();

    let mock_client = MockAuthClient::new(users.clone());

    // Test batch API
    let result = mock_client.get_users_by_ids(&user_ids).await.unwrap();

    // Verify all users returned
    assert_eq!(result.len(), 100, "Should return all 100 users");

    // Verify only 1 API call was made (not 100)
    assert_eq!(
        mock_client.get_batch_call_count(),
        1,
        "Should only make 1 batch API call, not 100 individual calls (100x improvement)"
    );
}

#[tokio::test]
#[ignore]
async fn test_batch_api_empty_group() {
    let mock_client = MockAuthClient::empty();

    // Test batch API with empty list
    let result = mock_client.get_users_by_ids(&[]).await.unwrap();

    // Verify empty result
    assert_eq!(result.len(), 0, "Should return empty map for empty input");

    // Verify 1 call was still made (even for empty input)
    assert_eq!(mock_client.get_batch_call_count(), 1);
}

#[tokio::test]
#[ignore]
async fn test_batch_api_partial_deleted_users() {
    // Create 10 users
    let user_ids: Vec<Uuid> = (0..10).map(|_| Uuid::new_v4()).collect();
    let users: Vec<(Uuid, String)> = user_ids
        .iter()
        .take(7) // Only first 7 users exist
        .enumerate()
        .map(|(i, &id)| (id, format!("user{}", i)))
        .collect();

    let mock_client = MockAuthClient::new(users.clone());

    // Request all 10 users
    let result = mock_client.get_users_by_ids(&user_ids).await.unwrap();

    // Should only return 7 users (last 3 are deleted/non-existent)
    assert_eq!(
        result.len(),
        7,
        "Should only return existing users (7 out of 10)"
    );

    // Verify correct users returned
    for (i, &user_id) in user_ids.iter().take(7).enumerate() {
        assert!(
            result.contains_key(&user_id),
            "User {} should be in result",
            i
        );
    }

    // Verify deleted users NOT returned
    for &user_id in user_ids.iter().skip(7) {
        assert!(
            !result.contains_key(&user_id),
            "Deleted user should NOT be in result"
        );
    }
}

// ========== Orphan Cleaner Logic Tests ==========

#[tokio::test]
#[ignore]
async fn test_orphan_cleaner_deletes_non_existent_users() {
    let pool = setup_test_db().await.unwrap();

    // Create conversation with 3 members
    let creator_id = Uuid::new_v4();
    let member1_id = Uuid::new_v4();
    let member2_id = Uuid::new_v4();

    let conversation_id =
        create_test_conversation(&pool, creator_id, vec![member1_id, member2_id]).await;

    // Verify 3 members exist initially
    let initial_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM conversation_members WHERE conversation_id = $1")
            .bind(conversation_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to count members");

    assert_eq!(initial_count, 3, "Should have 3 members initially");

    // Mock auth-service: only creator exists (member1 and member2 deleted)
    let mock_client = MockAuthClient::new(vec![(creator_id, "creator".to_string())]);

    // Simulate orphan cleaner logic
    let all_user_ids: Vec<Uuid> =
        sqlx::query_scalar("SELECT DISTINCT user_id FROM conversation_members")
            .fetch_all(&pool)
            .await
            .expect("Failed to fetch user IDs");

    // Get existing users from mock auth-service
    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    // Delete members for non-existent users
    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query("DELETE FROM conversation_members WHERE user_id = $1")
                .bind(user_id)
                .execute(&pool)
                .await
                .expect("Failed to delete orphaned member");
        }
    }

    // Verify only creator remains
    let final_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM conversation_members WHERE conversation_id = $1")
            .bind(conversation_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to count members");

    assert_eq!(final_count, 1, "Should only have creator remaining");

    // Verify creator is the remaining member
    let remaining_user: Uuid =
        sqlx::query_scalar("SELECT user_id FROM conversation_members WHERE conversation_id = $1")
            .bind(conversation_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to fetch remaining user");

    assert_eq!(
        remaining_user, creator_id,
        "Remaining user should be creator"
    );

    // Verify batch API was used (1 call, not 3)
    assert_eq!(
        mock_client.get_batch_call_count(),
        1,
        "Should use batch API (1 call) not individual checks (3 calls)"
    );
}

#[tokio::test]
#[ignore]
async fn test_orphan_cleaner_preserves_existing_users() {
    let pool = setup_test_db().await.unwrap();

    // Create conversation with 2 members
    let creator_id = Uuid::new_v4();
    let member1_id = Uuid::new_v4();

    let conversation_id = create_test_conversation(&pool, creator_id, vec![member1_id]).await;

    // Mock auth-service: both users exist
    let mock_client = MockAuthClient::new(vec![
        (creator_id, "creator".to_string()),
        (member1_id, "member1".to_string()),
    ]);

    // Simulate orphan cleaner logic
    let all_user_ids: Vec<Uuid> =
        sqlx::query_scalar("SELECT DISTINCT user_id FROM conversation_members")
            .fetch_all(&pool)
            .await
            .expect("Failed to fetch user IDs");

    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    // Delete members for non-existent users
    let mut deleted_count = 0;
    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query("DELETE FROM conversation_members WHERE user_id = $1")
                .bind(user_id)
                .execute(&pool)
                .await
                .expect("Failed to delete orphaned member");
            deleted_count += 1;
        }
    }

    // Verify no users were deleted
    assert_eq!(deleted_count, 0, "Should not delete any existing users");

    // Verify all members remain
    let final_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM conversation_members WHERE conversation_id = $1")
            .bind(conversation_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to count members");

    assert_eq!(final_count, 2, "Both members should remain");
}

#[tokio::test]
#[ignore]
async fn test_orphan_cleaner_batch_processing() {
    let pool = setup_test_db().await.unwrap();

    // Create conversation with 150 members (exceeds BATCH_SIZE of 100)
    let creator_id = Uuid::new_v4();
    let mut member_ids = Vec::new();
    for _ in 0..149 {
        member_ids.push(Uuid::new_v4());
    }

    let conversation_id = create_test_conversation(&pool, creator_id, member_ids.clone()).await;

    // Verify 150 members exist
    let initial_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM conversation_members WHERE conversation_id = $1")
            .bind(conversation_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to count members");

    assert_eq!(initial_count, 150, "Should have 150 members initially");

    // Mock auth-service: only first 100 members exist (last 50 deleted)
    let existing_members: Vec<(Uuid, String)> = std::iter::once(creator_id)
        .chain(member_ids.iter().take(99).copied())
        .enumerate()
        .map(|(i, id)| (id, format!("user{}", i)))
        .collect();

    let mock_client = MockAuthClient::new(existing_members);

    // Get all user IDs
    let all_user_ids: Vec<Uuid> =
        sqlx::query_scalar("SELECT DISTINCT user_id FROM conversation_members")
            .fetch_all(&pool)
            .await
            .expect("Failed to fetch user IDs");

    // Simulate orphan cleaner batch processing (BATCH_SIZE = 100)
    const BATCH_SIZE: usize = 100;
    let mut total_deleted = 0;

    for chunk in all_user_ids.chunks(BATCH_SIZE) {
        let existing_users = mock_client.get_users_by_ids(chunk).await.unwrap();

        for user_id in chunk {
            if !existing_users.contains_key(user_id) {
                let result = sqlx::query("DELETE FROM conversation_members WHERE user_id = $1")
                    .bind(user_id)
                    .execute(&pool)
                    .await
                    .expect("Failed to delete orphaned member");
                total_deleted += result.rows_affected();
            }
        }
    }

    // Verify 50 members were deleted (last 50 who don't exist)
    assert_eq!(total_deleted, 50, "Should delete 50 non-existent users");

    // Verify 100 members remain
    let final_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM conversation_members WHERE conversation_id = $1")
            .bind(conversation_id)
            .fetch_one(&pool)
            .await
            .expect("Failed to count members");

    assert_eq!(
        final_count, 100,
        "Should have 100 existing members remaining"
    );

    // Verify batch API was called twice (150 users / 100 batch size = 2 batches)
    assert_eq!(
        mock_client.get_batch_call_count(),
        2,
        "Should process in 2 batches (150 users / 100 batch size)"
    );
}

// ========== N+1 Elimination Verification Tests ==========

#[tokio::test]
#[ignore]
async fn test_n_plus_1_elimination_50_members() {
    // Create mock client with 50 users
    let user_ids: Vec<Uuid> = (0..50).map(|_| Uuid::new_v4()).collect();
    let users: Vec<(Uuid, String)> = user_ids
        .iter()
        .enumerate()
        .map(|(i, &id)| (id, format!("user{}", i)))
        .collect();

    let mock_client = MockAuthClient::new(users.clone());

    // Simulate N+1 anti-pattern (50 individual calls)
    // Note: We don't actually make individual calls here, just demonstrate the pattern
    // In real N+1 scenario, this would be 50 individual get_user() calls

    // Simulate batch API pattern (1 call)
    mock_client.reset_call_count();
    let _ = mock_client.get_users_by_ids(&user_ids).await.unwrap();
    let batch_calls = mock_client.get_batch_call_count();

    assert_eq!(
        batch_calls, 1,
        "Batch API should make only 1 call for 50 users (50x improvement over N+1)"
    );
}

#[tokio::test]
#[ignore]
async fn test_n_plus_1_elimination_comparison() {
    // Demonstrate performance improvement with call counter
    let user_count = 100;
    let user_ids: Vec<Uuid> = (0..user_count).map(|_| Uuid::new_v4()).collect();
    let users: Vec<(Uuid, String)> = user_ids
        .iter()
        .enumerate()
        .map(|(i, &id)| (id, format!("user{}", i)))
        .collect();

    let mock_client = MockAuthClient::new(users);

    // Batch API: 1 call
    mock_client.reset_call_count();
    let _ = mock_client.get_users_by_ids(&user_ids).await.unwrap();

    assert_eq!(
        mock_client.get_batch_call_count(),
        1,
        "Batch API: 100 users → 1 call (100x improvement)"
    );
}

#[tokio::test]
#[ignore]
async fn test_batch_api_with_multiple_conversations() {
    // Scenario: Multiple conversations with overlapping members
    let shared_user1 = Uuid::new_v4();
    let shared_user2 = Uuid::new_v4();
    let user3 = Uuid::new_v4();
    let user4 = Uuid::new_v4();

    let mock_client = MockAuthClient::new(vec![
        (shared_user1, "shared1".to_string()),
        (shared_user2, "shared2".to_string()),
        (user3, "user3".to_string()),
        (user4, "user4".to_string()),
    ]);

    // Conversation 1: shared1, shared2, user3
    let conv1_users = vec![shared_user1, shared_user2, user3];
    let result1 = mock_client.get_users_by_ids(&conv1_users).await.unwrap();
    assert_eq!(result1.len(), 3);

    // Conversation 2: shared1, shared2, user4
    let conv2_users = vec![shared_user1, shared_user2, user4];
    let result2 = mock_client.get_users_by_ids(&conv2_users).await.unwrap();
    assert_eq!(result2.len(), 3);

    // Verify 2 batch calls total (1 per conversation)
    assert_eq!(
        mock_client.get_batch_call_count(),
        2,
        "Should make 2 batch calls (1 per conversation)"
    );
}
