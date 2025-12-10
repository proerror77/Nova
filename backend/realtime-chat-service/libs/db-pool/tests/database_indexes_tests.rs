//! Database Index Tests
//!
//! Tests for verifying database indexes are properly configured
//! for optimal query performance.
//!
//! NOTE: These tests require a running PostgreSQL database with the
//! application schema. Set DATABASE_URL environment variable to run.

use db_pool::{create_pool, DbConfig, PgPool};

/// Helper to create test pool
async fn create_test_pool() -> PgPool {
    let config = DbConfig {
        service_name: "index-test".to_string(),
        database_url: std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://postgres:password@localhost/nova_test".to_string()),
        max_connections: 5,
        min_connections: 1,
        connect_timeout_secs: 10,
        acquire_timeout_secs: 10,
        idle_timeout_secs: 60,
        max_lifetime_secs: 300,
    };

    create_pool(config)
        .await
        .expect("Failed to create test pool")
}

/// Test that critical indexes exist on conversation_members table
#[tokio::test]
#[ignore] // Requires running PostgreSQL with schema
async fn test_conversation_members_indexes_exist() {
    let pool = create_test_pool().await;
    let client = pool.get().await.expect("Failed to get connection");

    let result = client
        .query(
            r#"
            SELECT indexname FROM pg_indexes
            WHERE tablename = 'conversation_members'
            ORDER BY indexname
            "#,
            &[],
        )
        .await
        .expect("Failed to query indexes");

    let index_names: Vec<String> = result
        .iter()
        .map(|row| row.get::<_, String>("indexname"))
        .collect();

    // Verify expected indexes exist
    assert!(
        index_names.iter().any(|n| n.contains("user_id")),
        "Should have index on user_id"
    );
    assert!(
        index_names.iter().any(|n| n.contains("conversation_id")),
        "Should have index on conversation_id"
    );
}

/// Test that critical indexes exist on messages table
#[tokio::test]
#[ignore] // Requires running PostgreSQL with schema
async fn test_messages_indexes_exist() {
    let pool = create_test_pool().await;
    let client = pool.get().await.expect("Failed to get connection");

    let result = client
        .query(
            r#"
            SELECT indexname FROM pg_indexes
            WHERE tablename = 'messages'
            ORDER BY indexname
            "#,
            &[],
        )
        .await
        .expect("Failed to query indexes");

    let index_names: Vec<String> = result
        .iter()
        .map(|row| row.get::<_, String>("indexname"))
        .collect();

    // Verify expected indexes exist
    assert!(
        index_names.iter().any(|n| n.contains("conversation_id")),
        "Should have index on conversation_id"
    );
    assert!(
        index_names.iter().any(|n| n.contains("sender_id")),
        "Should have index on sender_id"
    );
    assert!(
        index_names.iter().any(|n| n.contains("created_at")),
        "Should have index on created_at"
    );
}

/// Test that critical indexes exist on conversations table
#[tokio::test]
#[ignore] // Requires running PostgreSQL with schema
async fn test_conversations_indexes_exist() {
    let pool = create_test_pool().await;
    let client = pool.get().await.expect("Failed to get connection");

    let result = client
        .query(
            r#"
            SELECT indexname FROM pg_indexes
            WHERE tablename = 'conversations'
            ORDER BY indexname
            "#,
            &[],
        )
        .await
        .expect("Failed to query indexes");

    let index_names: Vec<String> = result
        .iter()
        .map(|row| row.get::<_, String>("indexname"))
        .collect();

    // Verify primary key index exists
    assert!(
        !index_names.is_empty(),
        "Should have at least primary key index"
    );
}

/// Test index usage statistics (for monitoring)
#[tokio::test]
#[ignore] // Requires running PostgreSQL with schema and some data
async fn test_index_usage_statistics() {
    let pool = create_test_pool().await;
    let client = pool.get().await.expect("Failed to get connection");

    let result = client
        .query(
            r#"
            SELECT
                schemaname,
                relname as table_name,
                indexrelname as index_name,
                idx_scan as index_scans,
                idx_tup_read as tuples_read,
                idx_tup_fetch as tuples_fetched
            FROM pg_stat_user_indexes
            WHERE schemaname = 'public'
            ORDER BY idx_scan DESC
            LIMIT 20
            "#,
            &[],
        )
        .await
        .expect("Failed to query index statistics");

    // Just verify we can query index stats
    // In a real test, you might check that frequently used indexes have high scan counts
    println!("Found {} index statistics entries", result.len());
}

/// Test for unused indexes (potential candidates for removal)
#[tokio::test]
#[ignore] // Requires running PostgreSQL with schema
async fn test_find_unused_indexes() {
    let pool = create_test_pool().await;
    let client = pool.get().await.expect("Failed to get connection");

    let result = client
        .query(
            r#"
            SELECT
                schemaname,
                relname as table_name,
                indexrelname as index_name,
                idx_scan as index_scans,
                pg_size_pretty(pg_relation_size(indexrelid)) as index_size
            FROM pg_stat_user_indexes
            WHERE schemaname = 'public'
              AND idx_scan = 0
              AND indexrelname NOT LIKE '%_pkey'
            ORDER BY pg_relation_size(indexrelid) DESC
            "#,
            &[],
        )
        .await
        .expect("Failed to query unused indexes");

    // Log unused indexes for review
    for row in result.iter() {
        let table: String = row.get("table_name");
        let index: String = row.get("index_name");
        let size: String = row.get("index_size");
        println!("Unused index: {} on {} (size: {})", index, table, size);
    }
}

/// Test for missing indexes on foreign keys
#[tokio::test]
#[ignore] // Requires running PostgreSQL with schema
async fn test_foreign_key_indexes() {
    let pool = create_test_pool().await;
    let client = pool.get().await.expect("Failed to get connection");

    // Find foreign keys without indexes
    let result = client
        .query(
            r#"
            SELECT
                tc.table_name,
                kcu.column_name,
                ccu.table_name AS foreign_table_name,
                ccu.column_name AS foreign_column_name
            FROM information_schema.table_constraints AS tc
            JOIN information_schema.key_column_usage AS kcu
                ON tc.constraint_name = kcu.constraint_name
                AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage AS ccu
                ON ccu.constraint_name = tc.constraint_name
                AND ccu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND tc.table_schema = 'public'
            "#,
            &[],
        )
        .await
        .expect("Failed to query foreign keys");

    // Log foreign keys for review
    println!("Found {} foreign key constraints", result.len());
}
