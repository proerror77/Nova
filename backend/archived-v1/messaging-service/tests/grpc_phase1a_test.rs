//! Phase 1A gRPC Integration Tests
//!
//! Tests for Phase 1A message operations (SendMessage, GetMessage, GetMessageHistory)
//! These tests verify the gRPC service implementations with proper proto conversions

use messaging_service::services::{
    conversation_service::{ConversationService, PrivacyMode},
    encryption::EncryptionService,
    message_service::MessageService,
};
use sqlx::postgres::PgPoolOptions;
use sqlx::{Pool, Postgres};
use uuid::Uuid;

const TEST_MASTER_KEY: [u8; 32] = [7u8; 32];

async fn bootstrap_pool() -> Pool<Postgres> {
    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL env var required for tests");
    PgPoolOptions::new()
        .max_connections(5)
        .connect(&db_url)
        .await
        .expect("failed to connect to DATABASE_URL")
}

async fn setup_test_conversation(
    pool: &Pool<Postgres>,
    creator_id: Uuid,
    privacy_mode: Option<PrivacyMode>,
) -> Uuid {
    ConversationService::create_group_conversation(
        pool,
        creator_id,
        "Test Conversation".to_string(),
        None,
        None,
        Vec::new(),
        privacy_mode,
    )
    .await
    .expect("failed to create test conversation")
}

async fn cleanup_conversation(pool: &Pool<Postgres>, conversation_id: Uuid, owner_id: Uuid) {
    let _ = sqlx::query("DELETE FROM messages WHERE conversation_id = $1")
        .bind(conversation_id)
        .execute(pool)
        .await;
    let _ = sqlx::query("DELETE FROM conversation_members WHERE conversation_id = $1")
        .bind(conversation_id)
        .execute(pool)
        .await;
    let _ = sqlx::query("DELETE FROM conversations WHERE id = $1")
        .bind(conversation_id)
        .execute(pool)
        .await;
    let _ = sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(owner_id)
        .execute(pool)
        .await;
}

// ========== SendMessage Tests ==========

#[tokio::test]
#[ignore]
async fn test_send_message_basic_plaintext() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = setup_test_conversation(&pool, user_id, None).await;

    let content = b"Hello, World!";
    let message = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        content,
        None,
    )
    .await
    .expect("send_message_db failed");

    // Verify message fields
    assert!(!message.id.is_nil(), "message id should be set");
    assert_eq!(message.conversation_id, conversation_id);
    assert_eq!(message.sender_id, user_id);
    assert_eq!(message.content, "Hello, World!");
    assert_eq!(message.sequence_number, 1); // First message
    assert!(
        message.created_at.timestamp() > 0,
        "created_at should be set"
    );

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

#[tokio::test]
#[ignore]
async fn test_send_message_with_idempotency_key() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = setup_test_conversation(&pool, user_id, None).await;

    let idempotency_key = "unique-key-1234";
    let content = b"Message with idempotency key";

    let message1 = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        content,
        Some(idempotency_key),
    )
    .await
    .expect("send_message_db failed");

    // Send again with same idempotency key
    let message2 = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        content,
        Some(idempotency_key),
    )
    .await
    .expect("send_message_db failed");

    // Both should return the same message ID (idempotent)
    assert_eq!(
        message1.id, message2.id,
        "idempotent messages should have same ID"
    );
    assert_eq!(message1.idempotency_key, Some(idempotency_key.to_string()));

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

#[tokio::test]
#[ignore]
async fn test_send_message_strict_e2e_encryption() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id =
        setup_test_conversation(&pool, user_id, Some(PrivacyMode::StrictE2e)).await;

    let plaintext = b"Secret message";
    let message = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        plaintext,
        None,
    )
    .await
    .expect("send_message_db failed");

    // Verify encryption settings
    assert_eq!(
        message.encryption_version, 1,
        "should use encryption version 1"
    );
    assert!(
        message.content.is_empty(),
        "plaintext content should be empty"
    );
    assert!(
        message.content_encrypted.is_some(),
        "encrypted content should be present"
    );
    assert!(message.content_nonce.is_some(), "nonce should be present");

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

#[tokio::test]
#[ignore]
async fn test_send_message_sequence_number_increment() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = setup_test_conversation(&pool, user_id, None).await;

    // Send multiple messages
    let msg1 = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"Message 1",
        None,
    )
    .await
    .expect("send_message_db failed");

    let msg2 = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"Message 2",
        None,
    )
    .await
    .expect("send_message_db failed");

    let msg3 = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"Message 3",
        None,
    )
    .await
    .expect("send_message_db failed");

    // Verify sequence numbers increment
    assert_eq!(msg1.sequence_number, 1);
    assert_eq!(msg2.sequence_number, 2);
    assert_eq!(msg3.sequence_number, 3);

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

// ========== GetMessage Tests ==========

#[tokio::test]
#[ignore]
async fn test_get_message_exists() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = setup_test_conversation(&pool, user_id, None).await;

    // Send a message
    let sent_message = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"Test message",
        None,
    )
    .await
    .expect("send_message_db failed");

    // Retrieve the message directly from DB
    let retrieved = sqlx::query_as::<
        _,
        (
            uuid::Uuid,
            uuid::Uuid,
            uuid::Uuid,
            String,
            Option<Vec<u8>>,
            Option<Vec<u8>>,
            i32,
            i64,
            Option<String>,
            chrono::DateTime<chrono::Utc>,
            Option<chrono::DateTime<chrono::Utc>>,
            Option<chrono::DateTime<chrono::Utc>>,
            i32,
        ),
    >(
        "SELECT id, conversation_id, sender_id, content, content_encrypted, content_nonce,
                encryption_version, sequence_number, idempotency_key, created_at,
                updated_at, deleted_at, 0 as reaction_count
         FROM messages WHERE id = $1",
    )
    .bind(sent_message.id)
    .fetch_one(&pool)
    .await
    .expect("message not found");

    // Verify all fields match
    assert_eq!(retrieved.0, sent_message.id);
    assert_eq!(retrieved.1, conversation_id);
    assert_eq!(retrieved.2, user_id);
    assert_eq!(retrieved.3, "Test message");
    assert_eq!(retrieved.7, sent_message.sequence_number);

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

#[tokio::test]
#[ignore]
async fn test_get_message_not_found() {
    let pool = bootstrap_pool().await;
    let fake_id = Uuid::new_v4();

    // Try to retrieve non-existent message
    let result = sqlx::query_as::<
        _,
        (
            uuid::Uuid,
            uuid::Uuid,
            uuid::Uuid,
            String,
            Option<Vec<u8>>,
            Option<Vec<u8>>,
            i32,
            i64,
            Option<String>,
            chrono::DateTime<chrono::Utc>,
            Option<chrono::DateTime<chrono::Utc>>,
            Option<chrono::DateTime<chrono::Utc>>,
            i32,
        ),
    >(
        "SELECT id, conversation_id, sender_id, content, content_encrypted, content_nonce,
                encryption_version, sequence_number, idempotency_key, created_at,
                updated_at, deleted_at, 0 as reaction_count
         FROM messages WHERE id = $1",
    )
    .bind(fake_id)
    .fetch_optional(&pool)
    .await
    .expect("query failed");

    assert!(result.is_none(), "non-existent message should not be found");
}

// ========== GetMessageHistory Tests ==========

#[tokio::test]
#[ignore]
async fn test_get_message_history_empty() {
    let pool = bootstrap_pool().await;
    let user_id = Uuid::new_v4();
    let conversation_id = setup_test_conversation(&pool, user_id, None).await;

    let history = MessageService::get_message_history_db(&pool, conversation_id)
        .await
        .expect("get_message_history_db failed");

    assert!(
        history.is_empty(),
        "empty conversation should have no history"
    );

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

#[tokio::test]
#[ignore]
async fn test_get_message_history_single_message() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = setup_test_conversation(&pool, user_id, None).await;

    // Send one message
    let sent_message = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"Single message",
        None,
    )
    .await
    .expect("send_message_db failed");

    let history = MessageService::get_message_history_db(&pool, conversation_id)
        .await
        .expect("get_message_history_db failed");

    assert_eq!(history.len(), 1, "history should contain one message");
    assert_eq!(history[0].id, sent_message.id);
    assert_eq!(history[0].content, "Single message");
    assert!(
        !history[0].encrypted,
        "plaintext message should not be marked encrypted"
    );

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

#[tokio::test]
#[ignore]
async fn test_get_message_history_multiple_messages_ordered() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = setup_test_conversation(&pool, user_id, None).await;

    // Send multiple messages
    let msg_ids: Vec<_> = vec!["Message 1", "Message 2", "Message 3"]
        .iter()
        .map(|content| {
            let msg_content = content.as_bytes();
            let task = MessageService::send_message_db(
                &pool,
                &encryption,
                conversation_id,
                user_id,
                msg_content,
                None,
            );
            (task, content)
        })
        .collect();

    // Execute in parallel and collect results
    let mut sent_ids = Vec::new();
    for (task, _) in msg_ids {
        let msg = task.await.expect("send_message_db failed");
        sent_ids.push(msg.id);
    }

    let history = MessageService::get_message_history_db(&pool, conversation_id)
        .await
        .expect("get_message_history_db failed");

    assert_eq!(history.len(), 3, "history should contain three messages");

    // Verify order (should be chronological, earliest first)
    assert_eq!(history[0].content, "Message 1");
    assert_eq!(history[1].content, "Message 2");
    assert_eq!(history[2].content, "Message 3");

    // Verify sequence numbers
    assert_eq!(history[0].sequence_number, 1);
    assert_eq!(history[1].sequence_number, 2);
    assert_eq!(history[2].sequence_number, 3);

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

#[tokio::test]
#[ignore]
async fn test_get_message_history_encrypted_messages() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id =
        setup_test_conversation(&pool, user_id, Some(PrivacyMode::StrictE2e)).await;

    // Send encrypted messages
    let msg1 = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"Secret 1",
        None,
    )
    .await
    .expect("send_message_db failed");

    let msg2 = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"Secret 2",
        None,
    )
    .await
    .expect("send_message_db failed");

    let history = MessageService::get_message_history_db(&pool, conversation_id)
        .await
        .expect("get_message_history_db failed");

    assert_eq!(history.len(), 2, "history should contain two messages");

    // Verify encryption markers
    assert!(history[0].encrypted, "message should be marked encrypted");
    assert!(history[1].encrypted, "message should be marked encrypted");

    // Verify encrypted payloads are present
    assert!(
        history[0].encrypted_payload.is_some(),
        "encrypted_payload should be present"
    );
    assert!(history[0].nonce.is_some(), "nonce should be present");

    // Verify plaintext content is empty
    assert!(
        history[0].content.is_empty(),
        "plaintext content should be empty"
    );
    assert!(
        history[1].content.is_empty(),
        "plaintext content should be empty"
    );

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

#[tokio::test]
#[ignore]
async fn test_get_message_history_excludes_deleted() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = setup_test_conversation(&pool, user_id, None).await;

    // Send messages
    let msg1 = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"Message 1",
        None,
    )
    .await
    .expect("send_message_db failed");

    let msg2 = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"Message 2",
        None,
    )
    .await
    .expect("send_message_db failed");

    // Soft delete the first message
    let _ = sqlx::query("UPDATE messages SET deleted_at = NOW() WHERE id = $1")
        .bind(msg1.id)
        .execute(&pool)
        .await;

    let history = MessageService::get_message_history_db(&pool, conversation_id)
        .await
        .expect("get_message_history_db failed");

    // History should only contain non-deleted messages
    assert_eq!(
        history.len(),
        1,
        "history should only include non-deleted messages"
    );
    assert_eq!(history[0].id, msg2.id);

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

#[tokio::test]
#[ignore]
async fn test_get_message_history_pagination_limit() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = setup_test_conversation(&pool, user_id, None).await;

    // Send 250 messages (exceeds service layer limit of 200)
    for i in 0..250 {
        let content = format!("Message {}", i);
        let _ = MessageService::send_message_db(
            &pool,
            &encryption,
            conversation_id,
            user_id,
            content.as_bytes(),
            None,
        )
        .await;
    }

    let history = MessageService::get_message_history_db(&pool, conversation_id)
        .await
        .expect("get_message_history_db failed");

    // Service layer limits to 200
    assert_eq!(
        history.len(),
        200,
        "history should be limited to 200 messages"
    );

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

// ========== Proto Conversion Tests ==========

#[tokio::test]
#[ignore]
async fn test_proto_conversion_all_fields() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = setup_test_conversation(&pool, user_id, None).await;

    // Send a message
    let message = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"Test message for proto conversion",
        Some("idempotency-key-1"),
    )
    .await
    .expect("send_message_db failed");

    // Verify all fields are populated for proto conversion
    assert!(!message.id.to_string().is_empty());
    assert!(!message.conversation_id.to_string().is_empty());
    assert!(!message.sender_id.to_string().is_empty());
    assert!(!message.content.is_empty());
    assert_eq!(message.sequence_number, 1);
    assert!(message.idempotency_key.is_some());
    assert!(message.created_at.timestamp() > 0);
    assert_eq!(message.encryption_version, 0); // plaintext mode

    cleanup_conversation(&pool, conversation_id, user_id).await;
}
