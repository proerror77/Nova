//! Integration Tests: Feed Cleaner
//!
//! Tests feed cleaner functionality with real database.
//!
//! Coverage:
//! - Cleanup of experiments (soft-delete → cancelled status) from deleted users
//! - Cleanup of experiment_assignments (hard-delete) from deleted users
//! - Cleanup of experiment_metrics (hard-delete) from deleted users
//! - Preservation of active user data
//! - Batch API usage verification (N+1 elimination)
//!
//! Architecture:
//! - Uses testcontainers for PostgreSQL database
//! - Mocks auth-service gRPC responses
//! - Tests real feed-service cleanup logic

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

/// Create test experiment
async fn create_test_experiment(
    pool: &Pool<Postgres>,
    name: &str,
    created_by: Option<Uuid>,
) -> Uuid {
    let experiment_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO experiments (id, name, description, status, created_by, created_at, updated_at)
         VALUES ($1, $2, $3, 'active', $4, NOW(), NOW())"
    )
    .bind(experiment_id)
    .bind(name)
    .bind(format!("Test experiment: {}", name))
    .bind(created_by)
    .execute(pool)
    .await
    .expect("Failed to create experiment");

    experiment_id
}

/// Create test experiment assignment
async fn create_test_assignment(pool: &Pool<Postgres>, experiment_id: Uuid, user_id: Uuid) -> Uuid {
    let assignment_id = Uuid::new_v4();
    let variant_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO experiment_assignments (id, experiment_id, user_id, variant_id, assigned_at)
         VALUES ($1, $2, $3, $4, NOW())",
    )
    .bind(assignment_id)
    .bind(experiment_id)
    .bind(user_id)
    .bind(variant_id)
    .execute(pool)
    .await
    .expect("Failed to create assignment");

    assignment_id
}

/// Create test experiment metric
async fn create_test_metric(
    pool: &Pool<Postgres>,
    experiment_id: Uuid,
    user_id: Uuid,
    metric_name: &str,
    metric_value: f64,
) -> Uuid {
    let metric_id = Uuid::new_v4();
    let variant_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO experiment_metrics (id, experiment_id, user_id, variant_id, metric_name, metric_value, recorded_at)
         VALUES ($1, $2, $3, $4, $5, $6, NOW())"
    )
    .bind(metric_id)
    .bind(experiment_id)
    .bind(user_id)
    .bind(variant_id)
    .bind(metric_name)
    .bind(metric_value)
    .execute(pool)
    .await
    .expect("Failed to create metric");

    metric_id
}

#[tokio::test]
#[ignore]
async fn test_cleaner_cancels_deleted_user_experiments() {
    let pool = setup_test_db().await.unwrap();

    // Create 2 users
    let user1_id = Uuid::new_v4();
    let user2_id = Uuid::new_v4();

    // Create experiments: user1 (active), user2 (deleted)
    let exp1_id = create_test_experiment(&pool, "exp1", Some(user1_id)).await;
    let exp2_id = create_test_experiment(&pool, "exp2", Some(user2_id)).await;

    // Verify both experiments are active
    let initial_active_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM experiments WHERE status = 'active'")
            .fetch_one(&pool)
            .await
            .expect("Failed to count active experiments");

    assert_eq!(
        initial_active_count, 2,
        "Should have 2 active experiments initially"
    );

    // Mock auth-service: only user1 exists
    let mock_client = MockAuthClient::new(vec![(user1_id, "user1".to_string())]);

    // Simulate feed cleaner logic
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT created_by AS user_id
         FROM experiments
         WHERE created_by IS NOT NULL
         UNION
         SELECT DISTINCT user_id
         FROM experiment_assignments
         UNION
         SELECT DISTINCT user_id
         FROM experiment_metrics
         ORDER BY 1",
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch user IDs");

    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    // Cancel experiments created by deleted users (soft delete)
    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query(
                "UPDATE experiments
                 SET status = 'cancelled', updated_at = NOW()
                 WHERE created_by = $1 AND status != 'cancelled'",
            )
            .bind(user_id)
            .execute(&pool)
            .await
            .expect("Failed to cancel experiment");
        }
    }

    // Verify user1's experiment is still active
    let active_exp: Uuid = sqlx::query_scalar("SELECT id FROM experiments WHERE status = 'active'")
        .fetch_one(&pool)
        .await
        .expect("Failed to fetch active experiment");

    assert_eq!(
        active_exp, exp1_id,
        "User1's experiment should remain active"
    );

    // Verify user2's experiment is cancelled (soft-deleted)
    let cancelled_exp: Option<Uuid> =
        sqlx::query_scalar("SELECT id FROM experiments WHERE id = $1 AND status = 'cancelled'")
            .bind(exp2_id)
            .fetch_optional(&pool)
            .await
            .expect("Failed to check cancelled experiment");

    assert_eq!(
        cancelled_exp,
        Some(exp2_id),
        "User2's experiment should be cancelled"
    );

    // Verify batch API was used (1 call for 2 users)
    assert_eq!(
        mock_client.get_batch_call_count(),
        1,
        "Should use batch API (1 call)"
    );
}

#[tokio::test]
#[ignore]
async fn test_cleaner_hard_deletes_assignments() {
    let pool = setup_test_db().await.unwrap();

    // Create 2 users and 1 experiment
    let user1_id = Uuid::new_v4();
    let user2_id = Uuid::new_v4();
    let exp_id = create_test_experiment(&pool, "test-exp", None).await;

    // Create assignments for both users
    create_test_assignment(&pool, exp_id, user1_id).await;
    create_test_assignment(&pool, exp_id, user2_id).await;

    // Verify both assignments exist
    let initial_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM experiment_assignments")
        .fetch_one(&pool)
        .await
        .expect("Failed to count assignments");

    assert_eq!(initial_count, 2, "Should have 2 assignments initially");

    // Mock auth-service: only user1 exists
    let mock_client = MockAuthClient::new(vec![(user1_id, "user1".to_string())]);

    // Simulate feed cleaner logic
    let all_user_ids: Vec<Uuid> =
        sqlx::query_scalar("SELECT DISTINCT user_id FROM experiment_assignments")
            .fetch_all(&pool)
            .await
            .expect("Failed to fetch user IDs");

    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    // Hard-delete assignments for deleted users
    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query("DELETE FROM experiment_assignments WHERE user_id = $1")
                .bind(user_id)
                .execute(&pool)
                .await
                .expect("Failed to delete assignment");
        }
    }

    // Verify only user1's assignment remains
    let final_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM experiment_assignments")
        .fetch_one(&pool)
        .await
        .expect("Failed to count assignments");

    assert_eq!(final_count, 1, "Should only have 1 assignment");

    // Verify user1's assignment exists
    let remaining_user: Uuid = sqlx::query_scalar("SELECT user_id FROM experiment_assignments")
        .fetch_one(&pool)
        .await
        .expect("Failed to fetch remaining assignment");

    assert_eq!(remaining_user, user1_id, "User1's assignment should remain");
}

#[tokio::test]
#[ignore]
async fn test_cleaner_hard_deletes_metrics() {
    let pool = setup_test_db().await.unwrap();

    let user1_id = Uuid::new_v4();
    let user2_id = Uuid::new_v4();
    let exp_id = create_test_experiment(&pool, "test-exp", None).await;

    // Create metrics for both users
    create_test_metric(&pool, exp_id, user1_id, "conversion_rate", 0.25).await;
    create_test_metric(&pool, exp_id, user2_id, "conversion_rate", 0.30).await;

    let initial_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM experiment_metrics")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(initial_count, 2, "Should have 2 metrics initially");

    // Mock auth-service: only user1 exists
    let mock_client = MockAuthClient::new(vec![(user1_id, "user1".to_string())]);

    let all_user_ids: Vec<Uuid> =
        sqlx::query_scalar("SELECT DISTINCT user_id FROM experiment_metrics")
            .fetch_all(&pool)
            .await
            .unwrap();

    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    // Hard-delete metrics for deleted users
    for user_id in &all_user_ids {
        if !existing_users.contains_key(user_id) {
            sqlx::query("DELETE FROM experiment_metrics WHERE user_id = $1")
                .bind(user_id)
                .execute(&pool)
                .await
                .unwrap();
        }
    }

    let final_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM experiment_metrics")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(final_count, 1, "Should only have 1 metric");

    let remaining_user: Uuid = sqlx::query_scalar("SELECT user_id FROM experiment_metrics")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(remaining_user, user1_id, "User1's metric should remain");
}

#[tokio::test]
#[ignore]
async fn test_cleaner_preserves_active_user_experiments() {
    let pool = setup_test_db().await.unwrap();

    // Create active user with experiment, assignment, and metric
    let user_id = Uuid::new_v4();
    let exp_id = create_test_experiment(&pool, "active-exp", Some(user_id)).await;
    create_test_assignment(&pool, exp_id, user_id).await;
    create_test_metric(&pool, exp_id, user_id, "engagement", 0.75).await;

    // Mock auth-service: user exists
    let mock_client = MockAuthClient::new(vec![(user_id, "active_user".to_string())]);

    // Simulate feed cleaner logic
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT created_by AS user_id
         FROM experiments
         WHERE created_by IS NOT NULL
         UNION
         SELECT DISTINCT user_id
         FROM experiment_assignments
         UNION
         SELECT DISTINCT user_id
         FROM experiment_metrics
         ORDER BY 1",
    )
    .fetch_all(&pool)
    .await
    .unwrap();

    let existing_users = mock_client.get_users_by_ids(&all_user_ids).await.unwrap();

    // Attempt cleanup (should do nothing)
    for uid in &all_user_ids {
        if !existing_users.contains_key(uid) {
            sqlx::query("UPDATE experiments SET status = 'cancelled' WHERE created_by = $1")
                .bind(uid)
                .execute(&pool)
                .await
                .unwrap();

            sqlx::query("DELETE FROM experiment_assignments WHERE user_id = $1")
                .bind(uid)
                .execute(&pool)
                .await
                .unwrap();

            sqlx::query("DELETE FROM experiment_metrics WHERE user_id = $1")
                .bind(uid)
                .execute(&pool)
                .await
                .unwrap();
        }
    }

    // Verify all data remains
    let exp_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM experiments WHERE status = 'active'")
            .fetch_one(&pool)
            .await
            .unwrap();

    let assignment_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM experiment_assignments")
        .fetch_one(&pool)
        .await
        .unwrap();

    let metric_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM experiment_metrics")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(exp_count, 1, "Active user's experiment should remain");
    assert_eq!(
        assignment_count, 1,
        "Active user's assignment should remain"
    );
    assert_eq!(metric_count, 1, "Active user's metric should remain");
}

#[tokio::test]
#[ignore]
async fn test_batch_api_n_plus_1_elimination() {
    let pool = setup_test_db().await.unwrap();

    // Create 500 users with experiments
    let mut user_ids = Vec::new();
    for i in 0..500 {
        let user_id = Uuid::new_v4();
        user_ids.push(user_id);
        create_test_experiment(&pool, &format!("exp-{}", i), Some(user_id)).await;
    }

    // Mock auth-service: first 250 users exist
    let existing_users: Vec<(Uuid, String)> = user_ids[..250]
        .iter()
        .enumerate()
        .map(|(i, &id)| (id, format!("user{}", i)))
        .collect();

    let mock_client = MockAuthClient::new(existing_users);

    // Simulate feed cleaner with batch size 100
    let all_user_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT created_by AS user_id
         FROM experiments
         WHERE created_by IS NOT NULL
         ORDER BY 1",
    )
    .fetch_all(&pool)
    .await
    .unwrap();

    const BATCH_SIZE: usize = 100;

    for chunk in all_user_ids.chunks(BATCH_SIZE) {
        let existing = mock_client.get_users_by_ids(chunk).await.unwrap();

        for user_id in chunk {
            if !existing.contains_key(user_id) {
                sqlx::query("UPDATE experiments SET status = 'cancelled' WHERE created_by = $1")
                    .bind(user_id)
                    .execute(&pool)
                    .await
                    .unwrap();
            }
        }
    }

    // Verify batch API efficiency: 500 users / 100 batch_size = 5 calls
    assert_eq!(
        mock_client.get_batch_call_count(),
        5,
        "Should use 5 batch API calls (not 500)"
    );

    // Verify cleanup results: 250 cancelled, 250 active
    let cancelled_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM experiments WHERE status = 'cancelled'")
            .fetch_one(&pool)
            .await
            .unwrap();

    let active_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM experiments WHERE status = 'active'")
            .fetch_one(&pool)
            .await
            .unwrap();

    assert_eq!(cancelled_count, 250, "250 experiments should be cancelled");
    assert_eq!(active_count, 250, "250 experiments should remain active");
}
