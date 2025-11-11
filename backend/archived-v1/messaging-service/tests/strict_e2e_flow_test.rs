use messaging_service::services::{
    conversation_service::{ConversationService, PrivacyMode},
    encryption::EncryptionService,
    message_service::MessageService,
};
use sqlx::postgres::PgPoolOptions;
use sqlx::Row;
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

async fn seed_strict_conversation(pool: &Pool<Postgres>, creator_id: Uuid) -> Uuid {
    ConversationService::create_group_conversation(
        pool,
        creator_id,
        "Strict Test Group".to_string(),
        None,
        None,
        Vec::new(),
        Some(PrivacyMode::StrictE2e),
    )
    .await
    .expect("failed to create strict conversation")
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

#[tokio::test]
#[ignore]
async fn strict_e2e_message_roundtrip() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = seed_strict_conversation(&pool, user_id).await;

    let plaintext = b"hello secure world";
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

    let row =
        sqlx::query("SELECT content, content_encrypted, content_nonce FROM messages WHERE id = $1")
            .bind(message.id)
            .fetch_one(&pool)
            .await
            .expect("message fetch failed");

    let stored_content: String = row.get("content");
    assert!(
        stored_content.is_empty(),
        "plaintext content should be blank"
    );

    let ciphertext: Vec<u8> = row.get("content_encrypted");
    let nonce: Vec<u8> = row.get("content_nonce");
    assert!(!ciphertext.is_empty(), "ciphertext should be present");
    assert_eq!(nonce.len(), 24);

    let history = MessageService::get_message_history_db(&pool, conversation_id)
        .await
        .expect("history fetch failed");
    let msg = history
        .first()
        .expect("history should include inserted message");
    assert!(msg.encrypted);
    assert!(msg.encrypted_payload.is_some());
    assert!(msg.nonce.is_some());
    assert!(msg.content.is_empty());

    cleanup_conversation(&pool, conversation_id, user_id).await;
}

#[tokio::test]
#[ignore]
async fn strict_e2e_version_and_audio_flow() {
    let pool = bootstrap_pool().await;
    let encryption = EncryptionService::new(TEST_MASTER_KEY);
    let user_id = Uuid::new_v4();
    let conversation_id = seed_strict_conversation(&pool, user_id).await;

    let message = MessageService::send_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        b"original",
        None,
    )
    .await
    .expect("send_message_db failed");

    MessageService::update_message_db(&pool, &encryption, message.id, b"updated")
        .await
        .expect("update_message_db failed");

    let version_row = sqlx::query("SELECT version_number FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_one(&pool)
        .await
        .expect("version fetch failed");
    let version_after_update: i32 = version_row.get("version_number");
    assert!(version_after_update > 1);

    let conflict =
        sqlx::query("UPDATE messages SET content = $1 WHERE id = $2 AND version_number = $3")
            .bind("should_not_apply")
            .bind(message_id)
            .bind(version_after_update - 1)
            .execute(&pool)
            .await
            .expect("conflict update execution");
    assert_eq!(
        conflict.rows_affected(),
        0,
        "stale version should not update"
    );

    let (_audio_id, _) = MessageService::send_audio_message_db(
        &pool,
        &encryption,
        conversation_id,
        user_id,
        "https://example.com/audio.opus",
        1_234,
        "opus",
        None,
    )
    .await
    .expect("send_audio_message_db failed");

    cleanup_conversation(&pool, conversation_id, user_id).await;
}
