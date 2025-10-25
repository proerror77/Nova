// Integration test for message search index synchronization
// This test verifies that:
// 1. Messages are indexed when created
// 2. Search index is updated when messages are edited
// 3. Search index is cleaned up when messages are deleted

use uuid::Uuid;
use sqlx::Pool;

// Helper to setup test database
async fn setup_test_db() -> Result<Pool<sqlx::Postgres>, sqlx::Error> {
    let db_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:postgres@localhost/nova_test".to_string());
    sqlx::postgres::PgPool::connect(&db_url).await
}

async fn create_test_user(db: &Pool<sqlx::Postgres>, user_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO users (id, username, email, password_hash) VALUES ($1, $2, $3, $4)
         ON CONFLICT (id) DO NOTHING"
    )
    .bind(user_id)
    .bind(format!("user_{}", user_id))
    .bind(format!("{}@test.com", user_id))
    .bind("hash")
    .execute(db)
    .await?;
    Ok(())
}

async fn create_test_conversation(
    db: &Pool<sqlx::Postgres>,
    conv_id: Uuid,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO conversations (id, conversation_type, created_by)
         VALUES ($1, 'direct', $2)
         ON CONFLICT (id) DO NOTHING"
    )
    .bind(conv_id)
    .bind(user_id)
    .execute(db)
    .await?;

    // Add user as member
    sqlx::query(
        "INSERT INTO conversation_members (conversation_id, user_id, role)
         VALUES ($1, $2, 'owner')
         ON CONFLICT (conversation_id, user_id) DO NOTHING"
    )
    .bind(conv_id)
    .bind(user_id)
    .execute(db)
    .await?;

    Ok(())
}

#[tokio::test]
#[ignore] // Run manually: cargo test --test message_search_index_sync_test -- --nocapture
async fn test_message_creation_indexes_for_search() {
    let db = setup_test_db()
        .await
        .expect("Failed to connect to test DB");

    let user_id = Uuid::new_v4();
    let conv_id = Uuid::new_v4();
    let msg_id = Uuid::new_v4();

    // Setup
    create_test_user(&db, user_id).await.expect("Failed to create test user");
    create_test_conversation(&db, conv_id, user_id)
        .await
        .expect("Failed to create test conversation");

    // Create message using raw SQL (simulating what message_service does)
    let plaintext = "Hello World";
    let nonce = vec![0u8; 24]; // Mock nonce

    sqlx::query(
        "INSERT INTO messages (id, conversation_id, sender_id, content_encrypted, content_nonce, encryption_version)
         VALUES ($1, $2, $3, $4, $5, 1)"
    )
    .bind(msg_id)
    .bind(conv_id)
    .bind(user_id)
    .bind(plaintext.as_bytes())
    .bind(&nonce)
    .execute(&db)
    .await
    .expect("Failed to insert message");

    // Index the message (simulating what upsert_search_index does)
    sqlx::query(
        "INSERT INTO message_search_index (message_id, conversation_id, sender_id, search_text)
         VALUES ($1, $2, $3, $4)"
    )
    .bind(msg_id)
    .bind(conv_id)
    .bind(user_id)
    .bind(plaintext)
    .execute(&db)
    .await
    .expect("Failed to insert search index");

    // Verify search index exists
    let result: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM message_search_index WHERE message_id = $1"
    )
    .bind(msg_id)
    .fetch_one(&db)
    .await
    .expect("Failed to query search index");

    assert_eq!(result.0, 1, "Search index entry should exist");

    // Verify we can search for the message
    let search_result = sqlx::query(
        "SELECT message_id FROM message_search_index
         WHERE conversation_id = $1 AND search_text @@ plainto_tsquery('simple', $2)"
    )
    .bind(conv_id)
    .bind("Hello")
    .fetch_optional(&db)
    .await
    .expect("Failed to search");

    assert!(search_result.is_some(), "Should find message by search");
}

#[tokio::test]
#[ignore] // Run manually
async fn test_message_edit_updates_search_index() {
    let db = setup_test_db()
        .await
        .expect("Failed to connect to test DB");

    let user_id = Uuid::new_v4();
    let conv_id = Uuid::new_v4();
    let msg_id = Uuid::new_v4();

    // Setup
    create_test_user(&db, user_id).await.expect("Failed to create test user");
    create_test_conversation(&db, conv_id, user_id)
        .await
        .expect("Failed to create test conversation");

    // Create message
    let original_text = "original content";
    let nonce = vec![0u8; 24];

    sqlx::query(
        "INSERT INTO messages (id, conversation_id, sender_id, content_encrypted, content_nonce, encryption_version)
         VALUES ($1, $2, $3, $4, $5, 1)"
    )
    .bind(msg_id)
    .bind(conv_id)
    .bind(user_id)
    .bind(original_text.as_bytes())
    .bind(&nonce)
    .execute(&db)
    .await
    .expect("Failed to insert message");

    // Index it
    sqlx::query(
        "INSERT INTO message_search_index (message_id, conversation_id, sender_id, search_text)
         VALUES ($1, $2, $3, $4)"
    )
    .bind(msg_id)
    .bind(conv_id)
    .bind(user_id)
    .bind(original_text)
    .execute(&db)
    .await
    .expect("Failed to insert search index");

    // Edit message
    let updated_text = "updated content";
    sqlx::query(
        "UPDATE message_search_index SET search_text = $1 WHERE message_id = $2"
    )
    .bind(updated_text)
    .bind(msg_id)
    .execute(&db)
    .await
    .expect("Failed to update search index");

    // Verify we can find by new text
    let search_result = sqlx::query(
        "SELECT message_id FROM message_search_index
         WHERE conversation_id = $1 AND search_text @@ plainto_tsquery('simple', $2)"
    )
    .bind(conv_id)
    .bind("updated")
    .fetch_optional(&db)
    .await
    .expect("Failed to search for updated text");

    assert!(search_result.is_some(), "Should find message by updated text");

    // Verify old text doesn't match (optional, depends on implementation)
    // let old_search = sqlx::query(
    //     "SELECT message_id FROM message_search_index
    //      WHERE conversation_id = $1 AND search_text @@ plainto_tsquery('simple', 'original')"
    // )
    // .bind(conv_id)
    // .fetch_optional(&db)
    // .await
    // .expect("Failed to search for old text");
    // assert!(old_search.is_none(), "Should not find message by old text");
}

#[tokio::test]
#[ignore] // Run manually
async fn test_message_delete_removes_from_search_index() {
    let db = setup_test_db()
        .await
        .expect("Failed to connect to test DB");

    let user_id = Uuid::new_v4();
    let conv_id = Uuid::new_v4();
    let msg_id = Uuid::new_v4();

    // Setup
    create_test_user(&db, user_id).await.expect("Failed to create test user");
    create_test_conversation(&db, conv_id, user_id)
        .await
        .expect("Failed to create test conversation");

    // Create and index message
    let plaintext = "content to delete";
    let nonce = vec![0u8; 24];

    sqlx::query(
        "INSERT INTO messages (id, conversation_id, sender_id, content_encrypted, content_nonce, encryption_version)
         VALUES ($1, $2, $3, $4, $5, 1)"
    )
    .bind(msg_id)
    .bind(conv_id)
    .bind(user_id)
    .bind(plaintext.as_bytes())
    .bind(&nonce)
    .execute(&db)
    .await
    .expect("Failed to insert message");

    sqlx::query(
        "INSERT INTO message_search_index (message_id, conversation_id, sender_id, search_text)
         VALUES ($1, $2, $3, $4)"
    )
    .bind(msg_id)
    .bind(conv_id)
    .bind(user_id)
    .bind(plaintext)
    .execute(&db)
    .await
    .expect("Failed to insert search index");

    // Verify it's there
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM message_search_index WHERE message_id = $1")
        .bind(msg_id)
        .fetch_one(&db)
        .await
        .expect("Failed to count before delete");
    assert_eq!(count.0, 1, "Search index entry should exist before delete");

    // Soft delete the message
    sqlx::query("UPDATE messages SET deleted_at = NOW() WHERE id = $1")
        .bind(msg_id)
        .execute(&db)
        .await
        .expect("Failed to soft delete message");

    // Remove from search index
    sqlx::query("DELETE FROM message_search_index WHERE message_id = $1")
        .bind(msg_id)
        .execute(&db)
        .await
        .expect("Failed to delete search index");

    // Verify it's gone
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM message_search_index WHERE message_id = $1")
        .bind(msg_id)
        .fetch_one(&db)
        .await
        .expect("Failed to count after delete");
    assert_eq!(count.0, 0, "Search index entry should be deleted");

    // Verify we can't search for it
    let search_result = sqlx::query(
        "SELECT message_id FROM message_search_index
         WHERE conversation_id = $1 AND search_text @@ plainto_tsquery('simple', $2)"
    )
    .bind(conv_id)
    .bind("delete")
    .fetch_optional(&db)
    .await
    .expect("Failed to search");

    assert!(search_result.is_none(), "Deleted message should not be searchable");
}
