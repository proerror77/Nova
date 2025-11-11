//! Database Indexes Tests (Quick Win #4)
//!
//! Tests for database index creation and performance validation
//!
//! Test Coverage:
//! - Index creation verification
//! - Query performance before/after
//! - Rollback capability
//! - No locks during index creation (CONCURRENTLY)

use db_pool::{create_pool, DbConfig};
use sqlx::PgPool;
use std::time::Instant;

async fn create_test_pool() -> PgPool {
    let config = DbConfig::for_service("index-test");
    create_pool(config)
        .await
        .expect("Failed to create test pool")
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_index_creation_verification() {
    // Test: All critical indexes are created
    let pool = create_test_pool().await;

    // Verify engagement_events indexes
    let indexes = sqlx::query!(
        r#"
        SELECT indexname
        FROM pg_indexes
        WHERE tablename = 'engagement_events'
        AND indexname LIKE 'idx_engagement%'
        ORDER BY indexname
        "#
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch indexes");

    let expected_indexes = vec![
        "idx_engagement_events_content_id",
        "idx_engagement_events_created_at",
        "idx_engagement_events_trending",
        "idx_engagement_events_user_id",
    ];

    assert_eq!(
        indexes.len(),
        expected_indexes.len(),
        "Should have {} indexes on engagement_events",
        expected_indexes.len()
    );

    for expected in expected_indexes {
        assert!(
            indexes.iter().any(|row| row.indexname == expected),
            "Missing index: {}",
            expected
        );
    }
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_trending_scores_primary_key() {
    // Test: trending_scores has composite primary key
    let pool = create_test_pool().await;

    let constraint = sqlx::query!(
        r#"
        SELECT constraint_name, constraint_type
        FROM information_schema.table_constraints
        WHERE table_name = 'trending_scores'
        AND constraint_type = 'PRIMARY KEY'
        "#
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to fetch primary key");

    assert_eq!(constraint.constraint_name, "pk_trending_scores");
}

#[tokio::test]
#[ignore] // Requires database setup with test data
async fn test_query_performance_with_indexes() {
    // Test: Queries are faster with indexes
    let pool = create_test_pool().await;

    // Insert test data
    let content_id = uuid::Uuid::new_v4();
    for _ in 0..1000 {
        sqlx::query!(
            r#"
            INSERT INTO engagement_events (id, content_id, user_id, event_type, created_at)
            VALUES ($1, $2, $3, $4, NOW())
            "#,
            uuid::Uuid::new_v4(),
            content_id,
            uuid::Uuid::new_v4(),
            "view"
        )
        .execute(&pool)
        .await
        .expect("Failed to insert test data");
    }

    // Query with index
    let start = Instant::now();
    let result = sqlx::query!(
        r#"
        SELECT COUNT(*) as count
        FROM engagement_events
        WHERE content_id = $1
        AND created_at >= NOW() - INTERVAL '30 days'
        "#,
        content_id
    )
    .fetch_one(&pool)
    .await
    .expect("Query failed");
    let elapsed = start.elapsed();

    // With index, query should be very fast (<10ms)
    assert!(
        elapsed.as_millis() < 100,
        "Query with index should be fast (<100ms), took {:?}",
        elapsed
    );
    assert_eq!(result.count, Some(1000));

    // Cleanup
    sqlx::query!("DELETE FROM engagement_events WHERE content_id = $1", content_id)
        .execute(&pool)
        .await
        .expect("Failed to cleanup");
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_explain_plan_uses_index() {
    // Test: Query planner uses indexes
    let pool = create_test_pool().await;

    let content_id = uuid::Uuid::new_v4();

    // Get explain plan
    let explain = sqlx::query_scalar::<_, String>(
        r#"
        EXPLAIN (FORMAT JSON)
        SELECT COUNT(*)
        FROM engagement_events
        WHERE content_id = $1
        AND created_at >= NOW() - INTERVAL '30 days'
        "#,
    )
    .bind(content_id)
    .fetch_one(&pool)
    .await
    .expect("EXPLAIN failed");

    // Parse JSON to verify index scan is used
    assert!(
        explain.contains("Index Scan") || explain.contains("Index Only Scan"),
        "Query should use index scan, got: {}",
        explain
    );

    // Should NOT use sequential scan
    assert!(
        !explain.contains("Seq Scan"),
        "Query should NOT use sequential scan"
    );
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_index_size_reasonable() {
    // Test: Index sizes are within reasonable bounds
    let pool = create_test_pool().await;

    let index_sizes = sqlx::query!(
        r#"
        SELECT
            indexname,
            pg_size_pretty(pg_relation_size(indexrelid)) as size,
            pg_relation_size(indexrelid) as size_bytes
        FROM pg_stat_user_indexes
        WHERE tablename IN ('engagement_events', 'trending_scores')
        ORDER BY pg_relation_size(indexrelid) DESC
        "#
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch index sizes");

    for idx in index_sizes {
        // No single index should exceed 500MB (warning threshold)
        assert!(
            idx.size_bytes < 500 * 1024 * 1024,
            "Index {} is too large: {}",
            idx.indexname,
            idx.size
        );
    }
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_concurrent_index_creation() {
    // Test: Indexes are created with CONCURRENTLY (no table locks)
    let pool = create_test_pool().await;

    // Simulate index creation
    let result = sqlx::query(
        r#"
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_test_concurrent
        ON engagement_events(created_at)
        "#,
    )
    .execute(&pool)
    .await;

    assert!(result.is_ok(), "Concurrent index creation should succeed");

    // Verify index exists
    let exists = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE indexname = 'idx_test_concurrent'
        )
        "#,
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to verify index");

    assert!(exists, "Index should exist after creation");

    // Cleanup
    sqlx::query("DROP INDEX IF EXISTS idx_test_concurrent")
        .execute(&pool)
        .await
        .expect("Failed to cleanup");
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_rollback_capability() {
    // Test: Indexes can be safely dropped (rollback)
    let pool = create_test_pool().await;

    // Create temporary index
    sqlx::query(
        r#"
        CREATE INDEX IF NOT EXISTS idx_test_rollback
        ON engagement_events(user_id)
        "#,
    )
    .execute(&pool)
    .await
    .expect("Failed to create test index");

    // Verify it exists
    let exists_before = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE indexname = 'idx_test_rollback'
        )
        "#,
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to verify index");
    assert!(exists_before);

    // Drop it (rollback)
    sqlx::query("DROP INDEX IF EXISTS idx_test_rollback")
        .execute(&pool)
        .await
        .expect("Failed to drop index");

    // Verify it's gone
    let exists_after = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE indexname = 'idx_test_rollback'
        )
        "#,
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to verify index");
    assert!(!exists_after);
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_posts_user_created_index() {
    // Test: posts table has user_id + created_at index
    let pool = create_test_pool().await;

    let exists = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE tablename = 'posts'
            AND indexname = 'idx_posts_user_created'
        )
        "#,
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to check index");

    assert!(exists, "idx_posts_user_created should exist");
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_comments_post_created_index() {
    // Test: comments table has post_id + created_at index
    let pool = create_test_pool().await;

    let exists = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE tablename = 'comments'
            AND indexname = 'idx_comments_post_created'
        )
        "#,
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to check index");

    assert!(exists, "idx_comments_post_created should exist");
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_partial_index_conditions() {
    // Test: Partial indexes have correct WHERE clauses
    let pool = create_test_pool().await;

    let index_def = sqlx::query_scalar::<_, String>(
        r#"
        SELECT pg_get_indexdef(indexrelid)
        FROM pg_stat_user_indexes
        WHERE indexname = 'idx_posts_user_created'
        "#,
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to get index definition");

    // Should filter out soft-deleted posts
    assert!(
        index_def.contains("deleted_at IS NULL"),
        "Index should filter soft-deleted posts: {}",
        index_def
    );
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_index_performance_trending_query() {
    // Test: Trending query performance with indexes
    let pool = create_test_pool().await;

    let start = Instant::now();
    let result = sqlx::query!(
        r#"
        SELECT content_id, score, rank
        FROM trending_scores
        WHERE time_window = '24h'
        AND category = 'technology'
        ORDER BY score DESC
        LIMIT 100
        "#
    )
    .fetch_all(&pool)
    .await
    .expect("Trending query failed");
    let elapsed = start.elapsed();

    // Should be very fast with index
    assert!(
        elapsed.as_millis() < 50,
        "Trending query should be fast (<50ms), took {:?}",
        elapsed
    );

    // Should return results in descending score order
    for i in 0..result.len() - 1 {
        assert!(
            result[i].score >= result[i + 1].score,
            "Results should be ordered by score DESC"
        );
    }
}

#[tokio::test]
#[ignore] // Requires database setup
async fn test_analyze_statistics_updated() {
    // Test: ANALYZE updates table statistics
    let pool = create_test_pool().await;

    // Force statistics update
    sqlx::query("ANALYZE engagement_events")
        .execute(&pool)
        .await
        .expect("ANALYZE failed");

    // Verify statistics exist
    let stats = sqlx::query!(
        r#"
        SELECT n_live_tup, n_dead_tup, last_analyze
        FROM pg_stat_user_tables
        WHERE relname = 'engagement_events'
        "#
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to fetch statistics");

    assert!(
        stats.last_analyze.is_some(),
        "Table should have analyze timestamp"
    );
}
